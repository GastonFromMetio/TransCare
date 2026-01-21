import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../speech_to_text_pipeline.dart';
import '../whisper_model_loader.dart';
import 'prescription_form_page.dart';

class PrescriptionHomePage extends StatefulWidget {
  const PrescriptionHomePage({super.key});

  @override
  State<PrescriptionHomePage> createState() => _PrescriptionHomePageState();
}

class _PrescriptionHomePageState extends State<PrescriptionHomePage> {
  final _recorder = AudioRecorder();
  SpeechToPrescriptionPipeline? _speechPipeline;
  Future<void> _pipelineReady = Future.value();
  bool _isPipelineReady = false;
  bool _isInitializing = false;
  String? _initError;
  late final VoidCallback _statusListener;

  String _status = '';
  bool _isRecording = false;
  bool _isProcessing = false;
  DateTime? _recordingStartedAt;

  @override
  void initState() {
    super.initState();
    _statusListener = () {
      if (!mounted) return;
      setState(() {
        _status = WhisperModelLoader.status.value;
      });
    };
    WhisperModelLoader.status.addListener(_statusListener);
    _pipelineReady = _initializePipeline();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestMicPermission();
    });
  }

  @override
  void dispose() {
    WhisperModelLoader.status.removeListener(_statusListener);
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isProcessing) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() {
        _status = 'Permission micro refusée';
      });
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${tempDir.path}/dictation_$timestamp.pcm';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
          audioManagerMode: AudioManagerMode.modeInCommunication,
        ),
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingStartedAt = DateTime.now();
      _status = 'Enregistrement en cours...';
    });
  }

  Future<void> _requestMicPermission() async {
    await _recorder.hasPermission();
  }

  Future<void> _stopAndTranscribe() async {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _status = 'Transcription en cours...';
    });

    final path = await _recorder.stop();
    if (path == null) {
      setState(() {
        _isProcessing = false;
        _status = 'Aucun fichier audio capturé';
      });
      return;
    }

    final pcmFile = File(path);
    if (!pcmFile.existsSync()) {
      setState(() {
        _isProcessing = false;
        _status = 'Fichier audio introuvable';
      });
      return;
    }

    final pcmStats = await _analyzePcm16(
      pcmFile,
      sampleRate: 16000,
      channels: 1,
    );
    debugPrint(
      'PCM stats: rms=${pcmStats.rms.toStringAsFixed(4)} '
      'peak=${pcmStats.peak.toStringAsFixed(4)} '
      'samples=${pcmStats.samples}',
    );

    File wavFile;
    try {
      wavFile = await _wrapPcmToWav(
        pcmFile,
        sampleRate: 16000,
        channels: 1,
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _status = 'Conversion audio échouée';
      });
      return;
    }

    final durationMs = _recordingStartedAt == null
        ? null
        : DateTime.now().difference(_recordingStartedAt!).inMilliseconds;
    _recordingStartedAt = null;

    await _pipelineReady;
    final pipeline = _speechPipeline;
    if (pipeline == null) {
      setState(() {
        _isProcessing = false;
        _status = 'Pipeline Whisper non initialisé';
      });
      return;
    }

    const minAudioBytes = 2048;
    final audioBytes = wavFile.lengthSync();
    debugPrint(
      'Audio recorded: path=${wavFile.path} bytes=$audioBytes '
      'durationMs=${durationMs ?? -1}',
    );
    if (audioBytes < minAudioBytes) {
      setState(() {
        _isProcessing = false;
        _status = 'Audio trop court, réessaie la dictée';
      });
      return;
    }

    final resultFuture = pipeline.transcribeAndExtract(wavFile.path);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionFormPage(resultFuture: resultFuture),
      ),
    );
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _status = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPipelineReady) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'TransCare',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                if (_isInitializing) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                Text(
                  _status.isNotEmpty
                      ? _status
                      : 'Téléchargement du modèle Whisper...',
                  textAlign: TextAlign.center,
                ),
                if (_initError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Initialisation échouée.\n'
                    'Assure-toi d’être en ligne puis réessaie.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _pipelineReady = _initializePipeline();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TransCare'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/profile');
            },
            icon: const Icon(Icons.account_circle),
            tooltip: 'Mon compte',
          ),
        ],
      ),
      body: _buildMicPage(context),
    );
  }

  Future<void> _initializePipeline() async {
    try {
      _isPipelineReady = false;
      _isInitializing = true;
      _initError = null;
      setState(() {
        _status = WhisperModelLoader.status.value.isEmpty
            ? 'Préparation du modèle Whisper...'
            : WhisperModelLoader.status.value;
      });

      final transcriber = await WhisperModelLoader.ensureInitialized();

      _speechPipeline = SpeechToPrescriptionPipeline(transcriber: transcriber);

      setState(() {
        _isPipelineReady = true;
        _isInitializing = false;
        _status = 'Modèle Whisper prêt';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = e.toString();
        _status = 'Échec initialisation Whisper: $e';
      });
    }
  }

  Widget _buildMicPage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopAndTranscribe(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording
                            ? colorScheme.error
                            : colorScheme.primary,
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 22,
                            spreadRadius: 2,
                            offset: const Offset(0, 6),
                            color: Colors.black.withOpacity(0.2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isRecording
                            ? 'Relâche pour arrêter et transcrire'
                            : 'Appuie et maintiens pour dicter',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      if (_status.isNotEmpty)
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<File> _wrapPcmToWav(
  File pcmFile, {
  required int sampleRate,
  required int channels,
}) async {
  final pcmBytes = await pcmFile.readAsBytes();
  final dataLength = pcmBytes.length;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final chunkSize = 36 + dataLength;

  final wavBytes = BytesBuilder();
  wavBytes.add(_asciiBytes('RIFF'));
  wavBytes.add(_int32le(chunkSize));
  wavBytes.add(_asciiBytes('WAVE'));
  wavBytes.add(_asciiBytes('fmt '));
  wavBytes.add(_int32le(16)); // PCM header size
  wavBytes.add(_int16le(1)); // PCM format
  wavBytes.add(_int16le(channels));
  wavBytes.add(_int32le(sampleRate));
  wavBytes.add(_int32le(byteRate));
  wavBytes.add(_int16le(blockAlign));
  wavBytes.add(_int16le(bitsPerSample));
  wavBytes.add(_asciiBytes('data'));
  wavBytes.add(_int32le(dataLength));
  wavBytes.add(pcmBytes);

  final wavPath = pcmFile.path.replaceAll(RegExp(r'\.pcm$'), '.wav');
  final wavFile = File(wavPath);
  await wavFile.writeAsBytes(wavBytes.takeBytes(), flush: true);
  return wavFile;
}

List<int> _asciiBytes(String value) => value.codeUnits;

List<int> _int16le(int value) => <int>[
      value & 0xff,
      (value >> 8) & 0xff,
    ];

List<int> _int32le(int value) => <int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

class _PcmStats {
  final double rms;
  final double peak;
  final int samples;

  const _PcmStats({
    required this.rms,
    required this.peak,
    required this.samples,
  });
}

Future<_PcmStats> _analyzePcm16(
  File pcmFile, {
  required int sampleRate,
  required int channels,
}) async {
  final bytes = await pcmFile.readAsBytes();
  if (bytes.isEmpty) {
    return const _PcmStats(rms: 0, peak: 0, samples: 0);
  }

  final sampleCount = bytes.length ~/ 2;
  var sumSquares = 0.0;
  var peak = 0.0;
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  for (var i = 0; i < sampleCount; i++) {
    final value = data.getInt16(i * 2, Endian.little) / 32768.0;
    final absValue = value.abs();
    if (absValue > peak) peak = absValue;
    sumSquares += value * value;
  }
  final rms =
      sampleCount == 0 ? 0.0 : math.sqrt(sumSquares / sampleCount);
  return _PcmStats(rms: rms, peak: peak, samples: sampleCount);
}
