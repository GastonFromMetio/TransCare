import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../prescription_engine.dart';
import '../speech_to_text_pipeline.dart';
import '../widgets/prescription_card.dart';
import '../widgets/prescription_form_field.dart';

class PrescriptionFormPage extends StatefulWidget {
  const PrescriptionFormPage({super.key, required this.resultFuture});

  final Future<SpeechPipelineResult> resultFuture;

  @override
  State<PrescriptionFormPage> createState() => _PrescriptionFormPageState();
}

class _PrescriptionFormPageState extends State<PrescriptionFormPage> {
  late final List<Prescription> _prescriptions;
  late final TextEditingController _lastNameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _transcriptionController;
  PatientProfile? _patient;
  SpeechPipelineResult? _pipelineResult;
  bool _isProcessing = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _prescriptions = [_blankPrescription()];
    _lastNameController = TextEditingController();
    _firstNameController = TextEditingController();
    _transcriptionController = TextEditingController();
    _loadResult();
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _transcriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadResult() async {
    try {
      final result = await widget.resultFuture;
      if (!mounted) return;
      setState(() {
        _pipelineResult = result;
        _patient = result.patient;
        _prescriptions
          ..clear()
          ..addAll(
            result.prescriptions.isEmpty
                ? [_blankPrescription()]
                : List<Prescription>.from(result.prescriptions),
          );
        _lastNameController.text = result.patient?.lastName ?? '';
        _firstNameController.text = result.patient?.firstName ?? '';
        _transcriptionController.text = result.cleanedTranscript;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Erreur de transcription: $e';
        _isProcessing = false;
      });
    }
  }

  Prescription _blankPrescription() {
    return Prescription(
      libelle: null,
      dci: null,
      dosage: null,
      posologie: null,
      voie: null,
      dispositif: null,
      forme: null,
      duree: null,
      notes: null,
      segmentSource: '',
      segmentSourcePhonetic: '',
    );
  }

  void _addPrescription() {
    setState(() {
      _prescriptions.add(_blankPrescription());
    });
  }

  void _updatePrescription(
    int index, {
    String? libelle,
    String? dci,
    String? dosage,
    String? posologie,
    String? voie,
    String? dispositif,
    String? duree,
    String? notes,
  }) {
    final current = _prescriptions[index];
    _prescriptions[index] = Prescription(
      libelle: libelle ?? current.libelle,
      dci: dci ?? current.dci,
      dosage: dosage ?? current.dosage,
      posologie: posologie ?? current.posologie,
      voie: voie ?? current.voie,
      dispositif: dispositif ?? current.dispositif,
      forme: current.forme,
      duree: duree ?? current.duree,
      notes: notes ?? current.notes,
      segmentSource: current.segmentSource,
      segmentSourcePhonetic: current.segmentSourcePhonetic,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pipelineResult = _pipelineResult;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescription'),
      ),
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
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: PrescriptionFormField(
                          label: 'Nom',
                          controller: _lastNameController,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrescriptionFormField(
                          label: 'Prénom',
                          controller: _firstNameController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Médicaments',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addPrescription,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._prescriptions.asMap().entries.map(
                        (entry) => PrescriptionCard(
                          index: entry.key + 1,
                          prescription: entry.value,
                          drugOptions: drugLexicon,
                          onChanged: ({
                            libelle,
                            dci,
                            dosage,
                            posologie,
                            voie,
                            dispositif,
                            duree,
                            notes,
                          }) {
                            _updatePrescription(
                              entry.key,
                              libelle: libelle,
                              dci: dci,
                              dosage: dosage,
                              posologie: posologie,
                              voie: voie,
                              dispositif: dispositif,
                              duree: duree,
                              notes: notes,
                            );
                          },
                        ),
                      ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _transcriptionController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      isDense: true,
                      hintText: 'Transcription',
                      labelText: 'Transcription',
                    ),
                  ),
                  if (kDebugMode && pipelineResult != null) ...[
                    const SizedBox(height: 20),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Debug transcription',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      children: [
                        _DebugBlock(
                          label: 'Transcription brute',
                          value: pipelineResult.transcript,
                        ),
                        _DebugBlock(
                          label: 'Transcription nettoyée',
                          value: pipelineResult.cleanedTranscript,
                        ),
                        _DebugBlock(
                          label: 'Transcription normalisée',
                          value: pipelineResult.normalizedTranscript,
                        ),
                        _DebugBlock(
                          label: 'Patient',
                          value: pipelineResult.patient == null
                              ? 'null'
                              : const JsonEncoder.withIndent('  ')
                                  .convert(pipelineResult.patient!.toJson()),
                        ),
                        _DebugBlock(
                          label: 'Prescriptions',
                          value: const JsonEncoder.withIndent('  ').convert(
                            pipelineResult.prescriptions
                                .map((p) => p.toJson())
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirmer la prescription'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 72,
                        height: 72,
                        child: CircularProgressIndicator(strokeWidth: 6),
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
        ],
      ),
    );
  }
}

class _DebugBlock extends StatelessWidget {
  const _DebugBlock({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              value.isEmpty ? '(vide)' : value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
