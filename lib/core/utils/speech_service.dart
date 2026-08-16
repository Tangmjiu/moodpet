import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// speech_to_text 封装：初始化、启动/停止/取消、结果与状态回调。
class SpeechService {
  SpeechService();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    void Function(SpeechRecognitionResult result)? onResult,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onStatus: (status) => onStatus?.call(status),
      onError: (error) => onError?.call(error),
      debugLogging: false,
      finalTimeout: const Duration(seconds: 2),
    );
    return _initialized;
  }

  Future<void> start({
    required void Function(String finalText) onFinalText,
    void Function(SpeechRecognitionResult result)? onPartialResult,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    final ok = await initialize(
      onResult: onPartialResult,
      onStatus: onStatus,
      onError: onError,
    );
    if (!ok) {
      throw SpeechServiceException('语音识别初始化失败，请检查麦克风权限');
    }
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final text = result.recognizedWords.trim();
          if (text.isNotEmpty) onFinalText(text);
        }
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: false,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  Future<void> dispose() async {
    await cancel();
  }
}

class SpeechServiceException implements Exception {
  const SpeechServiceException(this.message);

  final String message;

  @override
  String toString() => 'SpeechServiceException: $message';
}
