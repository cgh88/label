const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');
const fs = require('node:fs');

const testDbPath = path.join(__dirname, 'test_isolated.sqlite');
process.env.DB_PATH = testDbPath;
if (fs.existsSync(testDbPath)) {
    try { fs.unlinkSync(testDbPath); } catch (e) {}
}

const {
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
} = require('../server');

test('IP utilities correctly normalize and match client IPs', () => {
    assert.equal(normalizeIp('::ffff:192.168.0.10'), '192.168.0.10');
    assert.equal(normalizeIp('::1'), '127.0.0.1');
    assert.equal(normalizeIp('localhost'), '127.0.0.1');

    assert.equal(checkIpMatch('123.45.67.89', ''), true);
    assert.equal(checkIpMatch('123.45.67.89', '123.45.67.89, 10.0.0.1'), true);
    assert.equal(checkIpMatch('192.168.1.1', '123.45.67.89, 10.0.0.1'), false);
});

async function loginAndGetCookie(baseUrl, username = 'admin', password = 'admin') {
    const res = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
    });
    assert.equal(res.status, 200);
    return res.headers.get('set-cookie');
}

test('password hashes are salted and verifiable', () => {
    const first = hashPassword('secret');
    const second = hashPassword('secret');

    assert.notEqual(first, second);
    assert.equal(isPasswordHash(first), true);
    assert.equal(verifyPassword('secret', first).valid, true);
    assert.equal(verifyPassword('wrong', first).valid, false);
});

test('legacy sha256 passwords remain login-compatible for migration', () => {
    const legacyHash = '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918';

    assert.equal(verifyLegacyPassword('admin', legacyHash), true);
    assert.deepEqual(verifyPassword('admin', legacyHash), { valid: true, needsRehash: true });
});

test('numeric ids and shelf days reject unsafe integer inputs', () => {
    assert.equal(isSafePositiveInteger('12'), true);
    assert.equal(isSafePositiveInteger(12), true);
    assert.equal(isSafePositiveInteger('0'), false);
    assert.equal(isSafePositiveInteger('-1'), false);
    assert.equal(isSafePositiveInteger('1.5'), false);
    assert.equal(isSafePositiveInteger('abc'), false);
});

test('static allowlist does not expose server files or database', async () => {
    const server = app.listen(0);
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    try {
        assert.equal((await fetch(`${baseUrl}/index.html`)).status, 200);
        assert.equal((await fetch(`${baseUrl}/app.js`)).status, 200);
        assert.equal((await fetch(`${baseUrl}/style.css`)).status, 200);
        assert.equal((await fetch(`${baseUrl}/server.js`)).status, 404);
        assert.equal((await fetch(`${baseUrl}/database.sqlite`)).status, 404);
        assert.equal((await fetch(`${baseUrl}/.git/config`)).status, 404);
        assert.equal((await fetch(`${baseUrl}/package.json`)).status, 404);
    } finally {
        await new Promise(resolve => server.close(resolve));
    }
});

test('api/default-database returns default database content', async () => {
    const server = app.listen(0);
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    try {
        // Unauthenticated access is rejected.
        assert.equal((await fetch(`${baseUrl}/api/default-database`)).status, 401);

        const cookie = await loginAndGetCookie(baseUrl);
        const res = await fetch(`${baseUrl}/api/default-database`, { headers: { Cookie: cookie } });
        assert.equal(res.status, 200);
        const data = await res.json();
        assert.ok(data.categories);
        assert.ok(data.storage_locations);
        assert.ok(data.label_sizes);
        assert.ok(data.ingredients_v2);
        assert.ok(data.ingredient_storage);
    } finally {
        await new Promise(resolve => server.close(resolve));
    }
});

test('api/print-logs appends a log entry', async () => {
    const server = app.listen(0);
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    try {
        const payload = {
            ingredient_name: '그릴드치킨',
            category: '미트',
            abbr: 'E',
            storage_location: '해동',
            prep_date: '2026-07-10 17:00',
            expire_date: '2026-07-17 17:00',
            staff: 'admin',
            quantity: 2
        };

        // Unauthenticated access is rejected.
        assert.equal((await fetch(`${baseUrl}/api/print-logs`)).status, 401);

        const cookie = await loginAndGetCookie(baseUrl);
        const res = await fetch(`${baseUrl}/api/print-logs`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Cookie: cookie },
            body: JSON.stringify(payload)
        });

        assert.equal(res.status, 200);
        const data = await res.json();
        assert.equal(data.success, true);
        assert.equal(data.log.ingredient_name, '그릴드치킨');
        assert.equal(data.log.quantity, 2);

        // Verify GET returns it
        const getRes = await fetch(`${baseUrl}/api/print-logs`, { headers: { Cookie: cookie } });
        assert.equal(getRes.status, 200);
        const logs = await getRes.json();
        assert.ok(logs.length > 0);
        assert.equal(logs[logs.length - 1].ingredient_name, '그릴드치킨');
    } finally {
        await new Promise(resolve => server.close(resolve));
    }
});

async function loginAndGetJwt(baseUrl, username = 'admin', password = 'admin') {
    const res = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
    });
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.ok(data.token);
    return data.token;
}

test('api/sync/database requires authentication and supports JWT Bearer token', async () => {
    const server = app.listen(0);
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    try {
        // Unauthenticated access is rejected.
        assert.equal((await fetch(`${baseUrl}/api/sync/database`)).status, 401);

        // JWT Bearer token header authentication
        const jwtToken = await loginAndGetJwt(baseUrl);
        const bearerRes = await fetch(`${baseUrl}/api/sync/database`, {
            headers: { Authorization: `Bearer ${jwtToken}` }
        });
        assert.equal(bearerRes.status, 200);
        const bearerDbData = await bearerRes.json();
        assert.ok(bearerDbData.last_updated);
        assert.ok(Array.isArray(bearerDbData.categories));

        // Cookie header authentication (legacy/web support)
        const cookie = await loginAndGetCookie(baseUrl);
        const getRes = await fetch(`${baseUrl}/api/sync/database`, { headers: { Cookie: cookie } });
        assert.equal(getRes.status, 200);
        const dbData = await getRes.json();
        assert.ok(dbData.last_updated);
        assert.ok(Array.isArray(dbData.categories));

        const updatedDb = {
            ...dbData,
            last_updated: new Date().toISOString(),
            test_sync_flag: true
        };

        const postRes = await fetch(`${baseUrl}/api/sync/database`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Cookie: cookie },
            body: JSON.stringify(updatedDb)
        });
        assert.equal(postRes.status, 200);
        const postResult = await postRes.json();
        assert.equal(postResult.success, true);

        const getRes2 = await fetch(`${baseUrl}/api/sync/database`, { headers: { Cookie: cookie } });
        const dbData2 = await getRes2.json();
        assert.equal(dbData2.test_sync_flag, true);
    } finally {
        await new Promise(resolve => server.close(resolve));
    }
});

test('login failures are rate limited after repeated attempts', () => {
    const req = { ip: `test-${Date.now()}-${Math.random()}` };
    const username = 'admin';

    assert.equal(isLoginRateLimited(req, username), false);
    for (let i = 0; i < 10; i += 1) {
        recordLoginFailure(req, username);
    }
    assert.equal(isLoginRateLimited(req, username), true);
});

test('production mode requires explicit default passwords', () => {
    const originalNodeEnv = process.env.NODE_ENV;
    const originalAdminPassword = process.env.DEFAULT_ADMIN_PASSWORD;
    const originalStaffPassword = process.env.DEFAULT_STAFF_PASSWORD;

    try {
        process.env.NODE_ENV = 'production';
        delete process.env.DEFAULT_ADMIN_PASSWORD;
        delete process.env.DEFAULT_STAFF_PASSWORD;
        assert.throws(() => validateRuntimeSecurityConfig(), /DEFAULT_ADMIN_PASSWORD/);

        process.env.DEFAULT_ADMIN_PASSWORD = 'changed-admin-password';
        process.env.DEFAULT_STAFF_PASSWORD = 'changed-staff-password';
        assert.doesNotThrow(() => validateRuntimeSecurityConfig());
    } finally {
        if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
        else process.env.NODE_ENV = originalNodeEnv;

        if (originalAdminPassword === undefined) delete process.env.DEFAULT_ADMIN_PASSWORD;
        else process.env.DEFAULT_ADMIN_PASSWORD = originalAdminPassword;

        if (originalStaffPassword === undefined) delete process.env.DEFAULT_STAFF_PASSWORD;
        else process.env.DEFAULT_STAFF_PASSWORD = originalStaffPassword;
    }
});

test('api/ingredients/upload-excel rejects non-excel files', async () => {
    const server = app.listen(0);
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    try {
        await startDatabase();
        const loginRes = await fetch(`${baseUrl}/api/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: 'admin', password: 'admin' }),
        });
        const cookie = loginRes.headers.get('set-cookie');

        const formData = new FormData();
        const blob = new Blob(['fake content'], { type: 'text/plain' });
        formData.append('file', blob, 'test.txt');

        const res = await fetch(`${baseUrl}/api/ingredients/upload-excel`, {
            method: 'POST',
            headers: { Cookie: cookie },
            body: formData,
        });

        assert.equal(res.status, 400);
        const data = await res.json();
        assert.match(data.error, /엑셀 파일/);
    } finally {
        await new Promise((resolve) => server.close(resolve));
        await closeDatabase();
    }
});
