"""Значки программы — из ОДНОГО исходника, логотипа Glitch.

Исходник — mobile/assets/icon.png (тот же значок, что у Glitch на телефоне).

Делает в desktop/static/:
  icon.ico          — значок программы, ярлыков и трея (все размеры Windows);
  icon-unread.ico   — он же с красной точкой: есть что прочитать (трей).

Красный значок с числом на панели задач здесь НЕ делается: его рисует
программа на ходу (src/preload/app-preload.ts) — тем же красным, что DOT.

Поменялся логотип — запустить заново и положить оба файла вместе:
    python3 desktop/scripts/make_icons.py
Нужен Pillow. Сборка программы скрипт не зовёт: готовые файлы лежат в static/.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'mobile' / 'assets' / 'icon.png'
STATIC = ROOT / 'desktop' / 'static'

SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]

# Красный — как у точки непрочитанного у Discord: на тёмной и на светлой
# панели задач читается одинаково.
DOT = (242, 63, 67, 255)
# Доля стороны значка: диаметр точки и прозрачный зазор вокруг неё (точка
# «вырезана» из логотипа, а не лежит на нём пятном).
DOT_SHARE = 0.42
GAP_SHARE = 0.07
# Рисуем крупно и уменьшаем — иначе края круга на 16 точках ступеньками.
SUPERSAMPLE = 4


def with_dot(logo: Image.Image, size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    base = logo.resize((big, big), Image.LANCZOS)
    d = round(big * DOT_SHARE)
    gap = round(big * GAP_SHARE)
    x1, y1 = big, big
    x0, y0 = x1 - d, y1 - d
    # Зазор: стираем логотип кругом чуть больше точки.
    hole = Image.new('L', (big, big), 255)
    ImageDraw.Draw(hole).ellipse((x0 - gap, y0 - gap, x1 + gap, y1 + gap), fill=0)
    alpha = Image.composite(base.getchannel('A'), Image.new('L', (big, big), 0), hole)
    base.putalpha(alpha)
    ImageDraw.Draw(base).ellipse((x0, y0, x1 - 1, y1 - 1), fill=DOT)
    return base.resize((size, size), Image.LANCZOS)


def save_ico(frames: list[Image.Image], path: Path) -> None:
    largest = frames[-1]
    largest.save(path, format='ICO', sizes=[f.size for f in frames], append_images=frames[:-1])


def main() -> None:
    logo = Image.open(SOURCE).convert('RGBA')
    save_ico([logo.resize((s, s), Image.LANCZOS) for s in SIZES], STATIC / 'icon.ico')
    save_ico([with_dot(logo, s) for s in SIZES], STATIC / 'icon-unread.ico')
    print('Готово:', ', '.join(p.name for p in (STATIC / 'icon.ico', STATIC / 'icon-unread.ico')))


if __name__ == '__main__':
    main()
