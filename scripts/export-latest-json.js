const sqlite3 = require('sqlite3').verbose();
const fs = require('fs');
const path = require('path');

const dbPath = path.join(__dirname, '..', 'database.sqlite');
const rootJsonPath = path.join(__dirname, '..', 'default_database.json');
const clientJsonPath = path.join(__dirname, '..', 'client_flutter', 'assets', 'json', 'default_database.json');

const db = new sqlite3.Database(dbPath);

function allAsync(sql, params = []) {
    return new Promise((resolve, reject) => {
        db.all(sql, params, (err, rows) => {
            if (err) reject(err);
            else resolve(rows);
        });
    });
}

async function exportJson() {
    try {
        const categories = await allAsync("SELECT * FROM categories ORDER BY sort_order ASC, id ASC");
        const storage_locations = await allAsync("SELECT * FROM storage_locations ORDER BY sort_order ASC, id ASC");
        const label_sizes = await allAsync("SELECT * FROM label_sizes ORDER BY width ASC, height ASC, id ASC");
        const ingredients_v2 = await allAsync("SELECT * FROM ingredients_v2 ORDER BY CASE WHEN sort_order IS NULL OR sort_order = 0 THEN 99999 ELSE sort_order END ASC, category ASC, name ASC");
        const ingredient_storage = await allAsync("SELECT * FROM ingredient_storage");

        const nowIso = new Date().toISOString();

        db.run("INSERT OR REPLACE INTO db_metadata (key, value) VALUES ('last_updated', ?)", [nowIso]);

        const data = {
            last_updated: nowIso,
            categories,
            storage_locations,
            label_sizes,
            ingredients_v2,
            ingredient_storage
        };

        fs.writeFileSync(rootJsonPath, JSON.stringify(data, null, 4) + '\n', 'utf8');
        fs.writeFileSync(clientJsonPath, JSON.stringify(data, null, 4) + '\n', 'utf8');

        console.log(`Successfully exported latest database to JSON files!`);
        console.log(`  Timestamp: ${nowIso}`);
        console.log(`  Root: ${rootJsonPath}`);
        console.log(`  Client Asset: ${clientJsonPath}`);
    } catch (err) {
        console.error('Error exporting JSON:', err);
    } finally {
        db.close();
    }
}

exportJson();
