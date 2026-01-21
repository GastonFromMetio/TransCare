import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import 'speech_to_text_pipeline.dart';

/// Adapter du plugin `whisper_flutter_new` vers l'interface [SpeechTranscriber].
/// Il télécharge le modèle au premier appel si absent (via Hugging Face).
class WhisperFlutterNewTranscriber implements SpeechTranscriber {
  static const _minModelSizes = <WhisperModel, int>{
    WhisperModel.tiny: 30 * 1024 * 1024,
    WhisperModel.base: 120 * 1024 * 1024,
    WhisperModel.small: 400 * 1024 * 1024,
    WhisperModel.medium: 1400 * 1024 * 1024,
    WhisperModel.largeV1: 2500 * 1024 * 1024,
    WhisperModel.largeV2: 2500 * 1024 * 1024,
  };

  WhisperFlutterNewTranscriber({
    WhisperModel model = WhisperModel.base,
    this.language = 'fr',
    this.translate = false,
    this.splitOnWord = true,
    this.initialPrompt = '',
    this.temperature = 0.1,
    this.temperatureInc = 0.0,
    this.bestOf = 5,
    this.beamSize = 5,
    this.entropyThreshold = 2.4,
    this.logprobThreshold = -1.0,
    this.noSpeechThreshold = 0.6,
    this.modelDir,
  }) : _whisper = Whisper(
          model: model,
          modelDir: modelDir,
          downloadHost: null,
        );

  final Whisper _whisper;
  final String language;
  final bool translate;
  final bool splitOnWord;
  final String initialPrompt;
  final double temperature;
  final double temperatureInc;
  final int bestOf;
  final int beamSize;
  final double entropyThreshold;
  final double logprobThreshold;
  final double noSpeechThreshold;
  final String? modelDir;
  /// Prépare le modèle (copie l'asset ou télécharge) et retourne l'instance prête.
  static Future<WhisperFlutterNewTranscriber> initialize({
    WhisperModel model = WhisperModel.base,
    String language = 'fr',
    bool translate = false,
    bool splitOnWord = true,
    String initialPrompt = '',
    double temperature = 0.1,
    double temperatureInc = 0.0,
    int bestOf = 5,
    int beamSize = 5,
    double entropyThreshold = 2.4,
    double logprobThreshold = -1.0,
    double noSpeechThreshold = 0.6,
    String? assetModelPath,
    bool forceBundledAsset = false,
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('Préparation du modèle Whisper...');

    final supportDir = await getApplicationSupportDirectory();
    final modelDir = '${supportDir.path}/whisper_models';
    await Directory(modelDir).create(recursive: true);
    final modelFilename = 'ggml-${model.modelName}.bin';
    final modelPath = '$modelDir/$modelFilename';
    final modelFile = File(modelPath);
    const fallbackMinValidSizeBytes =
        1024 * 1024; // protect against HTML/error downloads
    var expectedMinBytes =
        _minModelSizes[model] ?? fallbackMinValidSizeBytes;
    final assetCandidates = <String>{
      if (assetModelPath != null) assetModelPath,
      'assets/models/$modelFilename',
    }.toList();

    final hasModelFile = modelFile.existsSync();
    final modelBytes = hasModelFile ? modelFile.lengthSync() : 0;
    final isLikelyCorrupted = hasModelFile && modelBytes < expectedMinBytes;

    final bundledAssetPath = await _firstExistingAsset(assetCandidates);
    final hasBundledAsset = bundledAssetPath != null;

    if (forceBundledAsset && !hasBundledAsset) {
      throw StateError(
        'Modèle Whisper embarqué introuvable (${assetModelPath ?? 'assets/models/ggml-small.bin'}).',
      );
    }

    if (forceBundledAsset && hasBundledAsset) {
      onStatus?.call(
        'Chargement du modèle Whisper embarqué (${model.modelName})...',
      );
      try {
        await modelFile.delete();
      } catch (_) {}
      final byteData = await rootBundle.load(bundledAssetPath);
      expectedMinBytes = byteData.lengthInBytes;
      await modelFile.writeAsBytes(
        byteData.buffer.asUint8List(),
        flush: true,
      );
      debugPrint(
        'Whisper model source=asset path=$modelPath bytes=${modelFile.lengthSync()}',
      );
    } else if (!hasModelFile || isLikelyCorrupted) {
      if (isLikelyCorrupted) {
        onStatus?.call(
          'Modèle Whisper corrompu détecté, nouveau téléchargement...',
        );
        // Clean up the bad file so the plugin does not try to load it.
        try {
          await modelFile.delete();
        } catch (_) {}
      }
      if (hasBundledAsset) {
        onStatus?.call(
          'Copie du modèle Whisper embarqué (${model.modelName})...',
        );
        final byteData = await rootBundle.load(bundledAssetPath);
        expectedMinBytes = byteData.lengthInBytes;
        await modelFile.writeAsBytes(
          byteData.buffer.asUint8List(),
          flush: true,
        );
        debugPrint(
          'Whisper model source=asset path=$modelPath bytes=${modelFile.lengthSync()}',
        );
      } else {
        throw StateError(
          'Aucun modèle Whisper embarqué trouvé. '
          'Ajoute le modèle dans assets/models et relance.',
        );
      }
    }

    if (modelFile.existsSync() && modelFile.lengthSync() < expectedMinBytes) {
      throw StateError(
        'Modèle Whisper invalide (taille trop petite). '
        'Supprime le modèle et relance la copie depuis les assets.',
      );
    }

    final header = await _readModelHeader(modelFile);
    final normalizedHeader = _normalizeHeader(header);
    debugPrint(
      'Whisper model ready: path=$modelPath bytes=${modelFile.lengthSync()} '
      'header=$header normalized=$normalizedHeader',
    );
    if (!_isSupportedHeader(normalizedHeader)) {
      throw StateError(
        'Modèle Whisper invalide (header="$header"). '
        'Attendu "ggml" ou "GGUF". '
        'Remplace le fichier dans assets/models par un modèle whisper.cpp valide.',
      );
    }

    return WhisperFlutterNewTranscriber(
      model: model,
      language: language,
      translate: translate,
      splitOnWord: splitOnWord,
      initialPrompt: initialPrompt,
      temperature: temperature,
      temperatureInc: temperatureInc,
      bestOf: bestOf,
      beamSize: beamSize,
      entropyThreshold: entropyThreshold,
      logprobThreshold: logprobThreshold,
      noSpeechThreshold: noSpeechThreshold,
      modelDir: modelDir,
    );
  }

  static Future<String> _readModelHeader(File modelFile) async {
    try {
      final raf = await modelFile.open();
      final bytes = await raf.read(4);
      await raf.close();
      if (bytes.isEmpty) return 'empty';
      final ascii = String.fromCharCodes(bytes);
      return ascii;
    } catch (_) {
      return 'unreadable';
    }
  }

  static String _normalizeHeader(String header) {
    if (header == 'lmgg') {
      return 'ggml';
    }
    return header;
  }

  static bool _isSupportedHeader(String header) {
    return header == 'ggml' || header == 'GGUF';
  }

  static Future<bool> _assetExists(String assetPath) async {
    try {
      // Flutter 3.16+ embarque l'AssetManifest en binaire ; on tente un load direct.
      await rootBundle.load(assetPath);
      return true;
    } on FlutterError {
      // Fallback : tenter via manifest JSON (pour compat ascendantes)
      try {
        final manifestContent =
            await rootBundle.loadString('AssetManifest.json');
        final manifestMap =
            json.decode(manifestContent) as Map<String, dynamic>? ?? {};
        return manifestMap.containsKey(assetPath);
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _firstExistingAsset(
    List<String> candidatePaths,
  ) async {
    for (final path in candidatePaths) {
      if (await _assetExists(path)) return path;
    }
    return null;
  }

  @override
  Future<String> transcribeFile(String audioFilePath) async {
    final response = await _whisper.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: audioFilePath,
        language: language,
        isTranslate: translate,
        splitOnWord: splitOnWord,
        initialPrompt: initialPrompt,
        temperature: temperature,
        temperatureInc: temperatureInc,
        bestOf: bestOf,
        beamSize: beamSize,
        entropyThreshold: entropyThreshold,
        logprobThreshold: logprobThreshold,
        noSpeechThreshold: noSpeechThreshold,
      ),
    );
    return response.text;
  }
}
