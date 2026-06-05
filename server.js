const path = require('path');
const express = require('express');
const sqlite3 = require('sqlite3').verbose();

const app = express();
const PORT = process.env.PORT || 3000;
const DB_PATH = path.join(__dirname, 'database.sqlite');

// ==========================================
// Default Seed Data
// ==========================================
const DEFAULT_CATEGORIES = [
    { name: "미트", emoji: "🍖", sort_order: 1 },
    { name: "야채", emoji: "🥬", sort_order: 2 },
    { name: "치즈", emoji: "🧀", sort_order: 3 },
    { name: "소스", emoji: "🏺", sort_order: 4 },
    { name: "캔",   emoji: "🥫", sort_order: 5 },
    { name: "기타", emoji: "🍕", sort_order: 6 }
];

const DEFAULT_STORAGE_LOCATIONS = [
    { name: "워크인 랙산", sort_order: 1 },
    { name: "메이크라인", sort_order: 2 },
    { name: "소스보틀",   sort_order: 3 }
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
    // 미트
    { category: "미트", name: "그릴드치킨", abbr: "E", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "베이컨", abbr: "K", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "햄", abbr: "H", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "페페로니", abbr: "P", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "불고기", abbr: "L", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "비프", abbr: "B", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "숏립", abbr: "", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "이탈리안 소시지", abbr: "I", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "미트", name: "치킨스트립", abbr: "CSHM", storage: { "워크인 랙산": 3, "메이크라인": 1 } },
    { category: "미트", name: "파파스윙", abbr: "10WG", storage: { "워크인 랙산": 3, "메이크라인": 1 } },
    // 야채
    { category: "야채", name: "양송이 버섯", abbr: "M", storage: { "워크인 랙산": 6, "메이크라인": 1 } },
    { category: "야채", name: "양파", abbr: "O", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "야채", name: "청피망", abbr: "G", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "야채", name: "토마토", abbr: "T", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    // 치즈
    { category: "치즈", name: "2 블랜드치즈", abbr: "2BX", storage: { "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "3 블랜드치즈", abbr: "3BX", storage: { "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "스트링 치즈", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "체다스트링 치즈", abbr: "CC", storage: { "워크인 랙산": 7, "메이크라인": 1 } },
    { category: "치즈", name: "체다 치즈", abbr: "CD", storage: { "워크인 랙산": 3, "메이크라인": 1 } },
    { category: "치즈", name: "치즈", abbr: "X", storage: { "워크인 랙산": 7, "메이크라인": 1 } },
    // 소스
    { category: "소스", name: "페퍼 BBQ 소스", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "갈릭 랜치 소스", abbr: "GR", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "갈릭 소스", abbr: "", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "맥앤치즈 소스", abbr: "", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "불고기 소스", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 1, "소스보틀": 12 } },
    { category: "소스", name: "알프레도 소스", abbr: "AL", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    { category: "소스", name: "제스티 버거 소스", abbr: "", storage: { "워크인 랙산": 5, "메이크라인": 2, "소스보틀": 12 } },
    // 캔
    { category: "캔", name: "블랙 올리브", abbr: "R", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "파인애플", abbr: "N", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "콘", abbr: "C", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "할라페뇨", abbr: "J", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "캔", name: "토마토 소스", abbr: "", storage: { "워크인 랙산": 1, "메이크라인": 1 } },
    // 기타
    { category: "기타", name: "고구마 무스", abbr: "SM", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "기타", name: "큰새우", abbr: "", storage: { "워크인 랙산": 2, "메이크라인": 1 } },
    { category: "기타", name: "포데이토 청크", abbr: "U", storage: { "워크인 랙산": 3, "메이크라인": 2 } },
    { category: "기타", name: "피클", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "기타", name: "더스티네이터", abbr: "", storage: { "워크인 랙산": 14, "메이크라인": 14 } },
    { category: "기타", name: "새니타이저", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 7, "소스보틀": 7 } },
    { category: "기타", name: "디아즈", abbr: "", storage: {} },
    { category: "기타", name: "직원용", abbr: "", storage: { "워크인 랙산": 1, "메이크라인": 1 } },
    { category: "기타", name: "토마토소스 배달", abbr: "", storage: { "워크인 랙산": 1, "메이크라인": 1 } },
    { category: "기타", name: "이탈리안 허브", abbr: "", storage: { "워크인 랙산": 180, "메이크라인": 30 } },
    { category: "기타", name: "레드 페퍼", abbr: "", storage: { "워크인 랙산": 180, "메이크라인": 30 } },
    { category: "기타", name: "감자 후레이크", abbr: "", storage: { "워크인 랙산": 7, "메이크라인": 2 } },
    { category: "기타", name: "TH(씬)", abbr: "", storage: {} }
];

// ==========================================
// Express Setup
// ==========================================
const crypto = require('crypto');
const sessions = {}; // key: token, value: { username, role, expiresAt }

app.use(express.json());
app.use(express.static(__dirname));

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

// Authentication Middlewares
function requireLogin(req, res, next) {
    const token = req.cookies.session_token;
    if (!token || !sessions[token]) {
        return res.status(401).json({ error: '로그인이 필요합니다.' });
    }
    if (sessions[token].expiresAt < Date.now()) {
        delete sessions[token];
        res.clearCookie('session_token');
        return res.status(401).json({ error: '세션이 만료되었습니다. 다시 로그인해 주세요.' });
    }
    req.user = sessions[token];
    next();
}

function requireAdmin(req, res, next) {
    const token = req.cookies.session_token;
    if (!token || !sessions[token]) {
        return res.status(401).json({ error: '로그인이 필요합니다.' });
    }
    if (sessions[token].expiresAt < Date.now()) {
        delete sessions[token];
        res.clearCookie('session_token');
        return res.status(401).json({ error: '세션이 만료되었습니다.' });
    }
    if (sessions[token].role !== 'admin') {
        return res.status(403).json({ error: '관리자 권한이 필요합니다.' });
    }
    req.user = sessions[token];
    next();
}

const db = new sqlite3.Database(DB_PATH, (err) => {
    if (err) {
        console.error('Error opening database:', err.message);
    } else {
        console.log('Connected to SQLite database at:', DB_PATH);
        db.run("PRAGMA foreign_keys = ON");
        initDatabase();
    }
});

// ==========================================
// Database Initialization & Migration
// ==========================================
function seedDefaultUsers() {
    const adminHash = crypto.createHash('sha256').update('admin').digest('hex');
    const staffHash = crypto.createHash('sha256').update('staff').digest('hex');
    
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
        seedAllDefaults();
    });
}

function checkAndSeedLabelSizes() {
    console.log("Checking and seeding default label sizes...");
    const checkStmt = db.prepare("SELECT id FROM label_sizes WHERE width = ? AND height = ?");
    
    db.serialize(() => {
        DEFAULT_LABEL_SIZES.forEach(s => {
            checkStmt.get(s.width, s.height, (err, row) => {
                if (err) {
                    console.error(`Error checking label size ${s.width}x${s.height}:`, err.message);
                    return;
                }
                if (!row) {
                    console.log(`Seeding missing default label size: ${s.width}x${s.height}`);
                    db.run("INSERT INTO label_sizes (width, height, is_default) VALUES (?, ?, ?)", [s.width, s.height, s.is_default]);
                }
            });
        });
    });

    setTimeout(() => {
        checkStmt.finalize();
    }, 1000);
}

function seedLabelSizes() {
    const lsStmt = db.prepare("INSERT INTO label_sizes (width, height, is_default) VALUES (?, ?, ?)");
    DEFAULT_LABEL_SIZES.forEach(s => lsStmt.run(s.width, s.height, s.is_default));
    lsStmt.finalize((err) => {
        if (err) console.error("Error seeding label sizes:", err.message);
        else console.log("Seeding label sizes completed.");
    });
}

function seedAllDefaults() {
    db.serialize(() => {
        // Categories
        const catStmt = db.prepare("INSERT OR IGNORE INTO categories (name, emoji, sort_order) VALUES (?, ?, ?)");
        DEFAULT_CATEGORIES.forEach(c => catStmt.run(c.name, c.emoji, c.sort_order));
        catStmt.finalize();

        // Storage Locations
        const slStmt = db.prepare("INSERT OR IGNORE INTO storage_locations (name, sort_order) VALUES (?, ?)");
        DEFAULT_STORAGE_LOCATIONS.forEach(s => slStmt.run(s.name, s.sort_order));
        slStmt.finalize();

        // Ingredients
        const ingStmt = db.prepare("INSERT OR IGNORE INTO ingredients_v2 (name, category, abbr) VALUES (?, ?, ?)");
        DEFAULT_INGREDIENTS.forEach(i => ingStmt.run(i.name, i.category, i.abbr || ''));
        ingStmt.finalize();

        // Ingredient-storage mapping
        db.all("SELECT id, name FROM storage_locations", (err, locations) => {
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
            stStmt.finalize(() => {
                console.log('Successfully seeded all default data (v2 schema).');
            });
        });

        // Seed label sizes
        seedLabelSizes();
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
    
    const hash = crypto.createHash('sha256').update(password).digest('hex');
    db.get("SELECT * FROM users WHERE username = ?", [username], (err, user) => {
        if (err) return res.status(500).json({ error: err.message });
        if (!user || user.password !== hash) {
            return res.status(400).json({ error: '아이디 또는 비밀번호가 올바르지 않습니다.' });
        }
        
        const token = crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex');
        const expiresAt = Date.now() + 2 * 60 * 60 * 1000; // 2 hours
        sessions[token] = { username: user.username, role: user.role, expiresAt };
        
        res.cookie('session_token', token, {
            httpOnly: true,
            maxAge: 2 * 60 * 60 * 1000, // 2 hours
            sameSite: 'strict',
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
    const token = req.cookies.session_token;
    if (token && sessions[token]) {
        if (sessions[token].expiresAt > Date.now()) {
            return res.json({ loggedIn: true, user: { username: sessions[token].username, role: sessions[token].role } });
        } else {
            delete sessions[token];
            res.clearCookie('session_token');
        }
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
    if (!w || !h) return res.status(400).json({ error: '가로와 세로 크기는 필수입니다.' });
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

app.post('/api/ingredients/reset', requireAdmin, (req, res) => {
    db.serialize(() => {
        db.run("DELETE FROM ingredient_storage");
        db.run("DELETE FROM ingredients_v2");
        db.run("DELETE FROM categories");
        db.run("DELETE FROM storage_locations");
        db.run("DELETE FROM label_sizes", () => {
            seedAllDefaults();
            // Wait a moment for seed to complete
            setTimeout(() => {
                res.json({ success: true });
            }, 500);
        });
    });
});

// ==========================================
// Start Server
// ==========================================
app.listen(PORT, () => {
    console.log(`Server is running at http://localhost:${PORT}`);
});
