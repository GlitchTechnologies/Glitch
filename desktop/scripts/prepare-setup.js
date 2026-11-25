
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const dist = path.join(root, 'dist');
const unpacked = path.join(dist, 'win-unpacked');
const { version } = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const engine = path.join(dist, `glitch-engine-${version}.exe`);

function sizeOf(dir) {
  let total = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    total += entry.isDirectory() ? sizeOf(full) : fs.statSync(full).size;
  }
  return total;
}

if (!fs.existsSync(engine)) {
  console.error(`Нет ${path.relative(root, engine)} — electron-builder не отработал.`);
  process.exit(1);
}
if (!fs.existsSync(path.join(dist, 'latest.yml'))) {
  console.error('Нет dist/latest.yml — без него самообновление не найдёт новую версию (build.publish в package.json).');
  process.exit(1);
}
fs.copyFileSync(engine, path.join(dist, 'glitch-engine.exe'));
const size = sizeOf(unpacked);
fs.writeFileSync(path.join(dist, 'payload-size.txt'), String(size), 'utf8');
console.log(`Размер программы: ${(size / 1024 / 1024).toFixed(1)} МБ`);
