
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const mobile = path.join(root, '..', 'mobile', 'lib');
const problems = [];

function read(file) {
  if (!fs.existsSync(file)) {
    problems.push(`нет файла ${file} (папка mobile должна лежать рядом с desktop)`);
    return '';
  }
  return fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
}

function find(text, regex, what) {
  const match = text.match(regex);
  if (!match) problems.push(`не нашёл ${what} — проверку надо поправить вслед за кодом`);
  return match ? match[1] : null;
}

function same(where, got, want) {
  if (got == null || want == null) return;
  if (String(got).toUpperCase() !== String(want).toUpperCase()) {
    problems.push(`${where}: ${got}, а в приложении ${want}`);
  }
}

function rgb(argbOrHex) {
  return argbOrHex.slice(-6).toUpperCase();
}


const palette = read(path.join(mobile, 'theme', 'glitch_palette.dart'));
const darkBlock = (palette.split('factory GlitchPalette.dark')[1] || '').split('factory GlitchPalette.light')[0];
const app = {};
for (const m of darkBlock.matchAll(/(\w+): const Color\(0x([0-9A-Fa-f]{8})\)/g)) app[m[1]] = rgb(m[2]);
for (const name of ['bg', 'bgCard', 'bgInput', 'border', 'textPrimary', 'textSecond', 'textHint']) {
  if (!app[name]) problems.push(`не нашёл цвет ${name} в GlitchPalette.dark`);
}
const accent = find(read(path.join(mobile, 'providers', 'theme_provider.dart')),
  /static const defaultAccent\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)/, 'акцент по умолчанию (theme_provider.dart)');
if (accent) app.accent = rgb(accent);
const error = find(read(path.join(mobile, 'theme', 'app_theme.dart')),
  /static const error\s*=\s*Color\(0x([0-9A-Fa-f]{8})\)/, 'цвет ошибки (app_theme.dart)');
if (error) app.error = rgb(error);

const button = read(path.join(mobile, 'widgets', 'glitch_action_button.dart'));
const softBlock = (button.split('if (soft) {')[1] || '').split('\n    return SizedBox(')[0];
const soft = {
  fill: find(button, /_softFill = ([\d.]+);/, 'прозрачность мягкой кнопки'),
  fillActive: find(button, /_softFillActive = ([\d.]+);/, 'прозрачность мягкой кнопки под мышью'),
  height: find(softBlock, /height: compact \? (\d+)/, 'высоту мягкой кнопки'),
  radius: find(softBlock, /circular\(compact \? (\d+)/, 'скругление мягкой кнопки'),
  padding: find(button, /final padding = compact \? const EdgeInsets\.symmetric\(horizontal: (\d+)\)/, 'отступы маленькой кнопки'),
  fontSize: find(softBlock, /fontSize: compact \? ([\d.]+)/, 'размер текста мягкой кнопки'),
};
if (!/final ink = (?:softInk \?\? )?GlitchColors\.textPrimary;/.test(softBlock)) problems.push('у мягкой кнопки сменился цвет текста/фона (ink) — поправь установщик и проверку');
if (!/FontWeight\.w600/.test(softBlock)) problems.push('у мягкой кнопки сменилась толщина текста — поправь установщик и проверку');

function alpha(opacity) {
  return Math.round(Number(opacity) * 255).toString(16).padStart(2, '0').toUpperCase();
}


const config = read(path.join(root, 'src', 'main', 'config.ts'));
const darkTs = find(config, /export const DARK = \{([\s\S]*?)\};/, 'DARK в config.ts') || '';
const configMap = { bg: 'bg', card: 'bgCard', border: 'border', text: 'textPrimary', textSecond: 'textSecond', textHint: 'textHint', accent: 'accent' };
for (const [key, appName] of Object.entries(configMap)) {
  const value = find(darkTs, new RegExp(`\\b${key}: '(#[0-9A-Fa-f]{6})'`), `цвет ${key} в DARK (config.ts)`);
  if (value) same(`config.ts DARK.${key}`, rgb(value), app[appName]);
}


const setup = read(path.join(root, 'installer', 'SetupWindow.cs'));
const installerMap = { Card: 'bgCard', Border: 'border', Input: 'bgInput', Text: 'textPrimary', TextSecond: 'textSecond', Accent: 'accent', Error: 'error' };
for (const [key, appName] of Object.entries(installerMap)) {
  const value = find(setup, new RegExp(`Brush ${key} = Hex\\("(#[0-9A-Fa-f]{6})"\\)`), `цвет ${key} в Palette (SetupWindow.cs)`);
  if (value) same(`SetupWindow.cs Palette.${key}`, rgb(value), app[appName]);
}
const fill = find(setup, /Brush SoftFill = Hex\("#([0-9A-Fa-f]{8})"\)/, 'SoftFill в Palette (SetupWindow.cs)');
const fillActive = find(setup, /Brush SoftFillActive = Hex\("#([0-9A-Fa-f]{8})"\)/, 'SoftFillActive в Palette (SetupWindow.cs)');
if (soft.fill && app.textPrimary) same('SetupWindow.cs Palette.SoftFill', fill, alpha(soft.fill) + app.textPrimary);
if (soft.fillActive && app.textPrimary) same('SetupWindow.cs Palette.SoftFillActive', fillActive, alpha(soft.fillActive) + app.textPrimary);

const softCs = (setup.split('private static Border MakeSoftButton(')[1] || '').split('\n        }\n')[0];
if (!softCs) problems.push('не нашёл MakeSoftButton в SetupWindow.cs — проверку надо поправить вслед за кодом');
same('мягкая кнопка установщика: высота', find(softCs, /button\.Height = (\d+);/, 'высоту MakeSoftButton'), soft.height);
same('мягкая кнопка установщика: скругление', find(softCs, /new CornerRadius\((\d+)\)/, 'скругление MakeSoftButton'), soft.radius);
same('мягкая кнопка установщика: отступы', find(softCs, /new Thickness\((\d+), 0, \1, 0\)/, 'отступы MakeSoftButton'), soft.padding);
same('мягкая кнопка установщика: размер текста', find(softCs, /FontSize = ([\d.]+),/, 'размер текста MakeSoftButton'), soft.fontSize);
if (softCs && !/Foreground = Palette\.Text,/.test(softCs)) problems.push('мягкая кнопка установщика: текст должен быть цвета Palette.Text');
if (softCs && !/FontWeight = FontWeights\.SemiBold,/.test(softCs)) problems.push('мягкая кнопка установщика: текст должен быть SemiBold (w600)');


const splashW = find(config, /SPLASH_SIZE = \{ width: (\d+),/, 'ширину SPLASH_SIZE (config.ts)');
const splashH = find(config, /SPLASH_SIZE = \{ width: \d+, height: (\d+) \}/, 'высоту SPLASH_SIZE (config.ts)');
const setupW = find(setup, /\n\s*Width = (\d+);/, 'ширину окна установщика (SetupWindow.cs)');
const setupH = find(setup, /\n\s*Height = (\d+);/, 'высоту окна установщика (SetupWindow.cs)');
if (splashW && setupW && (splashW !== setupW || splashH !== setupH)) {
  problems.push(`заставка ${splashW}×${splashH}, а окно установщика ${setupW}×${setupH} — должны совпадать`);
}

if (problems.length) {
  console.error('Вид программы или установщика разошёлся с приложением (mobile/):');
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
