/// Зеркало `PREVIEW_WIDTH`/`PREVIEW_HEIGHT` в app/core/stream_preview.py:
/// приложение уменьшает кадр до отправки, чтобы не гонять по сети целый
/// экран раз в минуту, а сервер всё равно вписывает присланное в этот размер
/// сам и присланному не доверяет. Разъедутся числа — сломается только лишний
/// трафик, не показ.
library;

const int kStreamPreviewWidth = 640;
const int kStreamPreviewHeight = 360;

const double kStreamPreviewQuality = 0.75;
