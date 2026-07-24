// One-off surgery: replace the hardcoded DEFAULT_* seed block in server.js
// (lines 24-121, 1-based) with a loader that uses default_database.json as the
// single source of truth. Usage: node scripts/replace-seed-block.js
const fs = require('fs');
const path = require('path');

const serverPath = path.join(__dirname, '..', 'server.js');
const content = fs.readFileSync(serverPath, 'utf8');
const eol = content.includes('\r\n') ? '\r\n' : '\n';
const lines = content.split(eol);

// Sanity-check the block boundaries before splicing (1-based lines 24 and 121)
const startIdx = 23; // line 24
const endIdx = 121;  // line 121 -> slice end index (exclusive)
if (!lines[startIdx + 1].includes('Default Seed Data')) {
    throw new Error(`Unexpected block start near line 25: ${lines[startIdx + 1]}`);
}
if (!/^\];\s*$/.test(lines[endIdx - 1])) {
    throw new Error(`Unexpected block end at line 121: ${lines[endIdx - 1]}`);
}

const newBlock = [
    '// ==========================================',
    '// Default Seed Data (single source: default_database.json)',
    '// ==========================================',
    'function loadDefaultSeedData() {',
    '    const filePath = path.join(__dirname, \'default_database.json\');',
    '    const raw = fs.readFileSync(filePath, \'utf8\');',
    '    const parsed = JSON.parse(raw);',
    '',
    '    const locationsById = {};',
    '    (parsed.storage_locations || []).forEach(l => { locationsById[l.id] = l; });',
    '',
    '    const ingredients = (parsed.ingredients_v2 || []).map(i => ({',
    '        category: i.category,',
    '        name: i.name,',
    '        abbr: i.abbr || \'\',',
    '        storage: {}',
    '    }));',
    '    const ingredientsByName = {};',
    '    ingredients.forEach(i => { ingredientsByName[i.name] = i; });',
    '    (parsed.ingredient_storage || []).forEach(m => {',
    '        const ing = ingredientsByName[m.ingredient_name];',
    '        const loc = locationsById[m.storage_id];',
    '        if (ing && loc) ing.storage[loc.name] = m.shelf_days;',
    '    });',
    '',
    '    return {',
    '        categories: (parsed.categories || []).map(c => ({ name: c.name, emoji: c.emoji || \'\', sort_order: c.sort_order || 0 })),',
    '        storageLocations: (parsed.storage_locations || []).map(l => ({ name: l.name, sort_order: l.sort_order || 0, unit: l.unit || \'day\' })),',
    '        labelSizes: (parsed.label_sizes || []).map(s => ({ width: s.width, height: s.height, is_default: s.is_default ? 1 : 0 })),',
    '        ingredients',
    '    };',
    '}',
    '',
    'const MINIMAL_FALLBACK_SEED = {',
    '    categories: [{ name: "기타", emoji: "🍕", sort_order: 1 }],',
    '    storageLocations: [{ name: "메이크라인", sort_order: 1, unit: "day" }],',
    '    labelSizes: [{ width: 50, height: 30, is_default: 1 }],',
    '    ingredients: []',
    '};',
    '',
    'let SEED_DATA;',
    'try {',
    '    SEED_DATA = loadDefaultSeedData();',
    '    if (!SEED_DATA.categories.length || !SEED_DATA.ingredients.length) {',
    '        console.warn(\'default_database.json is incomplete; using minimal fallback seed data.\');',
    '        SEED_DATA = MINIMAL_FALLBACK_SEED;',
    '    }',
    '} catch (e) {',
    '    console.warn(\'Failed to load default_database.json; using minimal fallback seed data:\', e.message);',
    '    SEED_DATA = MINIMAL_FALLBACK_SEED;',
    '}',
    '',
    'const DEFAULT_CATEGORIES = SEED_DATA.categories;',
    'const DEFAULT_STORAGE_LOCATIONS = SEED_DATA.storageLocations;',
    'const DEFAULT_LABEL_SIZES = SEED_DATA.labelSizes;',
    'const DEFAULT_INGREDIENTS = SEED_DATA.ingredients;',
];

lines.splice(startIdx, endIdx - startIdx, ...newBlock);
fs.writeFileSync(serverPath, lines.join(eol), 'utf8');
console.log('server.js seed block replaced. New line count:', lines.length);
