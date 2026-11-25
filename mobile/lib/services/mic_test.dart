import 'mic_options.dart';

abstract class MicTest {
  Future<void> setProcessing(MicProcessing processing);

  Future<void> setOutput(String deviceId);

  void setVolume(double volume);

  double get level;

  double? get inputLevelDb;

  /// Остановить и отпустить микрофон. Повторный вызов ничего не делает.
  Future<void> stop();
}
