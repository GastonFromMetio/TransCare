import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import 'whisper_flutter_adapter.dart';
import 'whisper_prompts.dart';

class WhisperModelLoader {
  static final ValueNotifier<String> status = ValueNotifier<String>('');
  static Future<WhisperFlutterNewTranscriber>? _cached;

  static Future<WhisperFlutterNewTranscriber> ensureInitialized() {
    final existing = _cached;
    if (existing != null) return existing;

    final future = WhisperFlutterNewTranscriber.initialize(
      model: WhisperModel.small,
      language: 'fr',
      translate: false,
      initialPrompt: whisperSystemPrompt,
      temperature: 0.1,
      beamSize: 5,
      bestOf: 5,
      assetModelPath: 'assets/models/ggml-base-q5_1.bin',
      forceBundledAsset: true,
      onStatus: (value) {
        status.value = value;
      },
    );
    _cached = future;
    future.catchError((_) {
      if (identical(_cached, future)) {
        _cached = null;
      }
    });
    return future;
  }

  static Future<void> warmUp() async {
    try {
      await ensureInitialized();
    } catch (error) {
      debugPrint('Whisper warm-up failed: $error');
    }
  }
}
