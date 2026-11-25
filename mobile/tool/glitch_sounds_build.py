"""ЗВУКИ GLITCH — все звуки голоса и звонка (2026-10-15, переделаны целиком).

Собирает: вход и выход в голосе, видео включилось и выключилось (камера или
показ экрана), микрофон и звук включены/выключены, новое сообщение, «вас
переместили», рацию (нажата/отпущена — готовы, НЕ подключены: режима рации
ещё нет), мелодию входящего звонка и гудки исходящего. Запуск из
mobile/:  python3 tool/glitch_sounds_build.py  (нужны numpy и ffmpeg).
Кладёт файлы в assets/sounds/ (веб) и их копии в android/app/src/main/res/raw/
(телефон) — имена и форматы те, что ждёт код (lib/services/voice_cue.dart,
call_platform_web.dart, плагин glitch_ringtone).

Короткий синтезаторный звук
«щипок», 0,5–0,7 с; но свои, фирменные — ГЛИТЧ слышен и он главный:
  * «заикание» — нота влетает очередью коротких повторов («та-та-та-ТАНГ»);
  * «остановка плёнки» — звук на уходе сползает вниз и гаснет;
  * «цифровое зерно» — повторы с пониженной выборкой, со скруглёнными краями.
СЕРЬЁЗНОСТЬ (второй заход владельца): не «пианино» — регистр низкий (малая
и первая октавы), щипок «закрывается» фильтром (удар яркий, хвост глухой),
под главными ударами — бас-«панч» октавой ниже, лёгкая сатурация. Всё в ре
МИНОРЕ — звуки одной семьи, серьёзные.
Не делать: длинную реверберацию («банка с эхом» — забраковано), резкие
прямоугольные волны и высокие ноты («молния по банке» — забраковано),
светлые высокие «пианинные» ноты (слишком легко для игровой платформы).
"""
import numpy as np
SR = 44100
rng = np.random.default_rng(11)

def hz(note):
    names = {'C':0,'C#':1,'D':2,'D#':3,'E':4,'F':5,'F#':6,'G':7,'G#':8,'A':9,'A#':10,'B':11}
    return 440 * 2 ** ((names[note[:-1]] + 12 * (int(note[-1]) + 1) - 69) / 12)

def fade(y, a=0.0015, r=0.004):
    n = len(y); ai = max(1, int(a * SR)); ri = max(1, int(r * SR))
    e = np.ones(n)
    e[:ai] = np.sin(np.linspace(0, np.pi / 2, ai)) ** 2
    e[n - ri:] *= np.cos(np.linspace(0, np.pi / 2, ri)) ** 2
    return y * e

def pluck(f, dur=0.45, decay=0.22, bright=1.0, detune=0.0, pitch=None):
    """Синтезаторный щипок: гармоники 1/k^1.6 через «закрывающийся» фильтр —
    удар яркий, за доли секунды звук темнеет и густеет (не пианино).
    [bright] — насколько фильтр открыт в ударе. [pitch] — множитель высоты
    во времени (для «остановки плёнки»)."""
    n = int(dur * SR); t = np.arange(n) / SR
    fr = f * 2 ** (detune / 1200) * (pitch if pitch is not None else 1.0)
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(fr, (n,))) / SR
    # Срез фильтра: в ударе ~3,3 кГц, через ~70 мс — ~1,1 кГц: хвост глухой,
    # но внятный — динамик телефона баса не играет, звук живёт в середине.
    fc = 2200 * bright * np.exp(-t / 0.07) + 1100
    y = np.zeros(n)
    for k in range(1, 16):
        if f * k > 8000: break
        tau = decay / (k ** 0.5)
        lp = 1 / np.sqrt(1 + (k * f / fc) ** 4)
        y += np.sin(k * ph) / k ** 1.15 * lp * np.exp(-t / tau)
    # Атака 2,5 мс: щипок без «клаца».
    return fade(y / 1.4, 0.0025)

def punch(f, dur=0.3, decay=0.13):
    """Бас под ударом: синус октавой ниже с коротким нисходящим «подъездом»
    (как у бочки) — вес и серьёзность."""
    n = int(dur * SR); t = np.arange(n) / SR
    fr = f / 2 * 2 ** (7 * np.exp(-t / 0.018) / 12)
    ph = 2 * np.pi * np.cumsum(fr) / SR
    y = np.sin(ph) + 0.25 * np.sin(2 * ph) * np.exp(-t / 0.04)
    return fade(y * np.exp(-t / decay), 0.003, 0.02)

def crush(y, rate=7000, bits=6):
    """Цифровое зерно: пониженная выборка со сглаживанием и огрубление."""
    idx = np.arange(0, len(y), SR / rate)
    low = np.interp(idx, np.arange(len(y)), y)
    q = 2 ** (bits - 1); low = np.round(low * q) / q
    back = np.interp(np.arange(len(y)), idx, low)
    return smooth(back, 5000)

def smooth(y, cutoff):
    Y = np.fft.rfft(y, axis=0); f = np.fft.rfftfreq(y.shape[0], 1 / SR)
    g = 1 / np.sqrt(1 + (f / cutoff) ** 4)
    return np.fft.irfft(Y * (g[:, None] if y.ndim == 2 else g), n=y.shape[0], axis=0)

def hp(y, cutoff=120):
    Y = np.fft.rfft(y, axis=0); f = np.fft.rfftfreq(y.shape[0], 1 / SR)
    g = 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(Y * (g[:, None] if y.ndim == 2 else g), n=y.shape[0], axis=0)

class Mix:
    def __init__(self, dur): self.b = np.zeros((int(dur * SR), 2))
    def add(self, y, at, pan=0.0, gain=1.0):
        i = int(at * SR); l = np.cos((pan + 1) * np.pi / 4) * np.sqrt(2); r = np.sin((pan + 1) * np.pi / 4) * np.sqrt(2)
        e = min(len(self.b), i + len(y)); y = y[:e - i] * gain
        self.b[i:e, 0] += y * l; self.b[i:e, 1] += y * r
    def note(self, f, at, gain=1.0, pan=0.0, bass=0.0, **kw):
        # Две чуть разных по высоте копии влево и вправо — ширина без эха.
        self.add(pluck(f, detune=-6, **kw), at, pan=pan - 0.35, gain=gain * 0.55)
        self.add(pluck(f, detune=+6, **kw), at, pan=pan + 0.35, gain=gain * 0.55)
        # [bass] — громкость баса под ударом (посередине).
        if bass: self.add(punch(f), at, gain=gain * bass)

def stutter(m, f, start, times, gap, grain=0.026, gains=None, pans=None, crushed=True, accel=1.0):
    """Заикание: нота очередью коротких повторов (зерно grain с), промежуток
    [gap] умножается на [accel] — разгон (<1) или торможение (>1)."""
    t = start
    for i in range(times):
        g = pluck(f, dur=grain + 0.01, decay=0.05)
        g = fade(g, 0.001, 0.006)
        if crushed: g = crush(g)
        m.add(g, t, pan=(pans[i] if pans else (-0.5 if i % 2 else 0.5)),
              gain=(gains[i] if gains else 0.5))
        t += gap; gap *= accel
    return t

def tape_stop(f, dur=0.32, drop=12, start=0.06):
    """Остановка плёнки: нота держится [start] с, потом сползает на [drop]
    полутонов и гаснет."""
    n = int(dur * SR); t = np.arange(n) / SR
    k = np.clip((t - start) / (dur - start), 0, 1)
    pitch = 2 ** (-drop * k ** 1.6 / 12)
    y = pluck(f, dur=dur, decay=0.5, pitch=pitch)
    return fade(y * (1 - k) ** 1.2, 0.0015, 0.01)

def room(buf, wet=0.09, decay=0.12, length=0.35):
    """Маленькая комната — воздух, а не эхо."""
    n = int(length * SR); t = np.arange(n) / SR; out = np.zeros_like(buf)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / decay); ir = smooth(ir, 4500)
        ir[:int(0.006 * SR)] = 0; ir /= np.sqrt((ir ** 2).sum())
        m = len(buf) + n
        out[:, ch] = np.fft.irfft(np.fft.rfft(buf[:, ch], m) * np.fft.rfft(ir, m), m)[:len(buf)]
    return buf + out * wet * 3

def master(m, total, rms=0.085, peak=0.55):
    # Лёгкая сатурация — плотнее и «толще»; бас не срезаем (от 40 Гц).
    b = hp(smooth(room(m.b), 7000), 40)
    b = np.tanh(b * 1.8 / np.abs(b).max()) / np.tanh(1.8)
    a = np.abs(b).max(axis=1); env = np.convolve(a, np.ones(441) / 441, 'same')
    act = env > env.max() * 0.05
    b *= rms / np.sqrt((b[act] ** 2).mean())
    p = np.abs(b).max()
    if p > peak: b *= peak / p
    n = int(total * SR); out = np.zeros((n, 2)); out[:min(n, len(b))] = b[:n]
    f = int(0.02 * SR); out[-f:] *= np.linspace(1, 0, f)[:, None]
    return out.astype(np.float32)

A3, D4, E4, F4, A4 = (hz(x) for x in ['A3', 'D4', 'E4', 'F4', 'A4'])

# ── Вход: «та — та-та-та-ТАНГ»: ля, и тоника ре влетает разгоняющейся
# очередью, под ней бас ───────────────────────────────────────────────────────
def connected():
    m = Mix(2.0)
    m.note(A3, 0.0, gain=0.75, decay=0.12, bass=0.35)
    end = stutter(m, D4, 0.075, 3, 0.03, gains=[0.35, 0.45, 0.55], accel=0.8)
    m.note(D4, end, gain=1.0, decay=0.3, bass=0.7)
    m.note(A4, end, gain=0.22, decay=0.16, bright=0.6)     # квинта сверху — плотность
    return master(m, 2.0)

# ── Выход: «ТАНГ — та… та… та»: ля, и тоника ре сползает вниз на октаву,
# как остановленная плёнка ────────────────────────────────────────────────────
def disconnected():
    m = Mix(2.0)
    m.note(A4, 0.0, gain=0.7, decay=0.12, bass=0.35)
    m.add(tape_stop(D4, dur=0.42, drop=12, start=0.07), 0.085, pan=-0.1, gain=1.0)
    m.add(punch(D4, dur=0.35, decay=0.16), 0.085, gain=0.35)
    stutter(m, D4, 0.2, 3, 0.055, gains=[0.32, 0.22, 0.14], accel=1.35, pans=[0.6, -0.6, 0.6])
    return master(m, 2.0, rms=0.08)

# ── Видео включилось: цифровое «сканирование» вверх по ре-минору и удар ─────
def stream_on():
    m = Mix(2.0)
    for i, f in enumerate([D4, F4, A4]):
        g = crush(fade(pluck(f, dur=0.045, decay=0.035), 0.001, 0.008))
        m.add(g, i * 0.032, pan=-0.6 + 0.6 * i, gain=0.5)
    m.note(D4, 0.105, gain=0.95, decay=0.3, bass=0.75)
    m.note(A4, 0.105, gain=0.4, decay=0.22, bright=0.7)
    stutter(m, A4, 0.23, 2, 0.05, gains=[0.2, 0.12], pans=[0.7, -0.7])
    return master(m, 2.0)

# ── Видео выключилось: удар, «сканирование» вниз, плёнка останавливается ───
def stream_off():
    m = Mix(2.0)
    m.note(A4, 0.0, gain=0.35, decay=0.1, bright=0.7)
    m.note(D4, 0.0, gain=0.8, decay=0.1, bass=0.5)
    for i, f in enumerate([A4, F4, D4]):
        g = crush(fade(pluck(f, dur=0.045, decay=0.035), 0.001, 0.008))
        m.add(g, 0.1 + i * 0.034, pan=0.6 - 0.6 * i, gain=0.45)
    m.add(tape_stop(D4, dur=0.34, drop=12, start=0.05), 0.2, gain=0.75)
    return master(m, 2.0, rms=0.08)

# ── Входящий звонок: фраза в ре-миноре с заиканиями, круг 2,6 с ─────────────
def calling():
    total = 2.6
    m = Mix(total + 0.6)
    e = 0.115    # восьмая при 130 ударах в минуту
    for f, k, b in [(D4, 0, 0.5), (A3, 1, 0), (D4, 2, 0), (E4, 3, 0)]:
        m.note(f, k * e, gain=0.8, decay=0.16, bass=b)
    stutter(m, F4, 4 * e, 3, e / 3, gains=[0.35, 0.45, 0.55])
    m.note(F4, 5 * e, gain=0.95, decay=0.2, bass=0.35)
    for f, k in [(E4, 6), (D4, 7), (A3, 8)]: m.note(f, k * e, gain=0.8, decay=0.16)
    m.note(D4, 9 * e, gain=0.95, decay=0.35, bass=0.7); m.note(A4, 9 * e, gain=0.25, decay=0.2, bright=0.6)
    stutter(m, A4, 9 * e + 0.2, 3, 0.06, gains=[0.2, 0.13, 0.08], accel=1.3)
    out = master(m, total + 0.6, rms=0.1, peak=0.6)
    n = int(total * SR); loop = out[:n].copy(); loop[:len(out) - n] += out[n:]
    return loop

# ── Гудки исходящего: глухой двойной «тук» с цифровым отзвуком, круг 3 с ────
def ringback():
    total = 3.0
    m = Mix(total + 0.6)
    for at in (0.0, 0.32):
        m.note(D4, at, gain=0.7, decay=0.25, bright=0.5, bass=0.25)
        m.note(A3, at, gain=0.5, decay=0.3, bright=0.5)
    stutter(m, A3, 0.62, 2, 0.07, gains=[0.16, 0.08], pans=[0.6, -0.6])
    out = master(m, total + 0.6, rms=0.06, peak=0.45)
    n = int(total * SR); loop = out[:n].copy(); loop[:len(out) - n] += out[n:]
    return loop

# ── Микрофон и звук: короче остальных — нажимают часто, не должны утомлять ─

def _grain(f, at, m, pan, gain):
    m.add(crush(fade(pluck(f, dur=0.045, decay=0.035), 0.001, 0.008)), at, pan=pan, gain=gain)

# Микрофон включён: ре → фа (малая терция вверх) и цифровое зерно-отголосок.
def mic_on():
    m = Mix(2.0)
    m.note(D4, 0.0, gain=0.65, decay=0.06)
    m.note(F4, 0.06, gain=0.9, decay=0.14, bass=0.35)
    _grain(F4, 0.15, m, 0.6, 0.22)
    return master(m, 2.0, rms=0.07)

# Микрофон выключен: фа → ре, темнее.
def mic_off():
    m = Mix(2.0)
    m.note(F4, 0.0, gain=0.65, decay=0.06, bright=0.7)
    m.note(D4, 0.06, gain=0.9, decay=0.14, bass=0.35, bright=0.6)
    _grain(D4, 0.15, m, -0.6, 0.2)
    return master(m, 2.0, rms=0.07)

# Звук выключен: тяжёлый удар, глухо сползает вниз — «закрылось».
def deafen():
    m = Mix(2.0)
    m.note(A4, 0.0, gain=0.35, decay=0.06, bright=0.5)
    m.add(tape_stop(D4, dur=0.3, drop=7, start=0.04), 0.0, gain=0.95)
    m.add(punch(D4, dur=0.3, decay=0.12), 0.0, gain=0.55)
    _grain(D4, 0.17, m, -0.6, 0.18)
    return master(m, 2.0, rms=0.075)

# Звук включён: низкий панч, «сканирование» вверх и удар — «открылось».
def undeafen():
    m = Mix(2.0)
    m.add(punch(D4, dur=0.25, decay=0.1), 0.0, gain=0.45)
    _grain(D4, 0.0, m, -0.5, 0.4)
    _grain(F4, 0.035, m, 0.0, 0.42)
    m.note(A4, 0.07, gain=0.75, decay=0.16, bright=0.8)
    m.note(D4, 0.07, gain=0.6, decay=0.18, bass=0.3)
    return master(m, 2.0, rms=0.075)

def tape_start(f, dur=0.4, rise=12, spin=0.08, decay=0.28):
    """Запуск плёнки (обратное остановке): нота разгоняется снизу на [rise]
    полутонов до своей высоты за [spin] с."""
    n = int(dur * SR); t = np.arange(n) / SR
    k = np.clip(t / spin, 0, 1)
    pitch = 2 ** (-rise * (1 - k) ** 2 / 12)
    return pluck(f, dur=dur, decay=decay, pitch=pitch, bright=0.8)

# Новое сообщение: «да-ДИНЬ» — ре и звонче квинта ля, отголосок.
def message():
    m = Mix(2.0)
    m.note(D4, 0.0, gain=0.6, decay=0.07, bright=0.7)
    m.note(A4, 0.075, gain=0.95, decay=0.2, bright=1.0, bass=0.25)
    _grain(A4, 0.2, m, 0.6, 0.2)
    _grain(A4, 0.26, m, -0.6, 0.1)
    return master(m, 2.0, rms=0.075)

# Вас переместили: зёрна проносятся слева направо, нота «запускается» снизу.
def moved():
    m = Mix(2.0)
    for i, f in enumerate([A3, D4, F4, A4, D4]):
        _grain(f, i * 0.028, m, -0.8 + 0.4 * i, 0.32 + 0.04 * i)
    for side in (-0.3, 0.3):
        m.add(tape_start(D4), 0.1, pan=side, gain=0.55)
    m.add(punch(D4, dur=0.3, decay=0.14), 0.18, gain=0.5)
    _grain(D4, 0.36, m, 0.7, 0.16)
    return master(m, 2.0, rms=0.078)

# Рация нажата / отпущена: совсем короткие тихие «щипки» вверх и вниз.
def ptt_on():
    m = Mix(2.0)
    m.note(D4, 0.0, gain=0.7, decay=0.05, bright=0.6)
    _grain(F4, 0.035, m, 0.4, 0.25)
    return master(m, 2.0, rms=0.055)

def ptt_off():
    m = Mix(2.0)
    m.note(F4, 0.0, gain=0.6, decay=0.04, bright=0.5)
    _grain(D4, 0.035, m, -0.4, 0.22)
    return master(m, 2.0, rms=0.05)

SOUNDS = {'connected': connected, 'disconnected': disconnected, 'stream_on': stream_on,
          'stream_off': stream_off, 'calling': calling, 'ringback': ringback,
          'mic_on': mic_on, 'mic_off': mic_off, 'deafen': deafen, 'undeafen': undeafen,
          'message': message, 'moved': moved, 'ptt_on': ptt_on, 'ptt_off': ptt_off}
# Файл в проекте: (веб, копия на телефоне, параметры кодирования ffmpeg).
FILES = {
    'connected': ('glitch_voice_connected.mp3', 'voice_connected.mp3', ['-b:a', '192k']),
    'disconnected': ('glitch_voice_disconnected.wav', 'voice_disconnected.wav', ['-c:a', 'pcm_s16le']),
    'stream_on': ('glitch_voice_stream_on.mp3', 'voice_stream_on.mp3', ['-b:a', '192k']),
    'stream_off': ('glitch_voice_stream_off.mp3', 'voice_stream_off.mp3', ['-b:a', '192k']),
    'calling': ('glitch_voice_calling.mp3', 'call_ringtone.mp3', ['-b:a', '192k']),
    'ringback': ('ringback.ogg', 'call_ringback.ogg', ['-c:a', 'libvorbis', '-q:a', '5']),
    'mic_on': ('glitch_voice_mic_on.mp3', 'voice_mic_on.mp3', ['-b:a', '192k']),
    'mic_off': ('glitch_voice_mic_off.mp3', 'voice_mic_off.mp3', ['-b:a', '192k']),
    'deafen': ('glitch_voice_deafen.mp3', 'voice_deafen.mp3', ['-b:a', '192k']),
    'undeafen': ('glitch_voice_undeafen.mp3', 'voice_undeafen.mp3', ['-b:a', '192k']),
    'message': ('glitch_message.mp3', 'glitch_message.mp3', ['-b:a', '192k']),
    'moved': ('glitch_voice_moved.mp3', 'voice_moved.mp3', ['-b:a', '192k']),
    'ptt_on': ('glitch_voice_ptt_on.mp3', 'voice_ptt_on.mp3', ['-b:a', '192k']),
    'ptt_off': ('glitch_voice_ptt_off.mp3', 'voice_ptt_off.mp3', ['-b:a', '192k']),
}

if __name__ == '__main__':
    import os, shutil, subprocess, tempfile
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    web = os.path.join(root, 'assets', 'sounds')
    raw = os.path.join(root, 'android', 'app', 'src', 'main', 'res', 'raw')
    with tempfile.TemporaryDirectory() as tmp:
        for name, make in SOUNDS.items():
            pcm = os.path.join(tmp, name + '.f32')
            make().tofile(pcm)
            web_name, raw_name, codec = FILES[name]
            dst = os.path.join(web, web_name)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2',
                            '-i', pcm, *codec, dst], check=True)
            shutil.copyfile(dst, os.path.join(raw, raw_name))
            print(name, '->', web_name, '+', raw_name)
