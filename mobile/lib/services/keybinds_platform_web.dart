import 'dart:js_interop';

import 'package:web/web.dart' as web;


bool _blockMouseNavigation = false;
bool _mouseBound = false;

/// Боковые кнопки мыши («назад» / «вперёд») назначены горячей клавише —
/// гасить их переход по истории страницы: иначе нажатие рации уводило бы
/// веб-версию на прошлое место (адрес и есть история, web_address.dart).
/// Браузер переходит по отпусканию кнопки, гасится оно же.
void setMouseNavigationBlocked(bool block) {
  _blockMouseNavigation = block;
  if (_mouseBound) return;
  _mouseBound = true;
  web.window.addEventListener(
    'mouseup',
    ((web.MouseEvent e) {
      if (_blockMouseNavigation && (e.button == 3 || e.button == 4)) e.preventDefault();
    }).toJS,
    true.toJS,
  );
}

bool _focusBound = false;

void watchWindowFocusLoss(void Function() onLost) {
  if (_focusBound) return;
  _focusBound = true;
  web.window.addEventListener('blur', ((web.Event _) => onLost()).toJS);
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.visibilityState == 'hidden') onLost();
    }).toJS,
  );
}
