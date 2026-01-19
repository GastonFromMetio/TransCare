import 'package:flutter/services.dart';

/// Minimal interface for on-device LLM inference.
abstract class LocalLlmClient {
  Future<bool> loadModel({
    String? assetPath,
    String? localPath,
    int nCtx = 2048,
    int nThreads = 4,
  });

  Future<String> complete(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.1,
  });
}

/// MethodChannel bridge to native LLM runtime (llama.cpp, etc.).
class MethodChannelLlmClient implements LocalLlmClient {
  MethodChannelLlmClient({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('llm_infer');

  final MethodChannel _channel;

  @override
  Future<bool> loadModel({
    String? assetPath,
    String? localPath,
    int nCtx = 2048,
    int nThreads = 4,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'loadModel',
      {
        'assetPath': assetPath,
        'localPath': localPath,
        'nCtx': nCtx,
        'nThreads': nThreads,
      },
    );
    return result ?? false;
  }

  @override
  Future<String> complete(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.1,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'infer',
      {
        'prompt': prompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
      },
    );
    return result ?? '';
  }
}
