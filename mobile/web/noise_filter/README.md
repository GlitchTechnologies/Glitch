# Шумоподавление в браузере — файлы фильтра

Кнопка «Шумоподавление» в веб-версии: нейросеть DeepFilterNet3 работает прямо
в браузере. Её подключает `lib/services/noise_filter_web.dart`.

Файлы лежат на НАШЕМ сайте, а не на чужом CDN, по двум причинам:

- страница веб-версии изолирована заголовками COOP/COEP (без них Flutter Web
  работает в один поток), и браузер не даст загрузить файлы с чужого домена;
- файл `deepfilter.js` и WebAssembly связаны по именам внутренних функций. CDN
  автора отдаёт `df_bg.wasm` по адресу без версии, и стоит автору его обновить,
  наша копия скрипта перестала бы с ним работать.

| Файл | Откуда | sha256 |
|---|---|---|
| `deepfilter.js` | npm `deepfilternet3-noise-filter@1.3.0`, `dist/index.esm.js` без изменений | `62d80bdbbcce1285ae25e02d9642d8ae9d9fb652c5e5c8bbe69291f09d6816d9` |
| `v3/pkg/df_bg.wasm` | `https://cdn.mezon.ai/AI/models/datas/noise_suppression/deepfilternet3/v3/pkg/df_bg.wasm`, скачан 2026-10-07 | `440b5d12b6ea7d95008736f844221d7874ee15de5cb10d3015002470fdba0432` |
| `v3/models/DeepFilterNet3_onnx.tar.gz` | оттуда же, `v3/models/` | `c94d91f70911001c946e0fabb4aa9adc37045f45a03b56008cb0c8244cb63616` |

Пути `v3/pkg/…` и `v3/models/…` задаёт сам `deepfilter.js`: он дописывает их
к адресу папки. Переименовывать нельзя.

Лицензия — MIT или Apache 2.0 на выбор (`LICENSE-MIT`, `LICENSE-APACHE`), как у
DeepFilterNet. Исходники обёртки — github.com/mezonai/mezon-noise-suppression.

**Обновлять только тремя файлами разом.** Проверка совместимости: имена
`__wbg_…_<хэш>` в `deepfilter.js` (внутри строки `workletCode`) должны совпадать
с теми, что в `df_bg.wasm`:

```
strings v3/pkg/df_bg.wasm | grep -o '__wbg_[a-zA-Z_]*_[0-9a-f]\{16\}' | sort -u
```
