// One-off utility: enrich default_database.json with storage unit fields and
// the standard label size presets, then sync the Flutter client asset copy.
// Usage: node scripts/update-default-json.js
const fs = require('fs');
const path = require('path');

const rootJsonPath = path.join(__dirname, '..', 'default_database.json');
const clientJsonPath = path.join(__dirname, '..', 'client_flutter', 'assets', 'json', 'default_database.json');

const data = JSON.parse(fs.readFileSync(rootJsonPath, 'utf8'));

// 1) storage_locations: add unit (hour-based for ids 4=소스보틀, 5=분할; day otherwise)
const HOUR_BASED_IDS = new Set([4, 5]);
data.storage_locations = (data.storage_locations || []).map((loc) => ({
    ...loc,
    unit: loc.unit || (HOUR_BASED_IDS.has(loc.id) ? 'hour' : 'day'),
}));

// 2) label_sizes: keep existing entries, ensure standard presets exist
const STANDARD_PRESETS = [
    { width: 50, height: 30 },
    { width: 60, height: 40 },
    { width: 70, height: 40 },
    { width: 80, height: 50 },
    { width: 100, height: 60 },
    { width: 100, height: 70 },
];
const sizes = Array.isArray(data.label_sizes) ? [...data.label_sizes] : [];
let nextId = sizes.reduce((max, s) => Math.max(max, s.id || 0), 0) + 1;
for (const preset of STANDARD_PRESETS) {
    const exists = sizes.some((s) => s.width === preset.width && s.height === preset.height);
    if (!exists) {
        sizes.push({ id: nextId, width: preset.width, height: preset.height, is_default: 1 });
        nextId += 1;
    }
}
data.label_sizes = sizes;

fs.writeFileSync(rootJsonPath, JSON.stringify(data, null, 4) + '\n', 'utf8');
console.log('Updated', rootJsonPath);
console.log('  storage_locations:', data.storage_locations.map((l) => `${l.name}(${l.unit})`).join(', '));
console.log('  label_sizes:', data.label_sizes.map((s) => `${s.width}x${s.height}`).join(', '));

// 3) Keep Flutter client offline default asset in sync with the server copy
fs.writeFileSync(clientJsonPath, JSON.stringify(data, null, 4) + '\n', 'utf8');
console.log('Synced client asset:', clientJsonPath);
