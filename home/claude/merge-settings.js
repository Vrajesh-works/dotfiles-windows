// Merge the repo's managed Claude Code settings into the live ~/.claude/settings.json.
// Only the top-level keys present in the managed file are written; everything else
// Claude Code stores there (plugins, permissions, model, ...) is left untouched.
// Usage: node merge-settings.js <live.json> <managed.json> <dotfilesDir> <stamp> [--dry-run]
const fs = require('fs');

const [livePath, managedPath, dotfilesDir, stamp, flag] = process.argv.slice(2);
const dryRun = flag === '--dry-run';
const dotfiles = dotfilesDir.replace(/\\/g, '/');

const managed = JSON.parse(fs.readFileSync(managedPath, 'utf8').replace(/__DOTFILES__/g, dotfiles));
const exists = fs.existsSync(livePath);
const liveText = exists ? fs.readFileSync(livePath, 'utf8') : '{}';
const live = JSON.parse(liveText.replace(/^﻿/, ''));

const changed = Object.keys(managed).filter(
  (k) => JSON.stringify(live[k]) !== JSON.stringify(managed[k]),
);
if (changed.length === 0) {
  console.log(`    ok      ${livePath}`);
  process.exit(0);
}
if (dryRun) {
  console.log(`    [dry-run] would set ${changed.join(', ')} in ${livePath}`);
  process.exit(0);
}
if (exists) {
  fs.copyFileSync(livePath, `${livePath}.bak-${stamp}`);
  console.log(`    backed up ${livePath} -> ${livePath}.bak-${stamp}`);
}
fs.writeFileSync(livePath, JSON.stringify({ ...live, ...managed }, null, 2) + '\n');
console.log(`    set     ${changed.join(', ')} in ${livePath}`);
