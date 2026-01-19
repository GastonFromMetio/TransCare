import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import 'llm_prescription_extractor.dart';
import 'local_llm_client.dart';
import 'prescription_engine.dart';
import 'speech_to_text_pipeline.dart';
import 'whisper_flutter_adapter.dart';

void main() {
  runApp(const PrescriptionNormalizerApp());
}

class PrescriptionNormalizerApp extends StatelessWidget {
  const PrescriptionNormalizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prescription Normalizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: 1.02),
      ),
      home: const PrescriptionHomePage(),
    );
  }
}

class PrescriptionHomePage extends StatefulWidget {
  const PrescriptionHomePage({super.key});

  @override
  State<PrescriptionHomePage> createState() => _PrescriptionHomePageState();
}

class _PrescriptionHomePageState extends State<PrescriptionHomePage> {
  static const _sampleText =
      'Ceftriaxone 1g 3 fois par jour VVP pendant 7 jours (retrocession hospitaliere)';

  static const _medicalAssetPath = 'assets/models/whisper-small-medical.bin';
  static const _qwenAssetPath = 'assets/models/qwen2-0_5b-instruct-q4_k_m.gguf';

  static const _whisperModels = <_WhisperModelOption>[
    _WhisperModelOption(
      label: 'Whisper Base (standard)',
      description: 'Modèle générique léger',
      model: WhisperModel.base,
      downloadHost: WhisperFlutterNewTranscriber.defaultDownloadHost,
    ),
    _WhisperModelOption(
      label: 'Whisper Small (médical embarqué)',
      description: 'Modèle spécialisé médical (chargé depuis assets)',
      model: WhisperModel.small,
      downloadHost: null,
      assetPath: _medicalAssetPath,
    ),
  ];

  final _inputController = TextEditingController(text: _sampleText);
  final _normalizer = const TextNormalizer();
  final _extractor = RuleBasedExtractor();
  final _patientExtractor = const PatientProfileExtractor();
  final MethodChannelLlmClient _llmClient = MethodChannelLlmClient();
  late final LlmPrescriptionExtractor _llmExtractor =
      LlmPrescriptionExtractor(client: _llmClient);
  final _recorder = AudioRecorder();
  SpeechToPrescriptionPipeline? _speechPipeline;
  WhisperModel _selectedModel = _whisperModels.first.model;
  String? _selectedHost = _whisperModels.first.downloadHost;
  String? _selectedAssetPath = _whisperModels.first.assetPath;
  Future<void> _pipelineReady = Future.value();
  bool _isPipelineReady = false;
  bool _isInitializing = false;
  String? _initError;
  bool _useLlm = false;
  bool _isLlmReady = false;
  String? _llmError;
  bool _isLlmInitializing = false;
  Timer? _llmInitTimer;
  Stopwatch? _llmStopwatch;

  String _normalizedText = '';
  String _jsonResult = '{"patient": null, "prescriptions": []}';
  String _status = '';
  bool _isRecording = false;
  bool _isProcessing = false;
  PatientProfile? _patientProfile;

  @override
  void initState() {
    super.initState();
    _pipelineReady = _initializePipeline();
    _process();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _recorder.dispose();
    _llmInitTimer?.cancel();
    super.dispose();
  }

  Future<void> _process() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _status = _useLlm ? 'Analyse LLM en cours...' : 'Analyse en cours...';
    });

    final raw = _inputController.text;
    final normalized = _normalizer.normalize(raw);

    PatientProfile? patient;
    List<Prescription> prescriptions;

    if (_useLlm) {
      if (!_isLlmReady) {
        await _initializeLlm();
      }
      try {
        final llmResult = await _llmExtractor.extract(
          raw,
          normalizedText: normalized,
          maxTokens: 64,
          temperature: 0.1,
        );
        patient = llmResult.patient;
        prescriptions = llmResult.prescriptions;
      } catch (e) {
        patient = _patientExtractor.extract(raw, normalizedText: normalized);
        prescriptions = _extractor.extract(normalized);
        setState(() {
          _status = 'Fallback rule-based (LLM indisponible): $e';
        });
      }
    } else {
      patient = _patientExtractor.extract(raw, normalizedText: normalized);
      prescriptions = _extractor.extract(normalized);
    }

    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert({
      'patient': patient?.toJson(),
      'prescriptions': prescriptions.map((p) => p.toJson()).toList(),
    });

    setState(() {
      _normalizedText = normalized;
      _jsonResult = jsonString;
      _patientProfile = patient;
      _isProcessing = false;
      if (!_status.contains('Fallback')) {
        _status = 'Analyse terminée';
      }
    });
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
    final path =
        '${tempDir.path}/dictation_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _status = 'Enregistrement en cours...';
    });
  }

  Future<void> _stopAndTranscribe() async {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _status = 'Transcription Whisper...';
    });

    final path = await _recorder.stop();
    if (path == null) {
      setState(() {
        _isProcessing = false;
        _status = 'Aucun fichier audio capturé';
      });
      return;
    }

    await _pipelineReady;
    final pipeline = _speechPipeline;
    if (pipeline == null) {
      setState(() {
        _isProcessing = false;
        _status = 'Pipeline Whisper non initialisé';
      });
      return;
    }

    try {
      if (_useLlm && !_isLlmReady) {
        await _initializeLlm();
      }
      final result = _useLlm
          ? await pipeline.transcribeAndExtractWithLlm(path)
          : await pipeline.transcribeAndExtract(path);
      const encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _inputController.text = result.transcript;
        _normalizedText = result.normalizedTranscript;
        _jsonResult = encoder.convert({
          'patient': result.patient?.toJson(),
          'prescriptions': result.prescriptions.map((p) => p.toJson()).toList(),
        });
        _patientProfile = result.patient;
        _status = 'Transcription terminée';
      });
    } catch (e) {
      setState(() {
        _status = 'Erreur de transcription: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPipelineReady) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Moteur de prescription'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isInitializing) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _status.isNotEmpty
                      ? _status
                      : 'Préparation du modèle Whisper...',
                  textAlign: TextAlign.center,
                ),
              ),
              if (_initError != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Initialisation échouée.\n'
                    'Assure-toi d’être en ligne ou place le modèle dans '
                    '${_selectedAssetPath ?? 'assets/models/ggml-${_selectedModel.modelName}.bin'}, puis réessaie.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    _initializePipeline();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moteur de prescription'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // --- ZONE INFOS + RÉPONSES (scrollable) ---
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Statut en haut
                      if (_status.isNotEmpty) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _isRecording
                                  ? Icons.mic
                                  : _isProcessing
                                      ? Icons.hourglass_top
                                      : Icons.info_outline,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _status,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      Text(
                        'Modèle Whisper',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<_WhisperModelOption>(
                        initialValue: _whisperModels.firstWhere(
                          (option) =>
                              option.model == _selectedModel &&
                              option.downloadHost == _selectedHost &&
                              option.assetPath == _selectedAssetPath,
                          orElse: () => _whisperModels.first,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        isExpanded: true,
                        selectedItemBuilder: (_) => _whisperModels
                            .map(
                              (option) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(option.label),
                              ),
                            )
                            .toList(),
                        items: _whisperModels
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minHeight: 48),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(option.label),
                                      const SizedBox(height: 2),
                                      Text(
                                        option.description,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (option) {
                          if (option == null) return;
                          _selectModel(option);
                        },
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'Extraction LLM',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        value: _useLlm,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Activer Qwen on-device'),
                        subtitle: Text(
                          _useLlm
                              ? (_isLlmReady
                                  ? 'Le LLM complète patient + prescriptions'
                                  : 'Initialisation du modèle en cours...')
                              : 'Extraction rule-based uniquement',
                        ),
                        onChanged: _isProcessing
                            ? null
                            : (value) {
                                setState(() {
                                  _useLlm = value;
                                });
                                if (value) {
                                  _initializeLlm().then((_) => _process());
                                } else {
                                  _process();
                                }
                              },
                      ),
                      const SizedBox(height: 16),

                      // --- Endroit dédié aux réponses ---
                      Text(
                        'Réponse',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),

                      // Texte normalisé
                      Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Texte normalisé',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _normalizedText,
                                key: const Key('normalized-text'),
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Profil patient
                      Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profil patient',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              if (_patientProfile == null) ...[
                                Text(
                                  'Aucun profil détecté',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ] else ...[
                                Text(
                                  'Nom: ${_patientProfile!.lastName ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Prénom: ${_patientProfile!.firstName ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Genre: ${_patientProfile!.gender ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Adresse: ${_patientProfile!.address ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Ville: ${_patientProfile!.city ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Email: ${_patientProfile!.email ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Téléphone: ${_patientProfile!.phone ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (_patientProfile!.civility != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Civilité: ${_patientProfile!.civility}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                                if (_patientProfile!.sourceText != null &&
                                    _patientProfile!.sourceText!
                                        .trim()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Extrait: ${_patientProfile!.sourceText}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // JSON résultat
                      Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'JSON résultat',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _jsonResult,
                                key: const Key('json-output'),
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // --- ZONE INPUT + BOUTON VOCAL EN BAS ---
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
                          : 'Maintiens le micro pour dicter ou saisis le texte',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Champ de texte en bas
                        Expanded(
                          child: TextField(
                            key: const Key('input-text'),
                            controller: _inputController,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: 'Dicter ou saisir une ordonnance…',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              suffixIcon: IconButton(
                                onPressed: _isProcessing ? null : _process,
                                icon: const Icon(Icons.send),
                                tooltip: 'Normaliser et extraire',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Bouton vocal rond
                        GestureDetector(
                          onLongPressStart: (_) => _startRecording(),
                          onLongPressEnd: (_) => _stopAndTranscribe(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 4),
                                  color: Colors.black.withOpacity(0.18),
                                ),
                              ],
                            ),
                            child: Icon(
                              _isRecording ? Icons.mic : Icons.mic_none,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectModel(_WhisperModelOption option) {
    final isSameSelection = option.model == _selectedModel &&
        option.downloadHost == _selectedHost &&
        option.assetPath == _selectedAssetPath;
    if (isSameSelection && _isPipelineReady) return;

    setState(() {
      _selectedModel = option.model;
      _selectedHost = option.downloadHost;
      _selectedAssetPath = option.assetPath;
      _status = 'Changement de modèle Whisper (${option.label})...';
      _isPipelineReady = false;
    });
    _pipelineReady = _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      _isPipelineReady = false;
      _isInitializing = true;
      _initError = null;
      setState(() {
        _status = 'Préparation du modèle Whisper...';
      });

      final transcriber = await WhisperFlutterNewTranscriber.initialize(
        model: _selectedModel,
        language: 'fr',
        translate: false,
        downloadHost: _selectedHost, // modèle custom (Hugging Face ou offline)
        assetModelPath: _selectedAssetPath,
        onStatus: (status) {
          setState(() {
            _status = status;
          });
        },
      );

      _speechPipeline = SpeechToPrescriptionPipeline(
        transcriber: transcriber,
        llmExtractor: _llmExtractor,
      );

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

  Future<void> _initializeLlm() async {
    if (_isLlmReady || _isLlmInitializing) return;
    setState(() {
      _llmError = null;
      _status = 'Chargement du modèle Qwen...';
      _isLlmInitializing = true;
    });

    _llmStopwatch?.stop();
    _llmStopwatch = Stopwatch()..start();
    _llmInitTimer?.cancel();
    _llmInitTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final elapsed = _llmStopwatch?.elapsed.inSeconds ?? 0;
      setState(() {
        _status = elapsed < 15
            ? 'Chargement du modèle Qwen...'
            : 'Chargement du modèle Qwen... (${elapsed}s)';
      });
    });

    try {
      final threads = Platform.numberOfProcessors.clamp(1, 6);
      final ready = await _llmClient.loadModel(
        assetPath: _qwenAssetPath,
        nCtx: 2048,
        nThreads: threads,
      );
      setState(() {
        _isLlmReady = ready;
        _status = ready ? 'Modèle Qwen prêt' : 'Échec chargement Qwen';
        _isLlmInitializing = false;
      });
      if (ready && _useLlm) {
        _process();
      }
    } catch (e) {
      setState(() {
        _llmError = e.toString();
        _status = 'Échec chargement Qwen: $e';
        _isLlmInitializing = false;
      });
    } finally {
      _llmStopwatch?.stop();
      _llmInitTimer?.cancel();
      _llmInitTimer = null;
    }
  }
}

class _WhisperModelOption {
  const _WhisperModelOption({
    required this.label,
    required this.description,
    required this.model,
    this.downloadHost,
    this.assetPath,
  });

  final String label;
  final String description;
  final WhisperModel model;
  final String? downloadHost;
  final String? assetPath;
}
