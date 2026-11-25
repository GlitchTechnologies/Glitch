import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<bool> windowsBefore11() async {
  try {
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    final data = navigator.getProperty<JSObject?>('userAgentData'.toJS);
    if (data == null) return false;
    if (data.getProperty<JSString?>('platform'.toJS)?.toDart != 'Windows') return false;
    final values = await data
        .callMethod<JSPromise<JSObject>>('getHighEntropyValues'.toJS, <JSString>['platformVersion'.toJS].toJS)
        .toDart;
    final version = values.getProperty<JSString?>('platformVersion'.toJS)?.toDart ?? '';
    final major = int.tryParse(version.split('.').first);
    return major != null && major < 13;
  } catch (_) {
    return false;
  }
}
