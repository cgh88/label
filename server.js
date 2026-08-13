const path = require('path');
const fs = require('fs');
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const crypto = require('crypto');
const multer = require('multer');
const xlsx = require('xlsx');

const app = express();
const PORT = process.env.PORT || 3000;
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'database.sqlite');
const SESSION_MAX_AGE_MS = 2 * 60 * 60 * 1000;
const SCRYPT_KEY_LENGTH = 64;
const SCRYPT_PARAMS = { N: 16384, r: 8, p: 1 };
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_MAX_FAILURES = 10;
const PUBLIC_FILES = new Map([
    ['/', 'index.html'],
    ['/index.html', 'index.html'],
    ['/app.js', 'app.js'],
    ['/style.css', 'style.css'],
]);

// ==========================================
// Default Seed Data (single source: default_database.json)
// ==========================================
function loadDefaultSeedData() {
    const filePath = path.join(__dirname, 'default_database.json');
    const raw = fs.readFileSync(filePath, 'utf8');
    const parsed = JSON.parse(raw);

    const locationsById = {};
    (parsed.storage_locations || []).forEach(l => { locationsById[l.id] = l; });

    const ingredients = (parsed.ingredients_v2 || []).map(i => ({
        category: i.category,
        name: i.name,
        abbr: i.abbr || '',
        storage: {}
    }));
    const ingredientsByName = {};
    ingredients.forEach(i => { ingredientsByName[i.name] = i; });
    (parsed.ingredient_storage || []).forEach(m => {
        const ing = ingredientsByName[m.ingredient_name];
        const loc = locationsById[m.storage_id];
        if (ing && loc) ing.storage[loc.name] = m.shelf_days;
    });

    return {
        categories: (parsed.categories || []).map(c => ({ name: c.name, emoji: c.emoji || '', sort_order: c.sort_order || 0 })),
        storageLocations: (parsed.storage_locations || []).map(l => ({ name: l.name, sort_order: l.sort_order || 0, unit: l.unit || 'day' })),
        labelSizes: (parsed.label_sizes || []).map(s => ({ width: s.width, height: s.height, is_default: s.is_default ? 1 : 0 })),
        ingredients
    };
}

const MINIMAL_FALLBACK_SEED = {
    categories: [{ name: "기타", emoji: "🍕", sort_order: 1 }],
    storageLocations: [{ name: "메이크라인", sort_order: 1, unit: "day" }],
    labelSizes: [{ width: 50, height: 30, is_default: 1 }],
    ingredients: []
};

let SEED_DATA;
try {
    SEED_DATA = loadDefaultSeedData();
    if (!SEED_DATA.categories.length || !SEED_DATA.ingredients.length) {
        console.warn('default_database.json is incomplete; using minimal fallback seed data.');
        SEED_DATA = MINIMAL_FALLBACK_SEED;
    }
} catch (e) {
    console.warn('Failed to load default_database.json; using minimal fallback seed data:', e.message);
    SEED_DATA = MINIMAL_FALLBACK_SEED;
}

const DEFAULT_CATEGORIES = SEED_DATA.categories;
const DEFAULT_STORAGE_LOCATIONS = SEED_DATA.storageLocations;
const DEFAULT_LABEL_SIZES = SEED_DATA.labelSizes;
const DEFAULT_INGREDIENTS = SEED_DATA.ingredients;

// ==========================================
// Express Setup
// ==========================================
const sessions = {}; // key: token, value: { username, role, expiresAt }
const loginFailures = new Map(); // key: ip + username, value: { count, resetAt }

const SERVER_START_TIME = Date.now();

app.use(express.json({ limit: '2mb' }));

// Structured HTTP Request Logging
app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
        const duration = Date.now() - start;
        if (req.path !== '/api/health' && process.env.NODE_ENV !== 'test') {
            console.log(`[HTTP] ${new Date().toISOString()} | ${req.method} ${req.path} | ${res.statusCode} | ${duration}ms`);
        }
    });
    next();
});

// Auto-initialize DB if not already running
app.use(async (req, res, next) => {
    try {
        await startDatabase();
        next();
    } catch (err) {
        res.status(500).json({ error: 'Database initialization error: ' + err.message });
    }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
    const isDbConnected = db !== null;
    res.json({
        status: isDbConnected ? 'ok' : 'degraded',
        uptimeSeconds: Math.floor((Date.now() - SERVER_START_TIME) / 1000),
        database: isDbConnected ? 'connected' : 'disconnected',
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

app.get(Array.from(PUBLIC_FILES.keys()), (req, res) => {
    const fileName = PUBLIC_FILES.get(req.path);
    res.sendFile(path.join(__dirname, fileName));
});

// Custom Cookie Parser Middleware
app.use((req, res, next) => {
    const list = {};
    const rc = req.headers.cookie;
    if (rc) {
        rc.split(';').forEach(cookie => {
            const parts = cookie.split('=');
            list[parts.shift().trim()] = decodeURIComponent(parts.join('='));
        });
    }
    req.cookies = list;
    next();
});

function isSafePositiveInteger(value) {
    const n = Number(value);
    return Number.isInteger(n) && n > 0 && Number.isSafeInteger(n);
}

function isProduction() {
    return process.env.NODE_ENV === 'production';
}

function validateRuntimeSecurityConfig() {
    if (isProduction() && (!process.env.DEFAULT_ADMIN_PASSWORD || !process.env.DEFAULT_STAFF_PASSWORD)) {
        throw new Error('DEFAULT_ADMIN_PASSWORD and DEFAULT_STAFF_PASSWORD are required in production.');
    }
}

function sendServerError(res, err, userMessage = '서버 처리 중 오류가 발생했습니다.') {
    console.error('[SERVER ERROR]', err);
    if (!res.headersSent) {
        res.status(500).json({ error: userMessage });
    }
}

function getLoginFailureKey(req, username) {
    return `${req.ip || req.socket.remoteAddress || 'unknown'}:${String(username || '').toLowerCase()}`;
}

function isLoginRateLimited(req, username) {
    const key = getLoginFailureKey(req, username);
    const record = loginFailures.get(key);
    if (!record) return false;
    if (record.resetAt <= Date.now()) {
        loginFailures.delete(key);
        return false;
    }
    return record.count >= LOGIN_MAX_FAILURES;
}

function recordLoginFailure(req, username) {
    const key = getLoginFailureKey(req, username);
    const now = Date.now();
    const record = loginFailures.get(key);
    if (!record || record.resetAt <= now) {
        loginFailures.set(key, { count: 1, resetAt: now + LOGIN_WINDOW_MS });
        return;
    }
    record.count += 1;
}

function clearLoginFailures(req, username) {
    loginFailures.delete(getLoginFailureKey(req, username));
}

function isPasswordHash(value) {
    return typeof value === 'string' && value.startsWith('scrypt$');
}

function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    const key = crypto.scryptSync(password, salt, SCRYPT_KEY_LENGTH, SCRYPT_PARAMS).toString('hex');
    return `scrypt$${SCRYPT_PARAMS.N}$${SCRYPT_PARAMS.r}$${SCRYPT_PARAMS.p}$${salt}$${key}`;
}

function verifyLegacyPassword(password, storedHash) {
    const hash = crypto.createHash('sha256').update(password).digest('hex');
    return storedHash === hash;
}

function verifyPassword(password, storedHash) {
    if (!isPasswordHash(storedHash)) {
        return { valid: verifyLegacyPassword(password, storedHash), needsRehash: true };
    }

    const [scheme, n, r, p, salt, key] = storedHash.split('$');
    if (scheme !== 'scrypt' || !salt || !key) {
        return { valid: false, needsRehash: false };
    }

    const derived = crypto.scryptSync(password, salt, Buffer.from(key, 'hex').length, {
        N: Number(n),
        r: Number(r),
        p: Number(p),
    });
    const stored = Buffer.from(key, 'hex');
    return {
        valid: stored.length === derived.length && crypto.timingSafeEqual(stored, derived),
        needsRehash: Number(n) !== SCRYPT_PARAMS.N || Number(r) !== SCRYPT_PARAMS.r || Number(p) !== SCRYPT_PARAMS.p,
    };
}

// ==========================================
// IP Utilities & Admin Access Restrictions
// ==========================================
function normalizeIp(ip) {
    if (!ip || typeof ip !== 'string') return '';
    let cleaned = ip.trim();
    if (cleaned.startsWith('::ffff:')) {
        cleaned = cleaned.substring(7);
    }
    if (cleaned === '::1' || cleaned === 'localhost') {
        cleaned = '127.0.0.1';
    }
    return cleaned;
}

function getClientIp(req) {
    if (!req) return '127.0.0.1';
    const xForwardedFor = req.headers ? (req.headers['x-forwarded-for'] || req.headers['X-Forwarded-For']) : null;
    if (xForwardedFor && typeof xForwardedFor === 'string') {
        const ips = xForwardedFor.split(',');
        if (ips.length > 0 && ips[0].trim()) {
            return normalizeIp(ips[0]);
        }
    }
    const rawIp = req.ip || (req.socket ? req.socket.remoteAddress : null) || '127.0.0.1';
    return normalizeIp(rawIp);
}

async function getAdminAllowedIpsAsync() {
    try {
        const row = await allAsync("SELECT setting_value FROM system_settings WHERE setting_key = 'admin_allowed_ips'");
        if (row && row.length > 0) {
            return row[0].setting_value || '';
        }
    } catch (_) {}
    return '';
}

function checkIpMatch(clientIp, allowedIpsStr) {
    if (!allowedIpsStr || !allowedIpsStr.trim()) {
        return true; // Empty setting means unrestricted
    }
    const normalizedClient = normalizeIp(clientIp);
    const allowedList = allowedIpsStr.split(/[\s,]+/)
        .map(ip => normalizeIp(ip))
        .filter(ip => ip.length > 0);

    if (allowedList.length === 0) return true;
    return allowedList.includes(normalizedClient);
}

// ==========================================
// JWT Authentication Helpers & Session Verification
// ==========================================
const JWT_SECRET = process.env.JWT_SECRET || 'shelflife-label-jwt-secret-key-2026';

function base64UrlEncode(str) {
    return Buffer.from(str).toString('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
}

function base64UrlDecode(str) {
    let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
    while (base64.length % 4) base64 += '=';
    return Buffer.from(base64, 'base64').toString('utf8');
}

function createJwtToken(payload, secret = JWT_SECRET, expiresInMs = SESSION_MAX_AGE_MS) {
    const header = { alg: 'HS256', typ: 'JWT' };
    const now = Date.now();
    const fullPayload = {
        ...payload,
        iat: Math.floor(now / 1000),
        exp: Math.floor((now + expiresInMs) / 1000)
    };
    const encodedHeader = base64UrlEncode(JSON.stringify(header));
    const encodedPayload = base64UrlEncode(JSON.stringify(fullPayload));
    const signature = crypto.createHmac('sha256', secret)
        .update(`${encodedHeader}.${encodedPayload}`)
        .digest('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');
    return `${encodedHeader}.${encodedPayload}.${signature}`;
}

function verifyJwtToken(token, secret = JWT_SECRET) {
    if (!token || typeof token !== 'string') return null;
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const [encodedHeader, encodedPayload, signature] = parts;
    const expectedSignature = crypto.createHmac('sha256', secret)
        .update(`${encodedHeader}.${encodedPayload}`)
        .digest('base64')
        .replace(/=/g, '')
        .replace(/\+/g, '-')
        .replace(/\//g, '_');

    try {
        const sigBuf = Buffer.from(signature);
        const expBuf = Buffer.from(expectedSignature);
        if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
            return null;
        }

        const payload = JSON.parse(base64UrlDecode(encodedPayload));
        if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
            return null; // Token expired
        }
        return payload;
    } catch (_) {
        return null;
    }
}

function getActiveSession(req, res) {
    let token = null;

    // 1. Check Authorization: Bearer <token>
    const authHeader = req.headers['authorization'] || req.headers['Authorization'];
    if (authHeader && typeof authHeader === 'string' && authHeader.startsWith('Bearer ')) {
        token = authHeader.substring(7).trim();
    }

    // 2. Check Cookie session_token
    if (!token && req.cookies && req.cookies.session_token) {
        token = req.cookies.session_token;
    }

    if (!token) return null;

    // 3. Verify JWT
    const jwtPayload = verifyJwtToken(token);
    if (jwtPayload) {
        return { username: jwtPayload.username, role: jwtPayload.role, expiresAt: jwtPayload.exp * 1000 };
    }

    // 4. Fallback to legacy in-memory session mapping
    if (sessions[token]) {
        if (sessions[token].expiresAt < Date.now()) {
            delete sessions[token];
            if (res && res.clearCookie) res.clearCookie('session_token');
            return null;
        }
        return sessions[token];
    }

    return null;
}

function requireRole(role) {
    return async (req, res, next) => {
        const session = getActiveSession(req, res);
        if (!session) {
            return res.status(401).json({ error: '로그인이 필요합니다.' });
        }
        if (role && session.role !== role) {
            return res.status(403).json({ error: '관리자 권한이 필요합니다.' });
        }

        // Enforce IP Allowlist ONLY if explicit admin role is required (requireAdmin management operations)
        if (role === 'admin') {
            const allowedIpsStr = await getAdminAllowedIpsAsync();
            const clientIp = getClientIp(req);
            if (!checkIpMatch(clientIp, allowedIpsStr)) {
                return res.status(403).json({
                    error: `허용되지 않은 IP 주소입니다. 접속이 불가능합니다. (접속 IP: ${clientIp})`,
                    ipBlocked: true,
                    clientIp: clientIp
                });
            }
        }

        req.user = session;
        next();
    };
}

const requireLogin = requireRole();
const requireAdmin = requireRole('admin');

function runAsync(sql, params = []) {
    return new Promise((resolve, reject) => {
        db.run(sql, params, function(err) {
            if (err) reject(err);
            else resolve(this);
        });
    });
}

function finalizeAsync(stmt) {
    return new Promise((resolve, reject) => {
        stmt.finalize((err) => {
            if (err) reject(err);
            else resolve();
        });
    });
}

function allAsync(sql, params = []) {
    return new Promise((resolve, reject) => {
        db.all(sql, params, (err, rows) => {
            if (err) reject(err);
            else resolve(rows);
        });
    });
}

async function touchDbLastUpdatedAsync() {
    const nowIso = new Date().toISOString();
    await runAsync("INSERT OR REPLACE INTO db_metadata (key, value) VALUES ('last_updated', ?)", [nowIso]);
    return nowIso;
}

async function seedDefaultsAsync() {
    await runAsync("BEGIN TRANSACTION");
    try {
        const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, emoji, sort_order) VALUES (?, ?, ?)");
        for (const c of DEFAULT_CATEGORIES) {
            catStmt.run(c.name, c.emoji, c.sort_order);
        }
        await finalizeAsync(catStmt);

        const slStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order, unit) VALUES (?, ?, ?)");
        for (const s of DEFAULT_STORAGE_LOCATIONS) {
            slStmt.run(s.name, s.sort_order, s.unit || 'day');
        }
        await finalizeAsync(slStmt);

        const ingStmt = db.prepare("INSERT OR IGNORE INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
        for (const i of DEFAULT_INGREDIENTS) {
            ingStmt.run(i.name, i.category, i.abbr || '');
        }
        await finalizeAsync(ingStmt);

        const locations = await allAsync("SELECT id, name FROM storage_locations");
        const locMap = {};
        locations.forEach(l => { locMap[l.name] = l.id; });

        const stStmt = db.prepare("INSERT OR IGNORE INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
        for (const item of DEFAULT_INGREDIENTS) {
            for (const [locName, days] of Object.entries(item.storage)) {
                if (locMap[locName]) {
                    stStmt.run(item.name, locMap[locName], days);
                }
            }
        }
        await finalizeAsync(stStmt);

        const lsStmt = db.prepare("INSERT OR IGNORE INTO label_sizes (width, height, is_default) VALUES (?, ?, ?)");
        for (const s of DEFAULT_LABEL_SIZES) {
            lsStmt.run(s.width, s.height, s.is_default);
        }
        await finalizeAsync(lsStmt);

        await runAsync("COMMIT");
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        throw err;
    }
}

let db;
let dbInitPromise = null;

function getDbPath() {
    return process.env.DB_PATH || path.join(__dirname, 'database.sqlite');
}

function startDatabase(customPath) {
    if (dbInitPromise) return dbInitPromise;
    validateRuntimeSecurityConfig();
    const targetPath = customPath || getDbPath();

    if (targetPath !== ':memory:') {
        const dbDir = path.dirname(targetPath);
        if (!fs.existsSync(dbDir)) {
            fs.mkdirSync(dbDir, { recursive: true });
        }
    }

    dbInitPromise = new Promise((resolve, reject) => {
        db = new sqlite3.Database(targetPath, async (err) => {
            if (err) {
                console.error('Error opening database:', err.message);
                reject(err);
            } else {
                console.log('Connected to SQLite database at:', targetPath);
                db.run("PRAGMA foreign_keys = ON");
                try {
                    await initDatabaseAsync();
                    resolve(db);
                } catch (initErr) {
                    reject(initErr);
                }
            }
        });
    });

    return dbInitPromise;
}

function closeDatabase() {
    return new Promise((resolve, reject) => {
        dbInitPromise = null;
        if (!db) return resolve();
        db.close((err) => {
            db = null;
            if (err) reject(err);
            else resolve();
        });
    });
}

// ==========================================
// Database Initialization & Migration
// ==========================================
async function seedDefaultUsersAsync() {
    const adminHash = hashPassword(process.env.DEFAULT_ADMIN_PASSWORD || 'admin');
    const staffHash = hashPassword(process.env.DEFAULT_STAFF_PASSWORD || 'staff');
    
    const adminRow = await allAsync("SELECT username FROM users WHERE username = 'admin'");
    if (!adminRow || adminRow.length === 0) {
        console.log('Seeding default admin user');
        await runAsync("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['admin', adminHash, 'admin']);
    }
    
    const staffRow = await allAsync("SELECT username FROM users WHERE username = 'staff'");
    if (!staffRow || staffRow.length === 0) {
        console.log('Seeding default staff user');
        await runAsync("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['staff', staffHash, 'staff']);
    }
}

async function checkAndSeedLabelSizesAsync() {
    for (const s of DEFAULT_LABEL_SIZES) {
        const row = await allAsync("SELECT id FROM label_sizes WHERE width = ? AND height = ?", [s.width, s.height]);
        if (!row || row.length === 0) {
            console.log(`Seeding missing default label size: ${s.width}x${s.height}`);
            await runAsync("INSERT INTO label_sizes (width, height, is_default) VALUES (?, ?, ?)", [s.width, s.height, s.is_default]);
        }
    }
}

async function initDatabaseAsync() {
    await runAsync(`CREATE TABLE IF NOT EXISTS users (
        username TEXT PRIMARY KEY,
        password TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff'
    )`);
    await seedDefaultUsersAsync();

    await runAsync(`CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        emoji TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0
    )`);

    await runAsync(`CREATE TABLE IF NOT EXISTS storage_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        sort_order INTEGER DEFAULT 0,
        unit TEXT DEFAULT 'day'
    )`);

    await runAsync(`ALTER TABLE storage_locations ADD COLUMN unit TEXT DEFAULT 'day'`).catch(() => {});

    await runAsync(`CREATE TABLE IF NOT EXISTS label_sizes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        is_default INTEGER DEFAULT 0
    )`);
    await checkAndSeedLabelSizesAsync();

    await runAsync(`CREATE TABLE IF NOT EXISTS ingredients_v2 (
        name TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        abbr TEXT DEFAULT '',
        is_sauce INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0
    )`);
    await runAsync(`ALTER TABLE ingredients_v2 ADD COLUMN is_sauce INTEGER DEFAULT 0`).catch(() => {});
    await runAsync(`ALTER TABLE ingredients_v2 ADD COLUMN sort_order INTEGER DEFAULT 0`).catch(() => {});

    await runAsync(`CREATE TABLE IF NOT EXISTS ingredient_storage (
        ingredient_name TEXT NOT NULL,
        storage_id INTEGER NOT NULL,
        shelf_days INTEGER NOT NULL,
        PRIMARY KEY (ingredient_name, storage_id),
        FOREIGN KEY (ingredient_name) REFERENCES ingredients_v2(name) ON DELETE CASCADE,
        FOREIGN KEY (storage_id) REFERENCES storage_locations(id) ON DELETE CASCADE
    )`);

    await runAsync(`CREATE TABLE IF NOT EXISTS print_logs (
        id TEXT PRIMARY KEY,
        ingredient_name TEXT NOT NULL,
        category TEXT DEFAULT '',
        abbr TEXT DEFAULT '',
        storage_location TEXT DEFAULT '',
        prep_date TEXT DEFAULT '',
        expire_date TEXT DEFAULT '',
        staff TEXT DEFAULT '',
        quantity INTEGER DEFAULT 1,
        timestamp TEXT NOT NULL
    )`);

    await runAsync(`CREATE TABLE IF NOT EXISTS db_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )`);

    await runAsync(`CREATE TABLE IF NOT EXISTS sauce_master (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sauce_code TEXT UNIQUE NOT NULL,
        sauce_name TEXT NOT NULL,
        default_valid_min INTEGER DEFAULT 600,
        warning_pct INTEGER DEFAULT 45,
        critical_pct INTEGER DEFAULT 15,
        is_active INTEGER DEFAULT 1
    )`);
    await seedSauceMasterAsync();

    await runAsync(`CREATE TABLE IF NOT EXISTS system_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        description TEXT
    )`);
    await seedSystemSettingsAsync();

    await runAsync(`CREATE TABLE IF NOT EXISTS pizza_sauce (
        source_id TEXT PRIMARY KEY,
        sauce_code TEXT DEFAULT 'PS',
        status TEXT NOT NULL,
        total_valid_min INTEGER NOT NULL,
        accum_used_min REAL DEFAULT 0,
        rem_valid_min REAL NOT NULL,
        prep_time TEXT NOT NULL,
        last_action_time TEXT NOT NULL,
        est_discard_time TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )`);

    await checkAndMigrateAsync();
}

async function seedSauceMasterAsync() {
    const defaultSauces = [
        { code: 'PS', name: '피자소스', min: 600, warn: 45, crit: 15 },
        { code: 'GD', name: '갈릭디핑소스', min: 480, warn: 45, crit: 15 },
        { code: 'BQ', name: '바비큐소스', min: 480, warn: 45, crit: 15 },
        { code: 'HS', name: '핫소스', min: 720, warn: 45, crit: 15 }
    ];
    for (const s of defaultSauces) {
        await runAsync(
            "INSERT OR IGNORE INTO sauce_master (sauce_code, sauce_name, default_valid_min, warning_pct, critical_pct) VALUES (?, ?, ?, ?, ?)",
            [s.code, s.name, s.min, s.warn, s.crit]
        );
    }
}

async function seedSystemSettingsAsync() {
    const defaultSettings = [
        { key: 'operating_start_time', val: '11:00:00', desc: '오전 출고 시 유효시간 차감 시작 시각' },
        { key: 'operating_end_time', val: '22:00:00', desc: '매장 영업 마감 시각' },
        { key: 'sauce_id_prefix', val: 'S', desc: '소스통 바코드 ID 접두사' },
        { key: 'admin_allowed_ips', val: '', desc: '관리자 접속 허용 IP 주소 (쉼표 구분, 빈값은 미제한)' }
    ];
    for (const st of defaultSettings) {
        await runAsync(
            "INSERT OR IGNORE INTO system_settings (setting_key, setting_value, description) VALUES (?, ?, ?)",
            [st.key, st.val, st.desc]
        );
    }
}

async function checkAndMigrateAsync() {
    const tableRow = await allAsync("SELECT name FROM sqlite_master WHERE type='table' AND name='ingredients'");
    if (tableRow && tableRow.length > 0) {
        const columns = await allAsync("PRAGMA table_info(ingredients)");
        const hasWalkin = columns && columns.some(c => c.name === 'walkin');
        if (hasWalkin) {
            console.log('Old schema detected. Running migration...');
            await migrateFromOldSchemaAsync();
        } else {
            await checkAndSeedNewSchemaAsync();
        }
    } else {
        await checkAndSeedNewSchemaAsync();
    }
}

async function checkAndSeedNewSchemaAsync() {
    const row = await allAsync("SELECT COUNT(*) as count FROM ingredients_v2");
    if (!row || row[0].count === 0) {
        console.log('Seeding new schema with default data...');
        await seedDefaultsAsync();
    }
}

// Migrate a legacy `ingredients` (walkin/makeline/bottle columns) database to
// the current v2 schema. Runs inside a transaction using the async helpers so
// that initDatabaseAsync() can await completion.
async function migrateFromOldSchemaAsync() {
    await runAsync("BEGIN TRANSACTION");
    try {
        const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, emoji, sort_order) VALUES (?, ?, ?)");
        for (const c of DEFAULT_CATEGORIES) catStmt.run(c.name, c.emoji, c.sort_order);
        await finalizeAsync(catStmt);

        const slStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order, unit) VALUES (?, ?, ?)");
        for (const s of DEFAULT_STORAGE_LOCATIONS) slStmt.run(s.name, s.sort_order, s.unit || 'day');
        await finalizeAsync(slStmt);

        const rows = await allAsync("SELECT * FROM ingredients");
        if (rows && rows.length > 0) {
            const ingStmt = db.prepare("INSERT OR IGNORE INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
            for (const r of rows) ingStmt.run(r.name, r.category, r.abbr || '');
            await finalizeAsync(ingStmt);

            const locations = await allAsync("SELECT id, name FROM storage_locations");
            const locMap = {};
            locations.forEach(l => { locMap[l.name] = l.id; });

            const columnToLocation = [
                ['walkin', '워크인 랙산'],
                ['makeline', '메이크라인'],
                ['bottle', '소스보틀'],
            ];
            const stStmt = db.prepare("INSERT OR IGNORE INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
            for (const r of rows) {
                for (const [col, locName] of columnToLocation) {
                    if (r[col] !== null && r[col] !== undefined && locMap[locName]) {
                        stStmt.run(r.name, locMap[locName], r[col]);
                    }
                }
            }
            await finalizeAsync(stStmt);
            console.log(`Migrated ${rows.length} ingredients to new schema.`);
        } else {
            console.log('No data to migrate from old ingredients table.');
        }

        await runAsync("DROP TABLE IF EXISTS ingredients");
        await runAsync("COMMIT");
        console.log('Old ingredients table dropped.');
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        throw err;
    }

    // If the legacy table was empty, fall back to seeding the default dataset.
    await checkAndSeedNewSchemaAsync();
}

// ==========================================
// API: Authentication
// ==========================================
app.post('/api/auth/login', (req, res) => {
    const { username, password } = req.body;
    if (!username || !password) {
        return res.status(400).json({ error: '아이디와 비밀번호를 입력해 주세요.' });
    }

    if (isLoginRateLimited(req, username)) {
        return res.status(429).json({ error: '로그인 실패가 너무 많습니다. 잠시 후 다시 시도해 주세요.' });
    }

    db.get("SELECT * FROM users WHERE username = ?", [username], async (err, user) => {
        if (err) return res.status(500).json({ error: err.message });
        const passwordCheck = user ? verifyPassword(password, user.password) : { valid: false };
        if (!user || !passwordCheck.valid) {
            recordLoginFailure(req, username);
            return res.status(400).json({ error: '아이디 또는 비밀번호가 올바르지 않습니다.' });
        }


        clearLoginFailures(req, username);

        if (passwordCheck.needsRehash) {
            db.run("UPDATE users SET password = ? WHERE username = ?", [hashPassword(password), user.username]);
        }

        const token = createJwtToken({ username: user.username, role: user.role });
        const expiresAt = Date.now() + SESSION_MAX_AGE_MS;
        sessions[token] = { username: user.username, role: user.role, expiresAt };

        res.cookie('session_token', token, {
            httpOnly: true,
            maxAge: SESSION_MAX_AGE_MS,
            sameSite: 'strict',
            secure: isProduction(),
            path: '/'
        });

        res.json({ success: true, token, user: { username: user.username, role: user.role } });
    });
});

app.post('/api/auth/logout', (req, res) => {
    const token = req.cookies.session_token;
    if (token) {
        delete sessions[token];
    }
    res.clearCookie('session_token');
    res.json({ success: true });
});

app.get('/api/auth/status', (req, res) => {
    const session = getActiveSession(req, res);
    if (session) {
        return res.json({ loggedIn: true, user: { username: session.username, role: session.role } });
    }
    res.json({ loggedIn: false });
});

// ==========================================
// API: Default Database & Sync & Print Logs
// ==========================================

// GET /api/default-database
app.get('/api/default-database', (req, res) => {
    try {
        const defaultPath = path.join(__dirname, 'default_database.json');
        if (fs.existsSync(defaultPath)) {
            const raw = fs.readFileSync(defaultPath, 'utf8');
            const parsed = JSON.parse(raw);
            delete parsed.users;
            delete parsed.passwords;
            delete parsed.password;
            delete parsed.print_logs;
            return res.json(parsed);
        }
    } catch (e) {
        console.error('Error reading default_database.json:', e);
    }
    res.json({
        last_updated: new Date().toISOString(),
        categories: DEFAULT_CATEGORIES,
        storage_locations: DEFAULT_STORAGE_LOCATIONS,
        label_sizes: DEFAULT_LABEL_SIZES,
        ingredients_v2: DEFAULT_INGREDIENTS.map(i => ({ name: i.name, category: i.category, abbr: i.abbr || '' })),
        ingredient_storage: []
    });
});

// GET /api/sync/database (Database download for tablet sync - public read access)
app.get('/api/sync/database', async (req, res) => {
    try {
        const categories = await allAsync("SELECT * FROM categories ORDER BY sort_order ASC, id ASC");
        const storage_locations = await allAsync("SELECT * FROM storage_locations ORDER BY sort_order ASC, id ASC");
        const label_sizes = await allAsync("SELECT * FROM label_sizes ORDER BY width ASC, height ASC, id ASC");
        const ingredients_v2 = await allAsync("SELECT * FROM ingredients_v2 ORDER BY CASE WHEN sort_order IS NULL OR sort_order = 0 THEN 99999 ELSE sort_order END ASC, category ASC, name ASC");
        const ingredient_storage = await allAsync("SELECT * FROM ingredient_storage");

        let lastUpdated = new Date().toISOString();
        try {
            const metaRow = await allAsync("SELECT value FROM db_metadata WHERE key = 'last_updated'");
            if (metaRow && metaRow.length > 0) {
                lastUpdated = metaRow[0].value;
            }
        } catch (metaErr) {
            // Ignore
        }

        const result = {
            last_updated: lastUpdated,
            categories,
            storage_locations,
            label_sizes,
            ingredients_v2,
            ingredient_storage
        };

        try {
            const extraRow = await allAsync("SELECT value FROM db_metadata WHERE key = 'extra_data'");
            if (extraRow && extraRow.length > 0) {
                const extra = JSON.parse(extraRow[0].value);
                Object.assign(result, extra);
            }
        } catch (e) {}

        const etag = crypto.createHash('md5').update(JSON.stringify(result)).digest('hex');
        res.setHeader('ETag', etag);

        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/sync/database
app.post('/api/sync/database', requireLogin, async (req, res) => {
    const payload = req.body;
    if (!payload || typeof payload !== 'object') {
        return res.status(400).json({ error: '유효하지 않은 데이터 형식입니다.' });
    }

    // Security: NEVER store or overwrite users/passwords from sync payload
    delete payload.users;
    delete payload.password;
    delete payload.passwords;

    const ifMatch = req.headers['if-match'];
    if (ifMatch) {
        try {
            const categories = await allAsync("SELECT * FROM categories ORDER BY sort_order ASC, id ASC");
            const storage_locations = await allAsync("SELECT * FROM storage_locations ORDER BY sort_order ASC, id ASC");
            const label_sizes = await allAsync("SELECT * FROM label_sizes ORDER BY width ASC, height ASC, id ASC");
            const ingredients_v2 = await allAsync("SELECT * FROM ingredients_v2 ORDER BY CASE WHEN sort_order IS NULL OR sort_order = 0 THEN 99999 ELSE sort_order END ASC, category ASC, name ASC");
            const ingredient_storage = await allAsync("SELECT * FROM ingredient_storage");
            const currentData = { categories, storage_locations, label_sizes, ingredients_v2, ingredient_storage };
            const currentEtag = crypto.createHash('md5').update(JSON.stringify(currentData)).digest('hex');
            if (ifMatch !== currentEtag) {
                return res.status(409).json({ error: '서버 데이터가 수정되었습니다. 최신 데이터를 먼저 동기화하세요.' });
            }
        } catch (e) {
            // ignore check failure
        }
    }

    const newLastUpdated = payload.last_updated || new Date().toISOString();
    const extraData = {};
    for (const [key, val] of Object.entries(payload)) {
        if (!['categories', 'storage_locations', 'label_sizes', 'ingredients_v2', 'ingredient_storage', 'last_updated'].includes(key)) {
            extraData[key] = val;
        }
    }

    try {
        await runAsync("BEGIN TRANSACTION");

        // Clear child table first due to foreign key constraints
        if (Array.isArray(payload.ingredient_storage) || Array.isArray(payload.ingredients_v2) || Array.isArray(payload.storage_locations)) {
            await runAsync("DELETE FROM ingredient_storage");
        }
        if (Array.isArray(payload.ingredients_v2)) {
            await runAsync("DELETE FROM ingredients_v2");
        }
        if (Array.isArray(payload.storage_locations)) {
            await runAsync("DELETE FROM storage_locations");
        }
        if (Array.isArray(payload.categories)) {
            await runAsync("DELETE FROM categories");
        }
        if (Array.isArray(payload.label_sizes)) {
            await runAsync("DELETE FROM label_sizes");
        }

        // Insert parent tables first
        if (Array.isArray(payload.categories)) {
            const catStmt = db.prepare("INSERT INTO categories (id, name, emoji, sort_order) VALUES (?, ?, ?, ?)");
            for (const c of payload.categories) {
                await new Promise((res, rej) => catStmt.run(c.id || null, c.name, c.emoji || '', c.sort_order || 0, err => err ? rej(err) : res()));
            }
            await finalizeAsync(catStmt);
        }

        if (Array.isArray(payload.storage_locations)) {
            const slStmt = db.prepare("INSERT INTO storage_locations (id, name, sort_order, unit) VALUES (?, ?, ?, ?)");
            for (const s of payload.storage_locations) {
                await new Promise((res, rej) => slStmt.run(s.id || null, s.name, s.sort_order || 0, s.unit || 'day', err => err ? rej(err) : res()));
            }
            await finalizeAsync(slStmt);
        }

        if (Array.isArray(payload.label_sizes)) {
            const lsStmt = db.prepare("INSERT INTO label_sizes (id, width, height, is_default) VALUES (?, ?, ?, ?)");
            for (const l of payload.label_sizes) {
                await new Promise((res, rej) => lsStmt.run(l.id || null, l.width, l.height, l.is_default ? 1 : 0, err => err ? rej(err) : res()));
            }
            await finalizeAsync(lsStmt);
        }

        if (Array.isArray(payload.ingredients_v2)) {
            const ingStmt = db.prepare("INSERT INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
            for (const i of payload.ingredients_v2) {
                await new Promise((res, rej) => ingStmt.run(i.name, i.category, i.abbr || '', err => err ? rej(err) : res()));
            }
            await finalizeAsync(ingStmt);
        }

        if (Array.isArray(payload.ingredient_storage)) {
            const stStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
            for (const st of payload.ingredient_storage) {
                await new Promise((res, rej) => stStmt.run(st.ingredient_name, st.storage_id, st.shelf_days, err => err ? rej(err) : res()));
            }
            await finalizeAsync(stStmt);
        }

        await runAsync("INSERT OR REPLACE INTO db_metadata (key, value) VALUES ('last_updated', ?)", [newLastUpdated]);
        if (Object.keys(extraData).length > 0) {
            await runAsync("INSERT OR REPLACE INTO db_metadata (key, value) VALUES ('extra_data', ?)", [JSON.stringify(extraData)]);
        }

        await runAsync("COMMIT");

        res.json({ success: true, last_updated: newLastUpdated });
    } catch (err) {
        console.error("POST /api/sync/database error:", err);
        await runAsync("ROLLBACK").catch(() => {});
        res.status(500).json({ error: '동기화 저장 중 오류가 발생했습니다: ' + err.message });
    }
});

// GET /api/print-logs
app.get('/api/print-logs', requireLogin, async (req, res) => {
    try {
        const logs = await allAsync("SELECT * FROM print_logs ORDER BY timestamp ASC");
        res.json(logs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/print-logs
app.post('/api/print-logs', requireLogin, async (req, res) => {
    const { ingredient_name, category, abbr, storage_location, prep_date, expire_date, staff, quantity } = req.body || {};
    if (!ingredient_name || typeof ingredient_name !== 'string') {
        return res.status(400).json({ error: '재료명은 필수 항목입니다.' });
    }
    const qty = isSafePositiveInteger(quantity) ? Number(quantity) : 1;
    const logId = req.body.id || `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
    const timestamp = req.body.timestamp || new Date().toISOString();

    const logEntry = {
        id: logId,
        ingredient_name: ingredient_name.trim(),
        category: String(category || '').trim(),
        abbr: String(abbr || '').trim(),
        storage_location: String(storage_location || '').trim(),
        prep_date: String(prep_date || '').trim(),
        expire_date: String(expire_date || '').trim(),
        staff: String(staff || '').trim(),
        quantity: qty,
        timestamp
    };

    try {
        await runAsync(
            `INSERT INTO print_logs (id, ingredient_name, category, abbr, storage_location, prep_date, expire_date, staff, quantity, timestamp)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [logEntry.id, logEntry.ingredient_name, logEntry.category, logEntry.abbr, logEntry.storage_location, logEntry.prep_date, logEntry.expire_date, logEntry.staff, logEntry.quantity, logEntry.timestamp]
        );
        res.json({ success: true, log: logEntry });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ==========================================
// Sauce Management REST APIs
// ==========================================

// GET /api/sauce-master (Sauce item master list)
app.get('/api/sauce-master', async (req, res) => {
    try {
        const rows = await allAsync("SELECT * FROM sauce_master WHERE is_active = 1 ORDER BY id ASC");
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/sauce-master (Create or Update sauce master)
app.post('/api/sauce-master', requireAdmin, async (req, res) => {
    const { sauce_code, sauce_name, default_valid_min, warning_pct, critical_pct } = req.body || {};
    if (!sauce_code || !sauce_name) {
        return res.status(400).json({ error: '소스 코드와 소스 이름은 필수입니다.' });
    }
    try {
        await runAsync(
            `INSERT OR REPLACE INTO sauce_master (sauce_code, sauce_name, default_valid_min, warning_pct, critical_pct, is_active)
             VALUES (?, ?, ?, ?, ?, 1)`,
            [sauce_code.toUpperCase(), sauce_name, default_valid_min || 600, warning_pct || 45, critical_pct || 15]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/system-settings (System configuration)
app.get('/api/system-settings', async (req, res) => {
    try {
        const rows = await allAsync("SELECT * FROM system_settings");
        const settings = {};
        rows.forEach(r => { settings[r.setting_key] = r.setting_value; });
        res.json(settings);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/system-settings (Update system configuration)
app.post('/api/system-settings', requireAdmin, async (req, res) => {
    const { key, value } = req.body || {};
    if (!key) return res.status(400).json({ error: '설정 키는 필수입니다.' });
    try {
        await runAsync(
            "INSERT OR REPLACE INTO system_settings (setting_key, setting_value) VALUES (?, ?)",
            [key, String(value)]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /api/sauces (Get active/stored sauces)
app.get('/api/sauces', async (req, res) => {
    try {
        const rows = await allAsync("SELECT * FROM pizza_sauce ORDER BY created_at DESC");
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// POST /api/sauces/prep (Create new PREP sauce)
app.post('/api/sauces/prep', async (req, res) => {
    const { source_id, sauce_code, total_valid_min, prep_time, last_action_time, est_discard_time } = req.body || {};
    if (!source_id) return res.status(400).json({ error: 'Source ID는 필수입니다.' });

    const nowIso = prep_time || new Date().toISOString();
    const estIso = est_discard_time || new Date(new Date(nowIso).getTime() + (total_valid_min || 600) * 60 * 1000).toISOString();

    try {
        await runAsync(
            `INSERT INTO pizza_sauce (source_id, sauce_code, status, total_valid_min, accum_used_min, rem_valid_min, prep_time, last_action_time, est_discard_time)
             VALUES (?, ?, 'PREP', ?, 0, ?, ?, ?, ?)`,
            [source_id, sauce_code || 'PS', total_valid_min || 600, total_valid_min || 600, nowIso, last_action_time || nowIso, estIso]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// PUT /api/sauces/:id/status (Update status to IN, OUT, or DISCARD)
app.put('/api/sauces/:id/status', async (req, res) => {
    const source_id = req.params.id;
    const { status, accum_used_min, rem_valid_min, last_action_time, est_discard_time } = req.body || {};
    if (!status) return res.status(400).json({ error: 'Status 항목은 필수입니다.' });

    try {
        await runAsync(
            `UPDATE pizza_sauce SET status = ?, accum_used_min = ?, rem_valid_min = ?, last_action_time = ?, est_discard_time = ? WHERE source_id = ?`,
            [status, accum_used_min ?? 0, rem_valid_min ?? 0, last_action_time || new Date().toISOString(), est_discard_time || null, source_id]
        );
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// DELETE /api/sauces/:id (Delete sauce record or reset all)
app.delete('/api/sauces/:id', async (req, res) => {
    const id = req.params.id;
    try {
        if (id === 'reset-all') {
            await runAsync("DELETE FROM pizza_sauce");
        } else {
            await runAsync("DELETE FROM pizza_sauce WHERE source_id = ?", [id]);
        }
        res.json({ success: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ==========================================
// API: Categories
// ==========================================
app.get('/api/categories', requireLogin, (req, res) => {
    db.all("SELECT * FROM categories ORDER BY sort_order ASC, id ASC", [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.post('/api/categories', requireAdmin, async (req, res) => {
    const { name, emoji } = req.body;
    if (!name) return res.status(400).json({ error: '카테고리 이름은 필수입니다.' });
    try {
        await runAsync("INSERT INTO categories (name, emoji, sort_order) VALUES (?, ?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM categories))", [name, emoji || '']);
        await touchDbLastUpdatedAsync();
        res.status(201).json({ success: true, name, emoji: emoji || '' });
    } catch (err) {
        if (err.message && err.message.includes('UNIQUE')) return res.status(400).json({ error: '이미 존재하는 카테고리입니다.' });
        sendServerError(res, err, '카테고리 추가 중 오류가 발생했습니다.');
    }
});

app.delete('/api/categories/:id', requireAdmin, async (req, res) => {
    try {
        await runAsync("DELETE FROM categories WHERE id = ?", [req.params.id]);
        await touchDbLastUpdatedAsync();
        res.json({ success: true });
    } catch (err) {
        sendServerError(res, err, '카테고리 삭제 중 오류가 발생했습니다.');
    }
});

// ==========================================
// API: Storage Locations
// ==========================================
app.get('/api/storage-locations', requireLogin, (req, res) => {
    db.all("SELECT * FROM storage_locations ORDER BY sort_order ASC, id ASC", [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.post('/api/storage-locations', requireAdmin, async (req, res) => {
    const { name, unit } = req.body;
    if (!name) return res.status(400).json({ error: '보관위치 이름은 필수입니다.' });
    const insertUnit = unit || 'day';
    try {
        await runAsync("INSERT INTO storage_locations (name, sort_order, unit) VALUES (?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM storage_locations), ?)", [name, insertUnit]);
        await touchDbLastUpdatedAsync();
        res.status(201).json({ success: true, name, unit: insertUnit });
    } catch (err) {
        if (err.message && err.message.includes('UNIQUE')) return res.status(400).json({ error: '이미 존재하는 보관위치입니다.' });
        sendServerError(res, err, '보관위치 추가 중 오류가 발생했습니다.');
    }
});

app.delete('/api/storage-locations/:id', requireAdmin, async (req, res) => {
    try {
        await runAsync("DELETE FROM storage_locations WHERE id = ?", [req.params.id]);
        await touchDbLastUpdatedAsync();
        res.json({ success: true });
    } catch (err) {
        sendServerError(res, err, '보관위치 삭제 중 오류가 발생했습니다.');
    }
});

// ==========================================
// API: Label Sizes
// ==========================================
app.get('/api/label-sizes', requireLogin, (req, res) => {
    db.all("SELECT * FROM label_sizes ORDER BY width ASC, height ASC, id ASC", [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.post('/api/label-sizes', requireAdmin, async (req, res) => {
    const { width, height } = req.body;
    const w = parseInt(width);
    const h = parseInt(height);
    if (!isSafePositiveInteger(w) || !isSafePositiveInteger(h)) {
        return res.status(400).json({ error: '가로와 세로 크기는 필수입니다.' });
    }
    if (w < 20 || w > 150 || h < 15 || h > 150) {
        return res.status(400).json({ error: '가로 크기는 20~150mm, 세로 크기는 15~150mm 사이여야 합니다.' });
    }

    try {
        const row = await allAsync("SELECT id FROM label_sizes WHERE width = ? AND height = ?", [w, h]);
        if (row && row.length > 0) return res.status(400).json({ error: '이미 존재하는 규격 프리셋입니다.' });

        await runAsync("INSERT INTO label_sizes (width, height, is_default) VALUES (?, ?, 0)", [w, h]);
        await touchDbLastUpdatedAsync();
        res.status(201).json({ success: true, width: w, height: h, is_default: 0 });
    } catch (err) {
        sendServerError(res, err, '라벨 규격 추가 중 오류가 발생했습니다.');
    }
});

app.delete('/api/label-sizes/:id', requireAdmin, async (req, res) => {
    try {
        await runAsync("DELETE FROM label_sizes WHERE id = ?", [req.params.id]);
        await touchDbLastUpdatedAsync();
        res.json({ success: true });
    } catch (err) {
        sendServerError(res, err, '라벨 규격 삭제 중 오류가 발생했습니다.');
    }
});

// ==========================================
// API: Ingredients (v2 — with dynamic storage)
// ==========================================
app.get('/api/ingredients', requireLogin, (req, res) => {
    // Join ingredients with their storage mappings
    db.all("SELECT * FROM ingredients_v2 ORDER BY CASE WHEN sort_order IS NULL OR sort_order = 0 THEN 99999 ELSE sort_order END ASC, category ASC, name ASC", [], (err, ingredients) => {
        if (err) return res.status(500).json({ error: err.message });

        // Get all storage mappings in one query
        db.all(`SELECT ist.ingredient_name, ist.storage_id, ist.shelf_days, sl.name as storage_name
                FROM ingredient_storage ist
                JOIN storage_locations sl ON ist.storage_id = sl.id`, [], (err, mappings) => {
            if (err) return res.status(500).json({ error: err.message });

            // Build a map: ingredient_name -> { storage_name: shelf_days, ... }
            const storageMap = {};
            mappings.forEach(m => {
                if (!storageMap[m.ingredient_name]) storageMap[m.ingredient_name] = {};
                storageMap[m.ingredient_name][m.storage_name] = { id: m.storage_id, days: m.shelf_days };
            });

            const result = ingredients.map(ing => ({
                ...ing,
                storage: storageMap[ing.name] || {}
            }));
            res.json(result);
        });
    });
});

app.post('/api/ingredients/reorder', requireAdmin, async (req, res) => {
    const { order } = req.body || {};
    if (!Array.isArray(order)) return res.status(400).json({ error: 'order 배열이 필요합니다.' });

    try {
        await runAsync("BEGIN TRANSACTION");
        const stmt = db.prepare("UPDATE ingredients_v2 SET sort_order = ? WHERE name = ?");
        for (let i = 0; i < order.length; i++) {
            await new Promise((resolve, reject) => {
                stmt.run(i + 1, order[i], err => err ? reject(err) : resolve());
            });
        }
        await finalizeAsync(stmt);
        await touchDbLastUpdatedAsync();
        await runAsync("COMMIT");
        res.json({ success: true });
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        sendServerError(res, err, '순서 변경 중 오류가 발생했습니다.');
    }
});

app.post('/api/ingredients', requireAdmin, async (req, res) => {
    const { category, name, abbr, storage, is_sauce, isSauce } = req.body || {};
    if (!name || !category) return res.status(400).json({ error: '재료명과 카테고리는 필수 항목입니다.' });

    const trimmedName = String(name).trim().substring(0, 100);
    const trimmedCategory = String(category).trim().substring(0, 100);
    const trimmedAbbr = String(abbr || '').trim().substring(0, 50);
    const isSauceVal = (is_sauce === 1 || is_sauce === true || isSauce === 1 || isSauce === true) ? 1 : 0;

    if (storage && typeof storage === 'object') {
        for (const [storageId, days] of Object.entries(storage)) {
            if (days !== null && days !== '' && days !== undefined) {
                if (!isSafePositiveInteger(storageId) || !isSafePositiveInteger(days)) {
                    return res.status(400).json({ error: '보관위치와 유통기한은 양의 정수여야 합니다.' });
                }
            }
        }
    }

    try {
        await runAsync("BEGIN TRANSACTION");
        
        await runAsync("INSERT INTO ingredients_v2 (name, category, abbr, is_sauce) VALUES (?, ?, ?, ?)",
            [trimmedName, trimmedCategory, trimmedAbbr, isSauceVal]
        );

        if (storage && typeof storage === 'object') {
            const stStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
            for (const [storageId, days] of Object.entries(storage)) {
                if (days !== null && days !== '' && days !== undefined) {
                    await new Promise((res, rej) => stStmt.run(trimmedName, parseInt(storageId), parseInt(days), err => err ? rej(err) : res()));
                }
            }
            await finalizeAsync(stStmt);
        }

        await touchDbLastUpdatedAsync();
        await runAsync("COMMIT");
        res.status(201).json({ success: true });
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        if (err.message && err.message.includes('UNIQUE')) {
            return res.status(400).json({ error: '이미 존재하는 재료 이름입니다.' });
        }
        sendServerError(res, err, '재료 추가 중 오류가 발생했습니다.');
    }
});

app.delete('/api/ingredients/:name', requireAdmin, async (req, res) => {
    const name = decodeURIComponent(req.params.name);
    try {
        await runAsync("BEGIN TRANSACTION");
        await runAsync("DELETE FROM ingredient_storage WHERE ingredient_name = ?", [name]);
        await runAsync("DELETE FROM ingredients_v2 WHERE name = ?", [name]);
        await touchDbLastUpdatedAsync();
        await runAsync("COMMIT");
        res.json({ success: true });
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        sendServerError(res, err, '재료 삭제 중 오류가 발생했습니다.');
    }
});

app.put('/api/ingredients/:oldName', requireAdmin, async (req, res) => {
    const oldName = decodeURIComponent(req.params.oldName);
    const { category, name, abbr, storage, is_sauce, isSauce } = req.body || {};
    if (!name || !category) return res.status(400).json({ error: '재료명과 카테고리는 필수 항목입니다.' });

    const trimmedName = String(name).trim().substring(0, 100);
    const trimmedCategory = String(category).trim().substring(0, 100);
    const trimmedAbbr = String(abbr || '').trim().substring(0, 50);
    const isSauceVal = (is_sauce === 1 || is_sauce === true || isSauce === 1 || isSauce === true) ? 1 : 0;

    if (storage && typeof storage === 'object') {
        for (const [storageId, days] of Object.entries(storage)) {
            if (days !== null && days !== '' && days !== undefined) {
                if (!isSafePositiveInteger(storageId) || !isSafePositiveInteger(days)) {
                    return res.status(400).json({ error: '보관위치와 유통기한은 양의 정수여야 합니다.' });
                }
            }
        }
    }

    try {
        await runAsync("BEGIN TRANSACTION");

        await runAsync("DELETE FROM ingredient_storage WHERE ingredient_name = ?", [oldName]);
        await runAsync("UPDATE ingredients_v2 SET name = ?, category = ?, abbr = ?, is_sauce = ? WHERE name = ?",
            [trimmedName, trimmedCategory, trimmedAbbr, isSauceVal, oldName]
        );

        if (storage && typeof storage === 'object') {
            const stStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
            for (const [storageId, days] of Object.entries(storage)) {
                if (days !== null && days !== '' && days !== undefined) {
                    await new Promise((res, rej) => stStmt.run(trimmedName, parseInt(storageId), parseInt(days), err => err ? rej(err) : res()));
                }
            }
            await finalizeAsync(stStmt);
        }

        await touchDbLastUpdatedAsync();
        await runAsync("COMMIT");
        res.json({ success: true });
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        if (err.message && err.message.includes('UNIQUE')) {
            return res.status(400).json({ error: '이미 존재하는 재료 이름입니다.' });
        }
        sendServerError(res, err, '재료 수정 중 오류가 발생했습니다.');
    }
});

const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 }, // 5MB limit
    fileFilter: (req, file, cb) => {
        const ext = path.extname(file.originalname || '').toLowerCase();
        if (ext !== '.xlsx' && ext !== '.xls') {
            return cb(new Error('엑셀 파일(.xlsx, .xls)만 업로드할 수 있습니다.'));
        }
        cb(null, true);
    }
});

app.get('/api/ingredients/sample-excel', requireLogin, (req, res) => {
    const filePath = path.join(__dirname, 'files', 'SHELFLIFE_sample.xlsx');
    res.download(filePath, 'SHELFLIFE_sample.xlsx', (err) => {
        if (err) {
            sendServerError(res, err, '샘플 파일을 다운로드하는 중에 오류가 발생했습니다.');
        }
    });
});

app.post('/api/ingredients/upload-excel', requireAdmin, (req, res, next) => {
    upload.single('file')(req, res, (err) => {
        if (err) {
            return res.status(400).json({ error: err.message || '엑셀 파일 업로드 오류가 발생했습니다.' });
        }
        next();
    });
}, async (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: '엑셀 파일을 업로드해 주세요.' });
    }

    try {
        const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        if (!sheetName || !workbook.Sheets[sheetName]) {
            return res.status(400).json({ error: '유효하지 않은 엑셀 파일 형식입니다.' });
        }
        const sheet = workbook.Sheets[sheetName];
        const rows = xlsx.utils.sheet_to_json(sheet, { header: 1 });

        if (!rows || rows.length < 2) {
            return res.status(400).json({ error: '유효하지 않은 엑셀 파일 형식입니다.' });
        }
        if (rows.length > 2000) {
            return res.status(400).json({ error: '엑셀 행 수가 너무 많습니다. 최대 2000행까지 지원합니다.' });
        }

        const parsedCategories = new Set();
        const parsedIngredients = [];

        let isTable2 = false;
        let currentCategory = null;

        for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            if (!row || row.length === 0) continue;

            const cell4 = row[4] ? String(row[4]).trim() : '';
            const cell5 = row[5] ? String(row[5]).trim() : '';
            if (cell4 === '분할' || cell5 === '폐기') {
                isTable2 = true;
                currentCategory = null;
                continue;
            }

            if (row[0] === 'ID' || row[1] === '카테고리' || row[2] === '재료명') {
                continue;
            }

            const colCat = row[1];
            const colName = row[2];
            const colAbbr = row[3];

            if (colCat) {
                currentCategory = String(colCat).trim().substring(0, 100);
            }

            if (colName) {
                const name = String(colName).trim().substring(0, 100);
                const abbr = colAbbr ? String(colAbbr).trim().substring(0, 50) : '';
                const category = currentCategory || '기타';

                parsedCategories.add(category);

                const storage = {};
                if (!isTable2) {
                    if (row[4] !== null && row[4] !== undefined && row[4] !== '') {
                        const val = parseInt(row[4]);
                        if (!isNaN(val) && val > 0 && val <= 3650) storage['해동'] = val;
                    }
                    if (row[5] !== null && row[5] !== undefined && row[5] !== '') {
                        const val = parseInt(row[5]);
                        if (!isNaN(val) && val > 0 && val <= 3650) storage['워크인 랙산'] = val;
                    }
                    if (row[6] !== null && row[6] !== undefined && row[6] !== '') {
                        const val = parseInt(row[6]);
                        if (!isNaN(val) && val > 0 && val <= 3650) storage['메이크라인'] = val;
                    }
                    if (row[7] !== null && row[7] !== undefined && row[7] !== '') {
                        const val = parseInt(row[7]);
                        if (!isNaN(val) && val > 0 && val <= 87600) storage['소스보틀'] = val;
                    }
                } else {
                    const expireStr = row[5] ? String(row[5]).trim() : '';
                    if (expireStr) {
                        if (expireStr.includes('22시') || expireStr === '22') {
                            storage['분할'] = 22;
                        } else if (expireStr.includes('시간')) {
                            const match = expireStr.match(/(\d+)/);
                            if (match) {
                                storage['분할'] = parseInt(match[1]);
                            }
                        } else if (expireStr.includes('일')) {
                            const match = expireStr.match(/(\d+)/);
                            if (match) {
                                storage['분할'] = parseInt(match[1]) * 24;
                            }
                        } else {
                            const val = parseInt(expireStr);
                            if (!isNaN(val) && val > 0 && val <= 87600) {
                                if (val < 10) {
                                    storage['분할'] = val * 24;
                                } else {
                                    storage['분할'] = val;
                                }
                            }
                        }
                    }
                }

                parsedIngredients.push({ category, name, abbr, storage });
            }
        }

        if (parsedIngredients.length === 0) {
            return res.status(400).json({ error: '엑셀 파일에서 읽어온 재료 데이터가 없습니다.' });
        }

        await runAsync("BEGIN TRANSACTION");
        try {
            const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, sort_order) VALUES (?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM categories))");
            for (const cat of parsedCategories) {
                await new Promise((r, j) => catStmt.run(cat, err => err ? j(err) : r()));
            }
            await finalizeAsync(catStmt);

            const defLocations = [
                { name: "해동", unit: "day" },
                { name: "워크인 랙산", unit: "day" },
                { name: "메이크라인", unit: "day" },
                { name: "소스보틀", unit: "hour" },
                { name: "분할", unit: "hour" }
            ];
            const locStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order, unit) VALUES (?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM storage_locations), ?)");
            for (const loc of defLocations) {
                await new Promise((r, j) => locStmt.run(loc.name, loc.unit, err => err ? j(err) : r()));
            }
            await finalizeAsync(locStmt);

            await runAsync("DELETE FROM ingredient_storage");
            await runAsync("DELETE FROM ingredients_v2");

            const ingStmt = db.prepare("INSERT INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
            for (const ing of parsedIngredients) {
                await new Promise((r, j) => ingStmt.run(ing.name, ing.category, ing.abbr, err => err ? j(err) : r()));
            }
            await finalizeAsync(ingStmt);

            const dbLocations = await allAsync("SELECT id, name FROM storage_locations");
            const locMap = {};
            dbLocations.forEach(l => { locMap[l.name] = l.id; });

            const mappingStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
            for (const ing of parsedIngredients) {
                for (const [locName, val] of Object.entries(ing.storage)) {
                    if (locMap[locName]) {
                        await new Promise((r, j) => mappingStmt.run(ing.name, locMap[locName], val, err => err ? j(err) : r()));
                    }
                }
            }
            await finalizeAsync(mappingStmt);

            await touchDbLastUpdatedAsync();
            await runAsync("COMMIT");
            res.json({ success: true, count: parsedIngredients.length });
        } catch (dbErr) {
            await runAsync("ROLLBACK").catch(() => {});
            throw dbErr;
        }

    } catch (err) {
        sendServerError(res, err, '엑셀 데이터 처리 중 오류가 발생했습니다.');
    }
});

app.post('/api/ingredients/reset', requireAdmin, async (req, res) => {
    try {
        await runAsync("BEGIN TRANSACTION");
        await runAsync("DELETE FROM ingredient_storage");
        await runAsync("DELETE FROM ingredients_v2");
        await runAsync("DELETE FROM categories");
        await runAsync("DELETE FROM storage_locations");
        await runAsync("DELETE FROM label_sizes");
        await touchDbLastUpdatedAsync();
        await runAsync("COMMIT");

        await seedDefaultsAsync();
        res.json({ success: true });
    } catch (err) {
        await runAsync("ROLLBACK").catch(() => {});
        sendServerError(res, err, '초기화 작업 중 오류가 발생했습니다.');
    }
});

function findApkPath() {
    const locations = [
        path.join(__dirname, 'files', 'app-release.apk'),
        path.join(__dirname, 'client_flutter', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
        path.join(__dirname, 'app-release.apk')
    ];
    return locations.find(p => fs.existsSync(p)) || null;
}

app.get('/api/app-info', (req, res) => {
    const apkPath = findApkPath();
    const pubspecPath = path.join(__dirname, 'client_flutter', 'pubspec.yaml');
    
    let version = '1.0.0';
    let buildNumber = '1';
    
    if (fs.existsSync(pubspecPath)) {
        const pubContent = fs.readFileSync(pubspecPath, 'utf8');
        const match = pubContent.match(/^version:\s*([^\s+]+)\+?(\d+)?/m);
        if (match) {
            version = match[1] || '1.0.0';
            buildNumber = match[2] || '1';
        }
    }

    if (apkPath) {
        const stats = fs.statSync(apkPath);
        const buildDate = stats.mtime.toISOString();
        const sizeMb = (stats.size / (1024 * 1024)).toFixed(1);
        res.json({
            exists: true,
            version,
            buildNumber,
            buildDate,
            fileSizeMb: `${sizeMb} MB`,
            downloadUrl: '/download/app-release.apk',
            fileName: 'shelflife-label-app.apk'
        });
    } else {
        res.json({
            exists: false,
            version,
            buildNumber,
            downloadUrl: '/download/app-release.apk'
        });
    }
});

app.get('/download/app-release.apk', (req, res) => {
    const apkPath = findApkPath();
    if (apkPath) {
        res.setHeader('Content-Type', 'application/vnd.android.package-archive');
        res.download(apkPath, 'shelflife-label-app.apk');
    } else {
        res.status(404).send('APK 파일이 없습니다.');
    }
});

// ==========================================
// API: System Settings & Client IP
// ==========================================
app.get('/api/client-ip', (req, res) => {
    res.json({ ip: getClientIp(req) });
});

app.get('/api/system-settings', requireLogin, async (req, res) => {
    try {
        const rows = await allAsync("SELECT setting_key, setting_value, description FROM system_settings");
        const settings = {};
        rows.forEach(r => { settings[r.setting_key] = r.setting_value; });
        res.json({ success: true, settings });
    } catch (err) {
        sendServerError(res, err, '시스템 설정을 불러오는 중 오류가 발생했습니다.');
    }
});

app.post('/api/system-settings', requireAdmin, async (req, res) => {
    const { setting_key, setting_value } = req.body;
    if (!setting_key || typeof setting_key !== 'string') {
        return res.status(400).json({ error: '유효한 설정 키를 입력해 주세요.' });
    }
    try {
        await runAsync(
            "INSERT INTO system_settings (setting_key, setting_value) VALUES (?, ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value",
            [setting_key, String(setting_value ?? '')]
        );
        res.json({ success: true, message: '설정이 성공적으로 저장되었습니다.' });
    } catch (err) {
        sendServerError(res, err, '시스템 설정을 저장하는 중 오류가 발생했습니다.');
    }
});

// ==========================================
// APK Download & App Version API
// ==========================================
app.get('/api/version', (req, res) => {
    const version = '1.0.5';
    const buildNumber = 105;
    const apkPath = path.join(__dirname, 'client_flutter', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    const exists = fs.existsSync(apkPath);
    res.json({
        exists,
        version,
        buildNumber,
        downloadUrl: '/download/app-release.apk'
    });
});

app.get('/download/app-release.apk', (req, res) => {
    const apkPath = path.join(__dirname, 'client_flutter', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    if (fs.existsSync(apkPath)) {
        res.setHeader('Content-Type', 'application/vnd.android.package-archive');
        res.download(apkPath, 'shelflife-label-app.apk');
    } else {
        res.status(404).send('APK 파일이 없습니다.');
    }
});

// ==========================================
// Start Server & Graceful Shutdown
// ==========================================
if (require.main === module) {
    startDatabase();
    const serverInstance = app.listen(PORT, () => {
        console.log(`Server is running at http://localhost:${PORT}`);
    });

    const gracefulShutdown = (signal) => {
        console.log(`\nReceived ${signal}. Closing server gracefully...`);
        serverInstance.close(async () => {
            console.log('HTTP server closed.');
            try {
                await closeDatabase();
                console.log('Database connection closed.');
                process.exit(0);
            } catch (err) {
                console.error('Error closing database:', err);
                process.exit(1);
            }
        });
    };

    process.on('SIGINT', () => gracefulShutdown('SIGINT'));
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
}

module.exports = {
    app,
    startDatabase,
    closeDatabase,
    isPasswordHash,
    hashPassword,
    verifyPassword,
    verifyLegacyPassword,
    isSafePositiveInteger,
    isLoginRateLimited,
    recordLoginFailure,
    validateRuntimeSecurityConfig,
    getClientIp,
    normalizeIp,
    checkIpMatch,
};
