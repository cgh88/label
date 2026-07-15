const path = require('path');
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const crypto = require('crypto');
const multer = require('multer');
const xlsx = require('xlsx');

const app = express();
const PORT = process.env.PORT || 3000;
const DB_PATH = path.join(__dirname, 'database.sqlite');
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
// Default Seed Data
// ==========================================
const DEFAULT_CATEGORIES = [
    { name: "도우", emoji: "🍞", sort_order: 1 },
    { name: "미트", emoji: "🍖", sort_order: 2 },
    { name: "야채", emoji: "🥬", sort_order: 3 },
    { name: "치즈", emoji: "🧀", sort_order: 4 },
    { name: "소스", emoji: "🏺", sort_order: 5 },
    { name: "캔",   emoji: "🥫", sort_order: 6 },
    { name: "기타", emoji: "🍕", sort_order: 7 }
];

const DEFAULT_STORAGE_LOCATIONS = [
    { name: "해동", sort_order: 1 },
    { name: "워크인 랙산", sort_order: 2 },
    { name: "메이크라인", sort_order: 3 },
    { name: "소스보틀",   sort_order: 4 },
    { name: "분할",       sort_order: 5 }
];

const DEFAULT_LABEL_SIZES = [
    { width: 50, height: 30, is_default: 1 },
    { width: 60, height: 40, is_default: 1 },
    { width: 70, height: 40, is_default: 1 },
    { width: 80, height: 50, is_default: 1 },
    { width: 100, height: 60, is_default: 1 },
    { width: 100, height: 70, is_default: 1 }
];

const DEFAULT_INGREDIENTS = [
    { category: "도우", name: "크루아상", abbr: "CRO", storage: { "해동": 7 } },
    { category: "미트", name: "그릴드치킨", abbr: "E", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "베이컨", abbr: "K", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "햄", abbr: "H", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "페페로니", abbr: "P", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "불고기", abbr: "L", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "비프", abbr: "B", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "바베큐 립", abbr: "", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "이탈리안 소시지", abbr: "I", storage: { "해동": 7, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "치킨스트립", abbr: "CSHM", storage: { "해동": 5, "워크인 랙산": 3, "메이크라인": 1 } },
    { category: "미트", name: "파파스윙", abbr: "10WG", storage: { "해동": 5, "워크인 랙산": 3, "메이크라인": 1 } },
    { category: "야채", name: "양송이 버섯", abbr: "M", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "야채", name: "양파", abbr: "O", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "야채", name: "청피망", abbr: "G", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "야채", name: "토마토", abbr: "T", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "치즈", name: "2 블랜드치즈", abbr: "2BX", storage: { "해동": 7, "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "3 블랜드치즈", abbr: "3BX", storage: { "해동": 7, "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "스트링 치즈", abbr: "", storage: { "해동": 7, "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "체다스트링 치즈", abbr: "CC", storage: { "해동": 7, "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "스파이시 갈릭치즈롤", abbr: "SG", storage: { "메이크라인": 1 } },
    { category: "치즈", name: "체다 치즈", abbr: "CD", storage: { "워크인 랙산": 3, "메이크라인": 1 } },
    { category: "치즈", name: "치즈", abbr: "X", storage: { "해동": 14, "워크인 랙산": 1, "메이크라인": 1 } },
    { category: "치즈", name: "치즈(템퍼링)", abbr: "X", storage: {} },
    { category: "소스", name: "페퍼 BBQ 소스", abbr: "Z", storage: { "워크인 랙산": 7, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "갈릭 랜치 소스", abbr: "GR", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "갈릭 소스", abbr: "A", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "맥앤치즈 소스", abbr: "", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "불고기 소스", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 1, "소스보틀": 12 } },
    { category: "소스", name: "알프레도 소스", abbr: "AL", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "제스티버거소스", abbr: "ZB", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "캔", name: "블랙 올리브", abbr: "R", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "파인애플", abbr: "N", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "콘", abbr: "C", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "할라페뇨", abbr: "J", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "피자소스", abbr: "PS", storage: { "소스보틀": 10 } },
    { category: "기타", name: "고구마 무스", abbr: "SM", storage: { "메이크라인": 2 } },
    { category: "기타", name: "브라우니", abbr: "", storage: { "해동": 14, "메이크라인": 2 } },
    { category: "기타", name: "솔티드 카라멜", abbr: "", storage: { "해동": 14, "메이크라인": 2 } },
    { category: "기타", name: "초코칩 쿠키", abbr: "", storage: { "해동": 14, "메이크라인": 2 } },
    { category: "기타", name: "큰새우", abbr: "", storage: { "해동": 5, "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "기타", name: "포데이토 청크", abbr: "U", storage: { "해동": 5, "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "기타", name: "피클", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "기타", name: "더스티네이터", abbr: "", storage: { "메이크라인": 14 } },
    { category: "기타", name: "새니타이저", abbr: "", storage: { "소스보틀": 7 } },
    { category: "기타", name: "피자소스 배달(소분)", abbr: "", storage: { "워크인 랙산": 1, "메이크라인": 1 } },
    { category: "기타", name: "이탈리안 허브", abbr: "", storage: { "메이크라인": 180 } },
    { category: "기타", name: "레드 페퍼", abbr: "", storage: { "메이크라인": 180 } },
    { category: "기타", name: "후레쉬 파프리카 피클", abbr: "", storage: { "워크인 랙산": 14, "메이크라인": 2 } },
    { category: "도우", name: "레귤러 분할 3일차", abbr: "R(3D)", storage: { "분할": 24 } },
    { category: "도우", name: "레귤러 분할 4일차", abbr: "R(4D)", storage: { "분할": 24 } },
    { category: "도우", name: "레귤러 분할 5일차", abbr: "R(5D)", storage: { "분할": 24 } },
    { category: "도우", name: "레귤러 분할 6일차", abbr: "R(6D)", storage: { "분할": 24 } },
    { category: "도우", name: "레귤러 분할 7일차", abbr: "R(7D)", storage: { "분할": 22 } },
    { category: "도우", name: "라지 분할 3일차", abbr: "R(3D)", storage: { "분할": 24 } },
    { category: "도우", name: "라지 분할 4일차", abbr: "R(4D)", storage: { "분할": 24 } },
    { category: "도우", name: "라지 분할 5일차", abbr: "R(5D)", storage: { "분할": 24 } },
    { category: "도우", name: "라지 분할 6일차", abbr: "R(6D)", storage: { "분할": 24 } },
    { category: "도우", name: "라지 분할 7일차", abbr: "R(7D)", storage: { "분할": 22 } },
    { category: "도우", name: "패밀리 분할 3일차", abbr: "R(3D)", storage: { "분할": 24 } },
    { category: "도우", name: "패밀리 분할 4일차", abbr: "R(4D)", storage: { "분할": 24 } },
    { category: "도우", name: "패밀리 분할 5일차", abbr: "R(5D)", storage: { "분할": 24 } },
    { category: "도우", name: "패밀리 분할 6일차", abbr: "R(6D)", storage: { "분할": 24 } },
    { category: "도우", name: "패밀리 분할 7일차", abbr: "R(7D)", storage: { "분할": 22 } },
    { category: "도우", name: "파티 분할 3일차", abbr: "R(3D)", storage: { "분할": 24 } },
    { category: "도우", name: "파티 분할 4일차", abbr: "R(4D)", storage: { "분할": 24 } },
    { category: "도우", name: "파티 분할 5일차", abbr: "R(5D)", storage: { "분할": 24 } },
    { category: "도우", name: "파티 분할 6일차", abbr: "R(6D)", storage: { "분할": 24 } },
    { category: "도우", name: "파티 분할 7일차", abbr: "R(7D)", storage: { "분할": 22 } }
];

// ==========================================
// Express Setup
// ==========================================
const sessions = {}; // key: token, value: { username, role, expiresAt }
const loginFailures = new Map(); // key: ip + username, value: { count, resetAt }

app.use(express.json());

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

function getActiveSession(req, res) {
    const token = req.cookies.session_token;
    if (!token || !sessions[token]) {
        return null;
    }
    if (sessions[token].expiresAt < Date.now()) {
        delete sessions[token];
        res.clearCookie('session_token');
        return null;
    }
    return sessions[token];
}

function requireRole(role) {
    return (req, res, next) => {
        const session = getActiveSession(req, res);
        if (!session) {
            return res.status(401).json({ error: '로그인이 필요합니다.' });
        }
        if (role && session.role !== role) {
            return res.status(403).json({ error: '관리자 권한이 필요합니다.' });
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

async function seedDefaultsAsync() {
    const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, emoji, sort_order) VALUES (?, ?, ?)");
    DEFAULT_CATEGORIES.forEach(c => catStmt.run(c.name, c.emoji, c.sort_order));
    await finalizeAsync(catStmt);

    const slStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order) VALUES (?, ?)");
    DEFAULT_STORAGE_LOCATIONS.forEach(s => slStmt.run(s.name, s.sort_order));
    await finalizeAsync(slStmt);

    const ingStmt = db.prepare("INSERT OR IGNORE INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
    DEFAULT_INGREDIENTS.forEach(i => ingStmt.run(i.name, i.category, i.abbr || ''));
    await finalizeAsync(ingStmt);

    const locations = await allAsync("SELECT id, name FROM storage_locations");
    const locMap = {};
    locations.forEach(l => { locMap[l.name] = l.id; });

    const stStmt = db.prepare("INSERT OR IGNORE INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
    DEFAULT_INGREDIENTS.forEach(item => {
        Object.entries(item.storage).forEach(([locName, days]) => {
            if (locMap[locName]) {
                stStmt.run(item.name, locMap[locName], days);
            }
        });
    });
    await finalizeAsync(stStmt);

    const lsStmt = db.prepare("INSERT OR IGNORE INTO label_sizes (width, height, is_default) VALUES (?, ?, ?)");
    DEFAULT_LABEL_SIZES.forEach(s => lsStmt.run(s.width, s.height, s.is_default));
    await finalizeAsync(lsStmt);
}

let db;

function startDatabase() {
    if (db) return db;
    validateRuntimeSecurityConfig();

    db = new sqlite3.Database(DB_PATH, (err) => {
        if (err) {
            console.error('Error opening database:', err.message);
        } else {
            console.log('Connected to SQLite database at:', DB_PATH);
            db.run("PRAGMA foreign_keys = ON");
            initDatabase();
        }
    });

    return db;
}

// ==========================================
// Database Initialization & Migration
// ==========================================
function seedDefaultUsers() {
    const adminHash = hashPassword(process.env.DEFAULT_ADMIN_PASSWORD || 'admin');
    const staffHash = hashPassword(process.env.DEFAULT_STAFF_PASSWORD || 'staff');
    
    db.get("SELECT username FROM users WHERE username = 'admin'", (err, row) => {
        if (!row) {
            console.log('Seeding default admin user');
            db.run("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['admin', adminHash, 'admin']);
        }
    });
    
    db.get("SELECT username FROM users WHERE username = 'staff'", (err, row) => {
        if (!row) {
            console.log('Seeding default staff user');
            db.run("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ['staff', staffHash, 'staff']);
        }
    });
}

function initDatabase() {
    db.serialize(() => {
        // Create user table
        db.run(`CREATE TABLE IF NOT EXISTS users (
            username TEXT PRIMARY KEY,
            password TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'staff'
        )`, (err) => {
            if (!err) seedDefaultUsers();
        });

        // Create new tables
        db.run(`CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            emoji TEXT DEFAULT '',
            sort_order INTEGER DEFAULT 0
        )`);

        db.run(`CREATE TABLE IF NOT EXISTS storage_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            sort_order INTEGER DEFAULT 0
        )`);

        db.run(`CREATE TABLE IF NOT EXISTS label_sizes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            width INTEGER NOT NULL,
            height INTEGER NOT NULL,
            is_default INTEGER DEFAULT 0
        )`, (err) => {
            if (!err) checkAndSeedLabelSizes();
        });

        db.run(`CREATE TABLE IF NOT EXISTS ingredients_v2 (
            name TEXT PRIMARY KEY,
            category TEXT NOT NULL,
            abbr TEXT DEFAULT ''
        )`);

        db.run(`CREATE TABLE IF NOT EXISTS ingredient_storage (
            ingredient_name TEXT NOT NULL,
            storage_id INTEGER NOT NULL,
            shelf_days INTEGER NOT NULL,
            PRIMARY KEY (ingredient_name, storage_id),
            FOREIGN KEY (ingredient_name) REFERENCES ingredients_v2(name) ON DELETE CASCADE,
            FOREIGN KEY (storage_id) REFERENCES storage_locations(id) ON DELETE CASCADE
        )`, () => {
            checkAndMigrate();
        });
    });
}

function checkAndMigrate() {
    // Check if the old 'ingredients' table with walkin column exists
    db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='ingredients'", (err, row) => {
        if (row) {
            // Old table exists — check if it has the old schema (walkin column)
            db.all("PRAGMA table_info(ingredients)", (err, columns) => {
                const hasWalkin = columns && columns.some(c => c.name === 'walkin');
                if (hasWalkin) {
                    console.log('Old schema detected. Running migration...');
                    migrateFromOldSchema();
                } else {
                    // Old table exists but doesn't have walkin — maybe already migrated
                    checkAndSeedNewSchema();
                }
            });
        } else {
            // No old table — fresh install
            checkAndSeedNewSchema();
        }
    });
}

function migrateFromOldSchema() {
    db.serialize(() => {
        // 1. Seed categories
        const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, emoji, sort_order) VALUES (?, ?, ?)");
        DEFAULT_CATEGORIES.forEach(c => catStmt.run(c.name, c.emoji, c.sort_order));
        catStmt.finalize();

        // 2. Seed storage locations
        const slStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order) VALUES (?, ?)");
        DEFAULT_STORAGE_LOCATIONS.forEach(s => slStmt.run(s.name, s.sort_order));
        slStmt.finalize();

        // 3. Migrate ingredients from old table
        db.all("SELECT * FROM ingredients", (err, rows) => {
            if (err || !rows || rows.length === 0) {
                console.log('No data to migrate from old ingredients table.');
                db.run("DROP TABLE IF EXISTS ingredients", () => {
                    checkAndSeedNewSchema();
                });
                return;
            }

            const ingStmt = db.prepare("INSERT OR IGNORE INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
            rows.forEach(r => ingStmt.run(r.name, r.category, r.abbr || ''));
            ingStmt.finalize();

            // Map old columns to storage locations
            db.all("SELECT id, name FROM storage_locations", (err, locations) => {
                const locMap = {};
                locations.forEach(l => { locMap[l.name] = l.id; });

                const stStmt = db.prepare("INSERT OR IGNORE INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
                rows.forEach(r => {
                    if (r.walkin !== null && r.walkin !== undefined && locMap["워크인 랙산"]) {
                        stStmt.run(r.name, locMap["워크인 랙산"], r.walkin);
                    }
                    if (r.makeline !== null && r.makeline !== undefined && locMap["메이크라인"]) {
                        stStmt.run(r.name, locMap["메이크라인"], r.makeline);
                    }
                    if (r.bottle !== null && r.bottle !== undefined && locMap["소스보틀"]) {
                        stStmt.run(r.name, locMap["소스보틀"], r.bottle);
                    }
                });
                stStmt.finalize(() => {
                    console.log(`Migrated ${rows.length} ingredients to new schema.`);
                    // Drop old table
                    db.run("DROP TABLE IF EXISTS ingredients", () => {
                        console.log('Old ingredients table dropped.');
                    });
                });
            });
        });
    });
}

function checkAndSeedNewSchema() {
    db.get("SELECT COUNT(*) as count FROM ingredients_v2", (err, row) => {
        if (err || (row && row.count > 0)) {
            if (row) console.log(`Database has ${row.count} ingredients (v2 schema).`);
            return;
        }
        console.log('Seeding new schema with default data...');
        seedDefaultsAsync().catch(seedErr => {
            console.error('Error seeding default data:', seedErr.message);
        });
    });
}

function checkAndSeedLabelSizes() {
    console.log("Checking and seeding default label sizes...");
    const checkStmt = db.prepare("SELECT id FROM label_sizes WHERE width = ? AND height = ?");
    let pending = DEFAULT_LABEL_SIZES.length;

    const finishOne = () => {
        pending -= 1;
        if (pending === 0) {
            checkStmt.finalize();
        }
    };

    db.serialize(() => {
        DEFAULT_LABEL_SIZES.forEach(s => {
            checkStmt.get(s.width, s.height, (err, row) => {
                if (err) {
                    console.error(`Error checking label size ${s.width}x${s.height}:`, err.message);
                    finishOne();
                    return;
                }
                if (!row) {
                    console.log(`Seeding missing default label size: ${s.width}x${s.height}`);
                    db.run("INSERT INTO label_sizes (width, height, is_default) VALUES (?, ?, ?)", [s.width, s.height, s.is_default], finishOne);
                } else {
                    finishOne();
                }
            });
        });
    });
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

    db.get("SELECT * FROM users WHERE username = ?", [username], (err, user) => {
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

        const token = crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex');
        const expiresAt = Date.now() + SESSION_MAX_AGE_MS;
        sessions[token] = { username: user.username, role: user.role, expiresAt };

        res.cookie('session_token', token, {
            httpOnly: true,
            maxAge: SESSION_MAX_AGE_MS,
            sameSite: 'strict',
            secure: isProduction(),
            path: '/'
        });

        res.json({ success: true, user: { username: user.username, role: user.role } });
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
// API: Categories
// ==========================================
app.get('/api/categories', requireLogin, (req, res) => {
    db.all("SELECT * FROM categories ORDER BY sort_order ASC, id ASC", [], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.post('/api/categories', requireAdmin, (req, res) => {
    const { name, emoji } = req.body;
    if (!name) return res.status(400).json({ error: '카테고리 이름은 필수입니다.' });
    db.run("INSERT INTO categories (name, emoji, sort_order) VALUES (?, ?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM categories))",
        [name, emoji || ''], function(err) {
            if (err) {
                if (err.message.includes('UNIQUE')) return res.status(400).json({ error: '이미 존재하는 카테고리입니다.' });
                return res.status(500).json({ error: err.message });
            }
            res.status(201).json({ id: this.lastID, name, emoji: emoji || '' });
        });
});

app.delete('/api/categories/:id', requireAdmin, (req, res) => {
    db.run("DELETE FROM categories WHERE id = ?", [req.params.id], function(err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ success: true });
    });
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

app.post('/api/storage-locations', requireAdmin, (req, res) => {
    const { name } = req.body;
    if (!name) return res.status(400).json({ error: '보관위치 이름은 필수입니다.' });
    db.run("INSERT INTO storage_locations (name, sort_order) VALUES (?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM storage_locations))",
        [name], function(err) {
            if (err) {
                if (err.message.includes('UNIQUE')) return res.status(400).json({ error: '이미 존재하는 보관위치입니다.' });
                return res.status(500).json({ error: err.message });
            }
            res.status(201).json({ id: this.lastID, name });
        });
});

app.delete('/api/storage-locations/:id', requireAdmin, (req, res) => {
    db.run("DELETE FROM storage_locations WHERE id = ?", [req.params.id], function(err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ success: true });
    });
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

app.post('/api/label-sizes', requireAdmin, (req, res) => {
    const { width, height } = req.body;
    const w = parseInt(width);
    const h = parseInt(height);
    if (!isSafePositiveInteger(w) || !isSafePositiveInteger(h)) {
        return res.status(400).json({ error: '가로와 세로 크기는 필수입니다.' });
    }
    if (w < 20 || w > 150 || h < 15 || h > 150) {
        return res.status(400).json({ error: '가로 크기는 20~150mm, 세로 크기는 15~150mm 사이여야 합니다.' });
    }

    db.get("SELECT id FROM label_sizes WHERE width = ? AND height = ?", [w, h], (err, row) => {
        if (err) return res.status(500).json({ error: err.message });
        if (row) return res.status(400).json({ error: '이미 존재하는 규격 프리셋입니다.' });

        db.run("INSERT INTO label_sizes (width, height, is_default) VALUES (?, ?, 0)", [w, h], function(err) {
            if (err) return res.status(500).json({ error: err.message });
            res.status(201).json({ id: this.lastID, width: w, height: h, is_default: 0 });
        });
    });
});

app.delete('/api/label-sizes/:id', requireAdmin, (req, res) => {
    db.run("DELETE FROM label_sizes WHERE id = ?", [req.params.id], function(err) {
        if (err) return res.status(500).json({ error: err.message });
        res.json({ success: true });
    });
});

// ==========================================
// API: Ingredients (v2 — with dynamic storage)
// ==========================================
app.get('/api/ingredients', requireLogin, (req, res) => {
    // Join ingredients with their storage mappings
    db.all("SELECT * FROM ingredients_v2 ORDER BY name ASC", [], (err, ingredients) => {
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

app.post('/api/ingredients', requireAdmin, (req, res) => {
    const { category, name, abbr, storage } = req.body;
    if (!name || !category) return res.status(400).json({ error: '재료명과 카테고리는 필수 항목입니다.' });

    if (storage && typeof storage === 'object') {
        for (const [storageId, days] of Object.entries(storage)) {
            if (days !== null && days !== '' && days !== undefined) {
                if (!isSafePositiveInteger(storageId) || !isSafePositiveInteger(days)) {
                    return res.status(400).json({ error: '보관위치와 유통기한은 양의 정수여야 합니다.' });
                }
            }
        }
    }

    db.run("INSERT INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)",
        [name, category, abbr || ''], function(err) {
            if (err) {
                if (err.message.includes('UNIQUE')) return res.status(400).json({ error: '이미 존재하는 재료 이름입니다.' });
                return res.status(500).json({ error: err.message });
            }
            // Insert storage mappings
            if (storage && typeof storage === 'object') {
                const entries = Object.entries(storage);
                if (entries.length === 0) return res.status(201).json({ success: true });

                const stStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
                entries.forEach(([storageId, days]) => {
                    if (days !== null && days !== '' && days !== undefined) {
                        stStmt.run(name, parseInt(storageId), parseInt(days));
                    }
                });
                stStmt.finalize((err) => {
                    if (err) return res.status(500).json({ error: err.message });
                    res.status(201).json({ success: true });
                });
            } else {
                res.status(201).json({ success: true });
            }
        });
});

app.delete('/api/ingredients/:name', requireAdmin, (req, res) => {
    const name = decodeURIComponent(req.params.name);
    db.serialize(() => {
        db.run("DELETE FROM ingredient_storage WHERE ingredient_name = ?", [name]);
        db.run("DELETE FROM ingredients_v2 WHERE name = ?", [name], function(err) {
            if (err) return res.status(500).json({ error: err.message });
            res.json({ success: true });
        });
    });
});

app.put('/api/ingredients/:oldName', requireAdmin, (req, res) => {
    const oldName = decodeURIComponent(req.params.oldName);
    const { category, name, abbr, storage } = req.body;
    if (!name || !category) return res.status(400).json({ error: '재료명과 카테고리는 필수 항목입니다.' });

    if (storage && typeof storage === 'object') {
        for (const [storageId, days] of Object.entries(storage)) {
            if (days !== null && days !== '' && days !== undefined) {
                if (!isSafePositiveInteger(storageId) || !isSafePositiveInteger(days)) {
                    return res.status(400).json({ error: '보관위치와 유통기한은 양의 정수여야 합니다.' });
                }
            }
        }
    }

    const nameChanged = oldName.toLowerCase() !== name.toLowerCase();

    db.serialize(() => {
        const performUpdate = () => {
            db.run("DELETE FROM ingredient_storage WHERE ingredient_name = ?", [oldName], (err) => {
                if (err) return res.status(500).json({ error: err.message });

                db.run("UPDATE ingredients_v2 SET name = ?, category = ?, abbr = ? WHERE name = ?",
                    [name, category, abbr || '', oldName], function(err) {
                        if (err) {
                            if (err.message.includes('UNIQUE')) return res.status(400).json({ error: '이미 존재하는 재료 이름입니다.' });
                            return res.status(500).json({ error: err.message });
                        }

                        // Insert storage mappings
                        if (storage && typeof storage === 'object') {
                            const entries = Object.entries(storage);
                            if (entries.length === 0) return res.json({ success: true });

                            const stStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
                            entries.forEach(([storageId, days]) => {
                                if (days !== null && days !== '' && days !== undefined) {
                                    stStmt.run(name, parseInt(storageId), parseInt(days));
                                }
                            });
                            stStmt.finalize((err) => {
                                if (err) return res.status(500).json({ error: err.message });
                                res.json({ success: true });
                            });
                        } else {
                            res.json({ success: true });
                        }
                    });
            });
        };

        if (nameChanged) {
            db.get("SELECT name FROM ingredients_v2 WHERE name = ?", [name], (err, row) => {
                if (err) return res.status(500).json({ error: err.message });
                if (row) return res.status(400).json({ error: '이미 존재하는 재료 이름입니다.' });
                performUpdate();
            });
        } else {
            performUpdate();
        }
    });
});

const upload = multer({ storage: multer.memoryStorage() });

app.get('/api/ingredients/sample-excel', requireLogin, (req, res) => {
    const filePath = path.join(__dirname, 'files', 'SHELFLIFE_sample.xlsx');
    res.download(filePath, 'SHELFLIFE_sample.xlsx', (err) => {
        if (err) {
            res.status(500).json({ error: '샘플 파일을 다운로드하는 중에 오류가 발생했습니다.' });
        }
    });
});

app.post('/api/ingredients/upload-excel', requireAdmin, upload.single('file'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: '엑셀 파일을 업로드해 주세요.' });
    }

    try {
        const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
        const sheetName = workbook.SheetNames[0];
        const sheet = workbook.Sheets[sheetName];
        const rows = xlsx.utils.sheet_to_json(sheet, { header: 1 });

        if (!rows || rows.length < 2) {
            return res.status(400).json({ error: '유효하지 않은 엑셀 파일 형식입니다.' });
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
                currentCategory = String(colCat).trim();
            }

            if (colName) {
                const name = String(colName).trim();
                const abbr = colAbbr ? String(colAbbr).trim() : '';
                const category = currentCategory || '기타';

                parsedCategories.add(category);

                const storage = {};
                if (!isTable2) {
                    if (row[4] !== null && row[4] !== undefined && row[4] !== '') {
                        const val = parseInt(row[4]);
                        if (!isNaN(val)) storage['해동'] = val;
                    }
                    if (row[5] !== null && row[5] !== undefined && row[5] !== '') {
                        const val = parseInt(row[5]);
                        if (!isNaN(val)) storage['워크인 랙산'] = val;
                    }
                    if (row[6] !== null && row[6] !== undefined && row[6] !== '') {
                        const val = parseInt(row[6]);
                        if (!isNaN(val)) storage['메이크라인'] = val;
                    }
                    if (row[7] !== null && row[7] !== undefined && row[7] !== '') {
                        const val = parseInt(row[7]);
                        if (!isNaN(val)) storage['소스보틀'] = val;
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
                            if (!isNaN(val)) {
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

        db.serialize(() => {
            db.run("BEGIN TRANSACTION");
            
            // Insert missing categories
            const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, sort_order) VALUES (?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM categories))");
            parsedCategories.forEach(cat => {
                catStmt.run(cat);
            });
            catStmt.finalize();

            // Ensure storage locations exist
            const defLocations = ["해동", "워크인 랙산", "메이크라인", "소스보틀", "분할"];
            const locStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order) VALUES (?, (SELECT COALESCE(MAX(sort_order),0)+1 FROM storage_locations))");
            defLocations.forEach(loc => {
                locStmt.run(loc);
            });
            locStmt.finalize();

            // Clear active ingredients and storage mappings
            db.run("DELETE FROM ingredient_storage");
            db.run("DELETE FROM ingredients_v2");

            const ingStmt = db.prepare("INSERT INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
            parsedIngredients.forEach(ing => {
                ingStmt.run(ing.name, ing.category, ing.abbr);
            });
            ingStmt.finalize();

            db.all("SELECT id, name FROM storage_locations", (err, dbLocations) => {
                if (err) {
                    db.run("ROLLBACK");
                    return res.status(500).json({ error: err.message });
                }

                const locMap = {};
                dbLocations.forEach(l => { locMap[l.name] = l.id; });

                const mappingStmt = db.prepare("INSERT INTO ingredient_storage (ingredient_name, storage_id, shelf_days) VALUES (?, ?, ?)");
                parsedIngredients.forEach(ing => {
                    Object.entries(ing.storage).forEach(([locName, val]) => {
                        if (locMap[locName]) {
                            mappingStmt.run(ing.name, locMap[locName], val);
                        }
                    });
                });

                mappingStmt.finalize((err) => {
                    if (err) {
                        db.run("ROLLBACK");
                        return res.status(500).json({ error: err.message });
                    }
                    db.run("COMMIT", (commitErr) => {
                        if (commitErr) {
                            return res.status(500).json({ error: commitErr.message });
                        }
                        res.json({ success: true, count: parsedIngredients.length });
                    });
                });
            });
        });

    } catch (err) {
        console.error("Excel upload parsing error:", err);
        res.status(500).json({ error: '엑셀 파싱 및 데이터베이스 업데이트 중 오류가 발생했습니다: ' + err.message });
    }
});

app.post('/api/ingredients/reset', requireAdmin, (req, res) => {
    db.serialize(() => {
        db.run("DELETE FROM ingredient_storage");
        db.run("DELETE FROM ingredients_v2");
        db.run("DELETE FROM categories");
        db.run("DELETE FROM storage_locations");
        db.run("DELETE FROM label_sizes", async (err) => {
            if (err) return res.status(500).json({ error: err.message });
            try {
                await seedDefaultsAsync();
                res.json({ success: true });
            } catch (seedErr) {
                res.status(500).json({ error: seedErr.message });
            }
        });
    });
});

// ==========================================
// Start Server
// ==========================================
if (require.main === module) {
    startDatabase();
    app.listen(PORT, () => {
        console.log(`Server is running at http://localhost:${PORT}`);
    });
}

module.exports = {
    app,
    startDatabase,
    isPasswordHash,
    hashPassword,
    verifyPassword,
    verifyLegacyPassword,
    isSafePositiveInteger,
    isLoginRateLimited,
    recordLoginFailure,
    validateRuntimeSecurityConfig,
};
