import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../route_observer.dart';
import '../speech_to_text_pipeline.dart';
import '../services/auth_service.dart';
import '../services/prescription_service.dart';
import '../widgets/top_notification.dart';

const List<String> _medicineOptions = [
  'Ceftriaxone',
  'Ceftazidime',
  'Piperacilline + Tazobactam',
  'Ganciclovir',
  'Ambisome',
  'Amphotericine B',
  'Amikacine',
  'Amoxicilline + Acide Clavulanique',
  'Aztreonam',
  'Cefepime',
  'Sulfamethoxazole + Trimethoprime',
  'Oxacilline',
  'Caspofungine',
  'Cefazoline',
  'Cefotaxime',
  'Ciprofloxacine',
  'Daptomycine',
  'Clindamycine',
  'Erythromycine',
  'Metronidazole',
  'Gentamicine',
  'Ertapenem',
  'Cefoxitine',
  'Meropenem',
  'Micafungine',
  'Tobramycine',
  'Temocilline',
  'Ofloxacine',
  'Cloxacilline',
  'Penicilline G',
  'Piperacilline',
  'Rifampicine',
  'Teicoplanine',
  'Levofloxacine',
  'Imipeneme + Cilastatine',
  'Fluconazole',
  'Vancomycine',
  'Dalbavancine',
  'Amoxicilline',
  'Clarithromycine',
  'Aciclovir',
  'Linezolide',
];

class TranscriptionResultPage extends StatefulWidget {
  const TranscriptionResultPage({super.key, required this.resultFuture});

  final Future<SpeechToTextResult> resultFuture;

  @override
  State<TranscriptionResultPage> createState() =>
      _TranscriptionResultPageState();
}

class _TranscriptionResultPageState extends State<TranscriptionResultPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin, RouteAware {
  late final TextEditingController _transcriptionController;
  late final TextEditingController _patientNameController;
  late final TextEditingController _dobController;
  late final AnimationController _aiController;
  final List<_MedicationForm> _medications = [];
  late Future<AuthUser?> _profileFuture;
  bool _isProcessing = true;
  String? _loadError;
  bool _isSubmitting = false;
  bool _isPolling = false;
  String? _backendError;
  String? _prescriptionId;
  Map<String, dynamic>? _backendPayload;
  Map<String, dynamic>? _prescription;
  String? _formPrescriptionId;
  bool _isValidating = false;
  String? _validationError;
  bool _hasUserEdited = false;
  bool _isWaitingForPdf = false;
  String? _pdfUrl;
  String? _pdfError;
  Timer? _pdfPollTimer;
  int _pdfPollAttempts = 0;
  Timer? _pollTimer;
  bool _pausePollingWhenInactive = false;
  bool _isRouteSubscribed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transcriptionController = TextEditingController();
    _patientNameController = TextEditingController();
    _dobController = TextEditingController();
    _profileFuture = AuthService.instance.fetchUserProfile();
    _aiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _loadResult();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_isRouteSubscribed && route is PageRoute) {
      routeObserver.subscribe(this, route);
      _isRouteSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_isRouteSubscribed) {
      routeObserver.unsubscribe(this);
    }
    _pollTimer?.cancel();
    _pdfPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _aiController.dispose();
    _transcriptionController.dispose();
    _patientNameController.dispose();
    _dobController.dispose();
    for (final medication in _medications) {
      medication.dispose();
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshOnReturn();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_prescriptionId == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_pollTimer != null) {
        _pausePollingWhenInactive = true;
        _pollTimer?.cancel();
        _pollTimer = null;
        if (mounted) {
          setState(() {
            _isPolling = false;
          });
        }
        debugPrint('Polling paused (app inactive)');
      }
      return;
    }
    if (state == AppLifecycleState.resumed && _pausePollingWhenInactive) {
      _pausePollingWhenInactive = false;
      _startPolling(_prescriptionId!);
      debugPrint('Polling resumed (app active)');
    }
  }

  Future<void> _loadResult() async {
    try {
      final result = await widget.resultFuture;
      if (!mounted) return;
      setState(() {
        _transcriptionController.text = result.transcript;
        _isProcessing = false;
      });
      await _submitTranscription(result.transcript);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Erreur de transcription: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _submitTranscription(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _isSubmitting = true;
      _backendError = null;
      _backendPayload = null;
    });
    try {
      final service = PrescriptionService();
      final submission = await service.submitTranscription(text);
      if (!mounted) return;
      setState(() {
        _prescriptionId = submission.id;
        _backendPayload = submission.payload;
        _isSubmitting = false;
      });
      _hydratePrescriptionFromPayload(submission.payload);
      if (submission.id == null) {
        setState(() {
          _backendError = 'Identifiant ordonnance manquant.';
        });
        return;
      }
      _startPolling(submission.id!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backendError = 'Envoi echoue: $e';
        _isSubmitting = false;
      });
    }
  }

  void _startPolling(String id) {
    _pollTimer?.cancel();
    setState(() {
      _isPolling = true;
    });
    debugPrint('Polling started: every 4s for prescription $id');
    _pollOnce(id);
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollOnce(id);
    });
  }

  void _refreshOnReturn() {
    setState(() {
      _profileFuture = AuthService.instance.fetchUserProfile();
    });
    final id = _prescriptionId ?? _formPrescriptionId;
    if (id == null || id.isEmpty) return;
    _refreshPrescription(id);
  }

  Future<void> _refreshPrescription(String id) async {
    try {
      final service = PrescriptionService();
      final payload = await service.fetchPrescription(id);
      if (!mounted) return;
      setState(() {
        _backendPayload = payload;
      });
      _hydratePrescriptionFromPayload(payload);
      final pdfUrl = _extractPdfUrl(payload);
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        setState(() {
          _pdfUrl = pdfUrl;
          _isWaitingForPdf = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backendError = 'Rafraichissement echoue: $e';
      });
    }
  }

  Future<void> _pollOnce(String id) async {
    try {
      final service = PrescriptionService();
      debugPrint('Polling: GET /api/prescriptions/$id/poll');
      final result = await service.pollPrescription(id);
      if (!mounted) return;
      setState(() {
        _backendPayload = result.payload;
      });
      _hydratePrescriptionFromPayload(result.payload);
      if (result.isComplete) {
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _isPolling = false;
        });
        debugPrint('Polling stopped: prescription $id ready');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backendError = 'Polling echoue: $e';
        _isPolling = false;
      });
      _pollTimer?.cancel();
      debugPrint('Polling stopped (error): $e');
    }
  }

  void _hydratePrescriptionFromPayload(Map<String, dynamic> payload) {
    final prescription = _extractPrescription(payload);
    if (prescription == null) return;
    final id = prescription['id'];
    final idString = id == null ? null : '$id';
    if (idString == null || idString.isEmpty) return;
    if (_formPrescriptionId == idString) {
      if (mounted) {
        setState(() {
          _prescription = prescription;
        });
      }
      if (_hasUserEdited) {
        return;
      }
    } else {
      _formPrescriptionId = idString;
    }
    _prescription = prescription;
    _patientNameController.text =
        '${prescription['patient_name'] ?? ''}'.trim();
    _dobController.text =
        _formatDateOfBirthForDisplay('${prescription['date_of_birth'] ?? ''}');
    for (final medication in _medications) {
      medication.dispose();
    }
    _medications
      ..clear()
      ..addAll(_buildMedicationForms(prescription['medications']));
    if (_medications.isEmpty) {
      _medications.add(_MedicationForm.empty());
    }
    if (mounted) {
      setState(() {});
    }
  }

  List<_MedicationForm> _buildMedicationForms(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(_MedicationForm.fromJson)
        .toList();
  }

  void _addMedication() {
    setState(() {
      _medications.add(_MedicationForm.empty());
    });
    _hasUserEdited = true;
  }

  void _removeMedication(_MedicationForm medication) {
    setState(() {
      _medications.remove(medication);
      medication.dispose();
      if (_medications.isEmpty) {
        _medications.add(_MedicationForm.empty());
      }
    });
    _hasUserEdited = true;
  }

  void _markUserEdited([String? _]) {
    if (!mounted) return;
    setState(() {
      _hasUserEdited = true;
    });
  }

  bool _hasIncompleteMedications() {
    for (final medication in _medications) {
      final name = medication.nameController.text.trim();
      final posology = medication.posologyController.text.trim();
      final duration = medication.durationController.text.trim();
      final path = medication.pathController.text.trim();
      final isAllEmpty =
          name.isEmpty && posology.isEmpty && duration.isEmpty && path.isEmpty;
      if (isAllEmpty) {
        return true;
      }
      final isComplete = name.isNotEmpty &&
          posology.isNotEmpty &&
          duration.isNotEmpty &&
          path.isNotEmpty;
      if (!isComplete) {
        return true;
      }
    }
    return false;
  }

  Future<void> _validatePrescription() async {
    final id = _prescriptionId ?? _formPrescriptionId;
    if (id == null || id.isEmpty) return;
    setState(() {
      _isValidating = true;
      _validationError = null;
    });
    try {
      final service = PrescriptionService();
      final payload = _buildPrescriptionPayload();
      await service.updatePrescription(id, payload);
      await service.validatePrescription(id, payload);
      if (!mounted) return;
      setState(() {
        _isValidating = false;
        _isWaitingForPdf = true;
        _pdfUrl = null;
        _pdfError = null;
      });
      _showNotification('Ordonnance validee et envoyee.');
      _startPdfPolling(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validationError = 'Validation echouee: $e';
        _isValidating = false;
      });
    }
  }

  void _startPdfPolling(String id) {
    _pdfPollTimer?.cancel();
    _pdfPollAttempts = 0;
    _pollPdfOnce(id);
    _pdfPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollPdfOnce(id);
    });
  }

  Future<void> _pollPdfOnce(String id) async {
    try {
      _pdfPollAttempts += 1;
      if (_pdfPollAttempts > 45) {
        _pdfPollTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _isWaitingForPdf = false;
          _pdfError =
              'Le PDF est toujours en cours de generation. Reessaie plus tard.';
        });
        return;
      }
      final service = PrescriptionService();
      final payload = await service.fetchPrescription(id);
      if (!mounted) return;
      final url = _extractPdfUrl(payload);
      if (url == null || url.isEmpty) {
        return;
      }
      _pdfPollTimer?.cancel();
      setState(() {
        _pdfUrl = url;
        _isWaitingForPdf = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pdfError = 'Recuperation PDF echouee: $e';
      });
    }
  }

  Future<void> _openPdf(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.inAppWebView);
  }

  Map<String, dynamic> _buildPrescriptionPayload() {
    final medications = _medications
        .map((medication) => medication.toJson())
        .where((entry) => entry.isNotEmpty)
        .toList();
    return <String, dynamic>{
      'transcribed_text': _transcriptionController.text.trim(),
      'patient_name': _patientNameController.text.trim(),
      'date_of_birth': _normalizeDateOfBirthForApi(_dobController.text),
      'medications': medications,
    };
  }

  String? _normalizeDateOfBirthForApi(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      return raw;
    }
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
    if (match == null) {
      return raw;
    }
    final day = match.group(1)!;
    final month = match.group(2)!;
    final year = match.group(3)!;
    return '$year-$month-$day';
  }

  String _formatDateOfBirthForDisplay(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final slashMatch = RegExp(r'^(\d{4})/(\d{2})/(\d{2})$').firstMatch(raw);
    if (slashMatch != null) {
      final year = slashMatch.group(1)!;
      final month = slashMatch.group(2)!;
      final day = slashMatch.group(3)!;
      return '$day/$month/$year';
    }
    final dashMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (dashMatch != null) {
      final year = dashMatch.group(1)!;
      final month = dashMatch.group(2)!;
      final day = dashMatch.group(3)!;
      return '$day/$month/$year';
    }
    return raw;
  }

  String? _emptyToNull(String value) {
    if (value.trim().isEmpty) return null;
    return value.trim();
  }

  void _showNotification(String message) {
    TopNotification.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = _prescription != null;
    final isFormLocked =
        _isSubmitting || _isPolling || _isValidating || _isWaitingForPdf;
    if (_isProcessing) {
      return _buildTranscriptionLoading(context);
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      bottomNavigationBar: _loadError == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  _loadError ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface,
                  colorScheme.surface.withOpacity(0.6),
                ],
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ordonnance',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_isSubmitting || _isPolling)
                      Icon(
                        Icons.cloud_sync,
                        color: colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isSubmitting || _isPolling)
                  _buildApiLoadingCard(context),
                if (_backendError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _backendError ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                if (!isReady) _buildProfileFallback(context),
                if (isReady)
                  Opacity(
                    opacity: isFormLocked ? 0.5 : 1,
                    child: IgnorePointer(
                      ignoring: isFormLocked,
                      child: _buildPrescriptionForm(context),
                    ),
                  ),
                if (_isWaitingForPdf) _buildPdfWaitingCard(context),
                if (_pdfError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _pdfError ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.error),
                    ),
                  ),
                if (_pdfUrl != null) _buildPdfReadyCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileFallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<AuthUser?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profil',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (user == null)
                  Text(
                    'Aucune information de profil disponible.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  )
                else
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: colorScheme.primary.withOpacity(0.12),
                        child: Icon(
                          Icons.person,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name.isNotEmpty ? user.name : 'Utilisateur',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  'Aucune ordonnance detectee pour cette transcription.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTranscriptionLoading(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surface.withOpacity(0.6),
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.94, end: 1),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: _buildAiLoader(colorScheme),
                ),
                const SizedBox(height: 16),
                Text(
                  'Transcription en cours...',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAiLoader(ColorScheme colorScheme) {
    final primary = colorScheme.primary;
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: _aiController,
        builder: (context, _) {
          final t = _aiController.value;
          final pulse = 0.9 + 0.1 * math.sin(t * math.pi * 2);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: t * math.pi * 2,
                child: Container(
                  width: 176,
                  height: 176,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        primary.withOpacity(0.0),
                        primary.withOpacity(0.3),
                        primary.withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      primary.withOpacity(0.25),
                      primary.withOpacity(0.02),
                    ],
                  ),
                ),
              ),
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Icon(
                Icons.auto_awesome,
                color: primary.withOpacity(0.9),
                size: 40,
              ),
              _buildOrbitDot(
                t,
                colorScheme,
                radius: 64,
                size: 10,
                phase: 0,
              ),
              _buildOrbitDot(
                t,
                colorScheme,
                radius: 68,
                size: 8,
                phase: 0.33,
              ),
              _buildOrbitDot(
                t,
                colorScheme,
                radius: 70,
                size: 6,
                phase: 0.66,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrbitDot(
    double t,
    ColorScheme colorScheme, {
    required double radius,
    required double size,
    required double phase,
  }) {
    final angle = (t + phase) * math.pi * 2;
    return Transform.translate(
      offset: Offset(
        math.cos(angle) * radius,
        math.sin(angle) * radius,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.25),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiLoadingCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = _isSubmitting
        ? 'Envoi au serveur...'
        : 'Analyse en cours, veuillez patienter...';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Icon(
                Icons.auto_awesome,
                color: colorScheme.primary,
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Traitement en cours',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrescriptionForm(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Formulaire ordonnance',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _patientNameController,
              onChanged: _markUserEdited,
              decoration: const InputDecoration(
                labelText: 'Patient',
                hintText: 'Nom du patient',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dobController,
              onChanged: _markUserEdited,
              keyboardType: TextInputType.number,
              inputFormatters: [
                _DateSlashInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Date de naissance',
                hintText: 'JJ/MM/AAAA',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Medicaments',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final medication in _medications)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MedicationCard(
                  medication: medication,
                  onRemove: () => _removeMedication(medication),
                  onChanged: _markUserEdited,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addMedication,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un medicament'),
              ),
            ),
            if (_validationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _validationError ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isValidating || _hasIncompleteMedications()
                    ? null
                    : _validatePrescription,
                child: _isValidating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Valider l\'ordonnance'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfWaitingCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.8, end: 1),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Icon(
                Icons.picture_as_pdf,
                color: colorScheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generation du PDF',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Nous attendons le PDF de l\'ordonnance...',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfReadyCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PDF disponible',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'L\'ordonnance est prete.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final url = _pdfUrl;
                  if (url == null) return;
                  _openPdf(url);
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ouvrir le PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSlashInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i += 1) {
      buffer.write(trimmed[i]);
      if (i == 1 || i == 3) {
        if (i != trimmed.length - 1) {
          buffer.write('/');
        }
      }
    }
    var selectionIndex = newValue.selection.baseOffset;
    if (selectionIndex < 0) {
      selectionIndex = newValue.text.length;
    } else if (selectionIndex == 0 &&
        oldValue.selection.baseOffset > 0 &&
        newValue.text.isNotEmpty) {
      final delta = newValue.text.length - oldValue.text.length;
      selectionIndex = (oldValue.selection.baseOffset + delta)
          .clamp(0, newValue.text.length);
    }
    final leading = selectionIndex <= 0
        ? ''
        : newValue.text.substring(0, selectionIndex);
    final digitsBeforeCursor = RegExp(r'\\d').allMatches(leading).length;
    var newOffset = digitsBeforeCursor;
    if (digitsBeforeCursor > 2) newOffset += 1;
    if (digitsBeforeCursor > 4) newOffset += 1;
    newOffset = math.min(newOffset, buffer.length);
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}

class _MedicationForm {
  _MedicationForm({
    required this.nameController,
    required this.posologyController,
    required this.durationController,
    required this.pathController,
  });

  factory _MedicationForm.empty() {
    return _MedicationForm(
      nameController: TextEditingController(),
      posologyController: TextEditingController(),
      durationController: TextEditingController(),
      pathController: TextEditingController(),
    );
  }

  factory _MedicationForm.fromJson(Map<String, dynamic> json) {
    return _MedicationForm(
      nameController:
          TextEditingController(text: '${json['medicineName'] ?? ''}'),
      posologyController:
          TextEditingController(text: '${json['posology'] ?? ''}'),
      durationController:
          TextEditingController(text: '${json['duration'] ?? ''}'),
      pathController: TextEditingController(text: '${json['path'] ?? ''}'),
    );
  }

  final TextEditingController nameController;
  final TextEditingController posologyController;
  final TextEditingController durationController;
  final TextEditingController pathController;

  Map<String, dynamic> toJson() {
    final name = nameController.text.trim();
    final posology = posologyController.text.trim();
    final duration = durationController.text.trim();
    final path = pathController.text.trim();
    if (name.isEmpty && posology.isEmpty && duration.isEmpty && path.isEmpty) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{
      'medicineName': name,
      'posology': posology,
      'duration': duration,
      'path': path,
    };
  }

  void dispose() {
    nameController.dispose();
    posologyController.dispose();
    durationController.dispose();
    pathController.dispose();
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.onRemove,
    required this.onChanged,
  });

  final _MedicationForm medication;
  final VoidCallback onRemove;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Traitement',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer',
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _medicineOptions.contains(medication.nameController.text)
                  ? medication.nameController.text
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Medicament',
              ),
              items: _medicineOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(
                        option,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                medication.nameController.text = value;
                onChanged(value);
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: medication.posologyController,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Posologie',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: medication.durationController,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Duree',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: medication.pathController,
              onChanged: onChanged,
              decoration: const InputDecoration(
                labelText: 'Voie',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic>? _extractPrescription(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final data = payload['data'];
  if (data is Map<String, dynamic>) {
    final prescription = data['prescription'];
    if (prescription is Map<String, dynamic>) return prescription;
  }
  final prescription = payload['prescription'];
  if (prescription is Map<String, dynamic>) return prescription;
  return null;
}

String? _extractPdfUrl(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final data = payload['data'];
  Map<String, dynamic>? prescription;
  if (data is Map<String, dynamic>) {
    final inner = data['prescription'];
    if (inner is Map<String, dynamic>) {
      prescription = inner;
    } else if (data['pdf_url'] != null) {
      return '${data['pdf_url']}';
    }
  }
  final rootPrescription = payload['prescription'];
  if (rootPrescription is Map<String, dynamic>) {
    prescription = rootPrescription;
  }
  if (payload['pdf_url'] != null) {
    return '${payload['pdf_url']}';
  }
  if (prescription == null) return null;
  final candidates = [
    'pdf_url',
    'pdfUrl',
    'prescription_pdf_url',
    'prescriptionPdfUrl',
    'pdf',
    'document_url',
  ];
  for (final key in candidates) {
    final value = prescription[key];
    if (value != null && '$value'.isNotEmpty) {
      return '$value';
    }
  }
  return null;
}
