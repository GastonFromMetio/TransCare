import 'package:flutter/foundation.dart';

/// A simple contract for turning an audio file into raw text.
abstract class SpeechTranscriber {
  Future<String> transcribeFile(String audioFilePath);
}

/// Minimal Whisper adapter that expects a function that runs the model.
/// You can wire this to `whisper_dart`, `flutter_whisper` or a method channel
/// binding to `whisper.cpp`.
class WhisperTranscriber implements SpeechTranscriber {
  const WhisperTranscriber({
    required Future<String> Function(String audioFilePath) runWhisper,
    this.languageCode = 'fr',
    this.shouldTranslateToEnglish = false,
  }) : _runWhisper = runWhisper;

  final Future<String> Function(String audioFilePath) _runWhisper;
  final String languageCode;
  final bool shouldTranslateToEnglish;

  @override
  Future<String> transcribeFile(String audioFilePath) async {
    // Keep the adapter tiny: the heavy lifting happens inside the provided
    // Whisper runner (FFI/plugin).
    return _runWhisper(audioFilePath);
  }
}

/// Safe fallback so the app can compile even when no speech backend is wired.
class NoOpSpeechTranscriber implements SpeechTranscriber {
  const NoOpSpeechTranscriber();

  @override
  Future<String> transcribeFile(String audioFilePath) async {
    debugPrint(
      'NoOpSpeechTranscriber called with $audioFilePath. Plug a real backend.',
    );
    return '';
  }
}

/// Result container for speech-to-text only.
class SpeechToTextResult {
  final String transcript;

  const SpeechToTextResult({required this.transcript});
}

/// Connects speech-to-text to the UI.
class SpeechToTextPipeline {
  SpeechToTextPipeline({required this.transcriber});

  final SpeechTranscriber transcriber;

  /// Convenience helper to go from audio file -> transcript.
  Future<SpeechToTextResult> transcribe(String audioFilePath) async {
    final transcript = await transcriber.transcribeFile(audioFilePath);
    return SpeechToTextResult(transcript: transcript);
  }
}
