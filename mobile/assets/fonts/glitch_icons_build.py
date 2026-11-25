# ИСХОДНИК ШРИФТА ЗНАЧКОВ GLITCH (assets/fonts/GlitchIcons.ttf) — в сборку не
# входит, лежит рядом, как вариативные Inter Tight. Свои значки — те, которых
# нет в Material Icons (2026-10-15: монитор «показать экран» / «остановить
# показ»). Стиль — Material Rounded: заливка, вырез, сетка 24×24. Новый
# значок — дописать сюда и в lib/theme/glitch_icons.dart, пересобрать:
#   python3 assets/fonts/glitch_icons_build.py   (нужен fontTools)
# Сетка 24×24 (как у Material Icons), 40 единиц шрифта на клетку.
import math
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen

U = 40
EM = 24 * U
K = 0.5523  # круг кубическими кривыми

def P(x, y):  # из сетки (y вниз) в единицы шрифта (y вверх)
    return (round(x * U), round((24 - y) * U))

def rrect(pen, x0, y0, x1, y1, r, hole=False):
    # По часовой (в сетке y вниз это против часовой в шрифте) — тело; дыра — наоборот.
    pts = []
    k = r * K
    seg = [
        ('M', (x0 + r, y0)),
        ('L', (x1 - r, y0)), ('C', (x1 - r + k, y0), (x1, y0 + r - k), (x1, y0 + r)),
        ('L', (x1, y1 - r)), ('C', (x1, y1 - r + k), (x1 - r + k, y1), (x1 - r, y1)),
        ('L', (x0 + r, y1)), ('C', (x0 + r - k, y1), (x0, y1 - r + k), (x0, y1 - r)),
        ('L', (x0, y0 + r)), ('C', (x0, y0 + r - k), (x0 + r - k, y0), (x0 + r, y0)),
    ]
    rec = RecordingPen()
    for s in seg:
        if s[0] == 'M': rec.moveTo(P(*s[1]))
        elif s[0] == 'L': rec.lineTo(P(*s[1]))
        else: rec.curveTo(P(*s[1]), P(*s[2]), P(*s[3]))
    rec.closePath()
    if hole:
        from fontTools.pens.reverseContourPen import ReverseContourPen
        rec.replay(ReverseContourPen(pen))
    else:
        rec.replay(pen)

def poly(pen, pts, hole=False):
    pts = [P(*p) for p in pts]
    if hole: pts = pts[::-1]
    pen.moveTo(pts[0])
    for p in pts[1:]: pen.lineTo(p)
    pen.closePath()

def monitor(pen):
    rrect(pen, 2, 3, 22, 17, 2.5)          # экран
    rrect(pen, 10.5, 16, 13.5, 19.5, 0.01) # ножка (заходит под экран)
    rrect(pen, 7, 19, 17, 21.2, 1.1)       # подставка

def arrow(pen):
    # Стрелка вверх, вырез в экране: наконечник шириной 8, древко 2.5.
    cx = 12
    poly(pen, [(cx, 5.6), (cx + 4, 9.6), (cx + 1.25, 9.6), (cx + 1.25, 14.2), (cx - 1.25, 14.2),
               (cx - 1.25, 9.6), (cx - 4, 9.6)], hole=True)

def cross(pen):
    # Крестик, вырез в экране: две перекладины толщиной 2.5, размах 3.6 от центра.
    cx, cy, a, t = 12, 10, 3.6, 1.25
    d = t / math.sqrt(2)
    s = t * math.sqrt(2)
    pts = [(cx, cy - s), (cx + a - d, cy - a - d), (cx + a + d, cy - a + d), (cx + s, cy),
           (cx + a + d, cy + a - d), (cx + a - d, cy + a + d), (cx, cy + s),
           (cx - a + d, cy + a + d), (cx - a - d, cy + a - d), (cx - s, cy),
           (cx - a - d, cy - a + d), (cx - a + d, cy - a - d)]
    poly(pen, pts, hole=True)

def glyph(draw):
    tt = TTGlyphPen(None)
    pen = Cu2QuPen(tt, max_err=1, reverse_direction=False)
    draw(pen)
    return tt.glyph()

glyphs = {
    '.notdef': TTGlyphPen(None).glyph(),
    'screenShare': glyph(lambda p: (monitor(p), arrow(p))),
    'screenShareStop': glyph(lambda p: (monitor(p), cross(p))),
}
cmap = {0xE000: 'screenShare', 0xE001: 'screenShareStop'}
fb = FontBuilder(EM, isTTF=True)
fb.setupGlyphOrder(list(glyphs))
fb.setupCharacterMap(cmap)
fb.setupGlyf(glyphs)
# Отступ слева (lsb) в таблице ширин ОБЯЗАН совпадать с левым краем рисунка
# (xMin), иначе значки будут смещены. Берём отступ из самого рисунка.
glyf = fb.font['glyf']
for n in glyphs:
    glyf[n].recalcBounds(glyf)
fb.setupHorizontalMetrics({n: (EM, getattr(glyf[n], 'xMin', 0)) for n in glyphs})
fb.setupHorizontalHeader(ascent=EM, descent=0)
fb.setupOS2(sTypoAscender=EM, sTypoDescender=0, usWinAscent=EM, usWinDescent=0, sTypoLineGap=0)
fb.setupNameTable({'familyName': 'GlitchIcons', 'styleName': 'Regular'})
fb.setupPost()
fb.save(__file__.replace('glitch_icons_build.py', 'GlitchIcons.ttf'))
print('ok')
