"""СЛОВАРЬ ПОИСКА ЭМОДЗИ — названия и ключевые слова каждого эмодзи нашего
набора на языках приложения (2026-10-16, поиск во вкладке «Эмодзи» окна
выбора, как у Discord).

Источник — официальный справочник Unicode CLDR (annotations + annotationsDerived:
у каждого эмодзи короткое название и ключевые слова на всех языках). Версия
закреплена ([CLDR_VERSION]) — словарь не меняется сам от того, что Unicode
выпустил новую.

Запуск из mobile/:  python3 tool/emoji_keywords_build.py
Читает набор эмодзи из lib/core/emoji_data.dart (пересобирать после правки
набора) и пишет lib/core/emoji_keywords.dart. Руками тот файл не править.

Данные Unicode распространяются по лицензии Unicode License v3 — она требует
сохранять уведомление; оно записывается в шапку собранного файла.
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

CLDR_VERSION = '46.0.0'
LANGS = ['ru', 'en', 'uk', 'zh']  # языки приложения (lib/l10n/app_*.arb)
BASE = f'https://raw.githubusercontent.com/unicode-org/cldr-json/{CLDR_VERSION}/cldr-json'
SOURCES = [
    ('cldr-annotations-full/annotations', 'annotations'),
    ('cldr-annotations-derived-full/annotationsDerived', 'annotationsDerived'),
]

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / 'lib' / 'core' / 'emoji_data.dart'
OUT = ROOT / 'lib' / 'core' / 'emoji_keywords.dart'

VS16 = '️'  # «показать цветным»: в CLDR часть ключей без него


def our_emojis():
    src = DATA.read_text(encoding='utf-8')
    body = src[src.index('const List<EmojiCategory> emojiCategories'):]
    seen, out = set(), []
    for e in re.findall(r"'([^']+)'", body):
        if e not in seen:
            seen.add(e)
            out.append(e)
    return out


def load_lang(lang):
    table = {}
    for path, key in SOURCES:
        url = f'{BASE}/{path}/{lang}/annotations.json'
        with urllib.request.urlopen(url, timeout=60) as r:
            data = json.load(r)
        for emoji, v in data[key]['annotations'].items():
            table[emoji] = v
            table.setdefault(emoji.replace(VS16, ''), v)
    return table


def words_for(entry):
    """Название первым, дальше ключевые слова без повторов."""
    name = (entry.get('tts') or [''])[0].strip()
    words = [name] if name else []
    for w in entry.get('default') or []:
        w = w.strip()
        if w and w not in words:
            words.append(w)
    return words


def dart_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def main():
    emojis = our_emojis()
    parts = []
    for lang in LANGS:
        table = load_lang(lang)
        lines, missing = [], []
        for e in emojis:
            entry = table.get(e) or table.get(e.replace(VS16, ''))
            if not entry:
                missing.append(e)
                continue
            # «|» в словах CLDR не встречается — им и разделяем.
            lines.append(f'  {dart_str(e)}: {dart_str("|".join(words_for(entry)))},')
        if missing:
            print(f'{lang}: нет в CLDR — {" ".join(missing)}', file=sys.stderr)
        parts.append(f'const Map<String, String> _{lang} = {{\n' + '\n'.join(lines) + '\n};\n')
    header = f'''// СОБРАНО tool/emoji_keywords_build.py — руками не править.
//
// Названия и ключевые слова эмодзи набора core/emoji_data.dart на языках
// приложения: эмодзи → «название|слово|слово…». Ищет по ним
// core/emoji_search.dart.
//
// Источник — Unicode CLDR {CLDR_VERSION} (annotations, annotationsDerived).
// Copyright © 1991-2024 Unicode, Inc. Распространяется по лицензии
// Unicode License v3: https://www.unicode.org/license.txt

/// Словарь языка [lang] (код языка приложения); null — такого нет.
Map<String, String>? emojiKeywordsFor(String lang) => switch (lang) {{
{"".join(f"      '{l}' => _{l},{chr(10)}" for l in LANGS)}      _ => null,
    }};

'''
    OUT.write_text(header + '\n'.join(parts), encoding='utf-8')
    print(f'{OUT.relative_to(ROOT)}: {len(emojis)} эмодзи, {OUT.stat().st_size // 1024} КБ')


if __name__ == '__main__':
    main()
