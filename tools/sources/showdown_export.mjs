// Exports Pokémon Showdown's data modules to plain JSON for the game.
// Usage: node showdown_export.mjs <package/dist/data folder> <output folder>
// Function-valued fields (move and item callbacks) are dropped by JSON.stringify.
import {createRequire} from 'node:module';
import {copyFileSync, mkdirSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';

const [dataDir, outDir] = process.argv.slice(2).map(p => resolve(p));
if (!dataDir || !outDir) {
  console.error('usage: node showdown_export.mjs <data folder> <output folder>');
  process.exit(2);
}

const require = createRequire(import.meta.url);
const tables = {pokedex: 'Pokedex', moves: 'Moves', learnsets: 'Learnsets', typechart: 'TypeChart'};

mkdirSync(outDir, {recursive: true});
for (const [file, exportName] of Object.entries(tables)) {
  const table = require(join(dataDir, `${file}.js`))[exportName];
  if (!table || typeof table !== 'object') {
    console.error(`${file}.js has no "${exportName}" export; the Showdown data layout may have changed`);
    process.exit(1);
  }
  writeFileSync(join(outDir, `${file}.json`), JSON.stringify(table));
  console.log(`${file}.json: ${Object.keys(table).length} entries`);
}
copyFileSync(join(dataDir, 'random-battles/gen9/sets.json'), join(outDir, 'gen9-random-sets.json'));
