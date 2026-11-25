/// ЦЕНА ДЛЯ ЧЕЛОВЕКА — одна запись на всё приложение (магазин, 2026-10-24).
/// Сервер присылает копейки целым числом (`app/core/shop.py`), здесь — «499 ₽»,
/// «1 299 ₽», «199,90 ₽». Пока валюта одна — рубли; знак после числа, как
/// принято в рублях на всех языках приложения.
String formatPrice(int kopecks) {
  final rub = kopecks ~/ 100;
  final kop = kopecks % 100;
  final digits = rub.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(digits[i]);
  }
  final whole = grouped.toString();
  return kop == 0 ? '$whole ₽' : '$whole,${kop.toString().padLeft(2, '0')} ₽';
}
