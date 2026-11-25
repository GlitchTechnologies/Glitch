
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const dist = path.join(root, 'dist');
const site = path.join(dist, 'site');
const { version } = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const unpackedCapture = path.join(dist, 'win-unpacked', 'resources', 'screen-capture', 'glitch_screen_capture.node');
const capture = fs.statSync(unpackedCapture, { throwIfNoEntry: false });
if (!capture?.isFile() || capture.size === 0) {
  throw new Error('В собранной программе отсутствует модуль захвата DXGI и WASAPI.');
}
const engine = `glitch-engine-${version}.exe`;
const optional = new Set([`${engine}.blockmap`]);
const files = ['GlitchSetup.exe', engine, `${engine}.blockmap`, 'latest.yml'];

const latest = fs.readFileSync(path.join(dist, 'latest.yml'), 'utf8');
if (!new RegExp(`^version: ${version.replace(/\./g, '\\.')}$`, 'm').test(latest) || !latest.includes(engine)) {
  console.error(`dist/latest.yml не про версию ${version} (${engine}).`);
  process.exit(1);
}

fs.rmSync(site, { recursive: true, force: true });
fs.mkdirSync(site);
for (const name of files) {
  const from = path.join(dist, name);
  if (!fs.existsSync(from)) {
    if (optional.has(name)) continue;
    console.error(`Нет dist/${name}.`);
    process.exit(1);
  }
  fs.copyFileSync(from, path.join(site, name));
}
console.log(`Файлы для сайта (версия ${version}): dist/site/ — ${fs.readdirSync(site).join(', ')}`);
