const assert = require('node:assert/strict');
const test = require('node:test');

const {
    app,
    isPasswordHash,
    hashPassword,
    verifyPassword,
    verifyLegacyPassword,
    isSafePositiveInteger,
    isLoginRateLimited,
    recordLoginFailure,
    validateRuntimeSecurityConfig,
} = require('../server');

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
