import 'dart:convert';

import 'local_llm_client.dart';
import 'prescription_engine.dart';

class LlmExtractionResult {
  final PatientProfile? patient;
  final List<Prescription> prescriptions;
  final String rawJson;

  LlmExtractionResult({
    required this.patient,
    required this.prescriptions,
    required this.rawJson,
  });
}

class LlmPrescriptionExtractor {
  LlmPrescriptionExtractor({
    required this.client,
    PatientProfileExtractor? patientFallback,
    RuleBasedExtractor? prescriptionFallback,
  })  : _patientFallback = patientFallback ?? const PatientProfileExtractor(),
        _prescriptionFallback = prescriptionFallback ?? RuleBasedExtractor();

  final LocalLlmClient client;
  final PatientProfileExtractor _patientFallback;
  final RuleBasedExtractor _prescriptionFallback;

  Future<LlmExtractionResult> extract(
    String rawText, {
    String? normalizedText,
    int maxTokens = 256,
    double temperature = 0.1,
  }) async {
    final prompt = _buildPrompt(rawText);
    final response = await client.complete(
      prompt,
      maxTokens: maxTokens,
      temperature: temperature,
    );
    final jsonText = _extractJsonPayload(response);
    final parsed = _decodeJson(jsonText);

    PatientProfile? patient;
    final prescriptions = <Prescription>[];

    if (parsed != null) {
      final patientMap = parsed['patient'];
      if (patientMap is Map<String, dynamic>) {
        patient = _buildPatient(patientMap);
      }

      final list = parsed['prescriptions'];
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            prescriptions.add(_buildPrescription(item));
          }
        }
      }
    }

    final fallbackPatient = patient ??
        _patientFallback.extract(
          rawText,
          normalizedText: normalizedText,
        );
    final fallbackPrescriptions = prescriptions.isEmpty
        ? _prescriptionFallback
            .extract(normalizedText ?? rawText.toLowerCase())
        : prescriptions;

    return LlmExtractionResult(
      patient: fallbackPatient,
      prescriptions: fallbackPrescriptions,
      rawJson: jsonText,
    );
  }

  String _buildPrompt(String rawText) {
    return [
      'Tu es un assistant médical.',
      'Extrait les prescriptions et le profil patient depuis le texte.',
      'Réponds uniquement en JSON valide.',
      'Format attendu :',
      '{',
      '  "patient": {',
      '    "first_name": "...",',
      '    "last_name": "...",',
      '    "gender": "male|female|null",',
      '    "civility": "M.|Mme|Mlle|null",',
      '    "address": "...",',
      '    "city": "...",',
      '    "email": "...",',
      '    "phone": "...",',
      '    "source_text": "..."',
      '  } ou null,',
      '  "prescriptions": [',
      '    {',
      '      "libelle": "...",',
      '      "dci": "...",',
      '      "dosage": "...",',
      '      "posologie": "...",',
      '      "voie": "...",',
      '      "dispositif": "...",',
      '      "forme": null,',
      '      "duree": "...",',
      '      "notes": "...",',
      '      "segment_source": "...",',
      '      "segment_source_phonetic": "..."',
      '    }',
      '  ]',
      '}',
      'Si un champ est inconnu, mets null.',
      'Texte:',
      rawText,
    ].join('\n');
  }

  Map<String, dynamic>? _decodeJson(String payload) {
    if (payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  String _extractJsonPayload(String response) {
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final fenceMatch = fenced.firstMatch(response);
    if (fenceMatch != null) {
      return fenceMatch.group(1)!.trim();
    }

    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return response.substring(start, end + 1).trim();
    }

    return response.trim();
  }

  PatientProfile _buildPatient(Map<String, dynamic> json) {
    String? readString(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return PatientProfile(
      firstName: readString('first_name'),
      lastName: readString('last_name'),
      gender: readString('gender'),
      civility: readString('civility'),
      address: readString('address'),
      city: readString('city'),
      email: readString('email'),
      phone: readString('phone'),
      sourceText: readString('source_text'),
    );
  }

  Prescription _buildPrescription(Map<String, dynamic> json) {
    String? readString(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return Prescription(
      libelle: readString('libelle'),
      dci: readString('dci'),
      dosage: readString('dosage'),
      posologie: readString('posologie'),
      voie: readString('voie'),
      dispositif: readString('dispositif'),
      forme: readString('forme'),
      duree: readString('duree'),
      notes: readString('notes'),
      segmentSource: readString('segment_source') ?? '',
      segmentSourcePhonetic:
          readString('segment_source_phonetic') ?? '',
    );
  }
}
