
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const config = fs.readFileSync(path.join(root, 'src', 'main', 'config.ts'), 'utf8');
const match = config.match(/export const APP_ID = '([^']+)';/);

if (!match || match[1] !== pkg.build.appId) {
  console.error(
    `appId расходится: package.json — ${pkg.build.appId}, src/main/config.ts — ${match ? match[1] : 'не найден'}`,
  );
  process.exit(1);
}
