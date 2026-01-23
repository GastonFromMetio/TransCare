import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';

class PrescriptionSubmission {
  const PrescriptionSubmission({
    required this.id,
    required this.payload,
  });

  final String? id;
  final Map<String, dynamic> payload;
}

class PrescriptionPollResult {
  const PrescriptionPollResult({
    required this.isComplete,
    required this.payload,
  });

  final bool isComplete;
  final Map<String, dynamic> payload;
}

class PrescriptionService {
  PrescriptionService({AuthService? authService})
      : _authService = authService ?? AuthService.instance;

  final AuthService _authService;

  Future<PrescriptionSubmission> submitTranscription(String text) async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    final response = await _postJson(
      _authService.baseUrl,
      '/api/prescriptions',
      body: <String, dynamic>{
        'transcribed_text': text,
      },
      token: token,
    );
    final data = _extractData(response);
    final id = _extractId(data) ?? _extractId(response);
    return PrescriptionSubmission(id: id, payload: response);
  }

  Future<PrescriptionPollResult> pollPrescription(String id) async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    final response = await _getJson(
      _authService.baseUrl,
      '/api/prescriptions/$id/poll',
      token: token,
    );
    final data = _extractData(response);
    final isComplete = _isCompletePayload(data);
    return PrescriptionPollResult(isComplete: isComplete, payload: response);
  }

  Future<List<Map<String, dynamic>>> fetchPrescriptions() async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    final response = await _getJson(
      _authService.baseUrl,
      '/api/prescriptions',
      token: token,
    );
    final data = _extractData(response);
    final list = data['prescriptions'] ?? data['items'] ?? data['data'];
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> fetchPrescription(String id) async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    return _getJson(
      _authService.baseUrl,
      '/api/prescriptions/$id',
      token: token,
    );
  }

  Future<Map<String, dynamic>> updatePrescription(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    return _patchJson(
      _authService.baseUrl,
      '/api/prescriptions/$id',
      body: payload,
      token: token,
    );
  }

  Future<Map<String, dynamic>> validatePrescription(String id) async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    return _postEmpty(
      _authService.baseUrl,
      '/api/prescriptions/$id/validate',
      token: token,
    );
  }

  Future<Uint8List> fetchPrescriptionPdfBytes(String id) async {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw StateError('Authentification requise.');
    }
    return _getBytes(
      _authService.baseUrl,
      '/api/prescriptions/$id/pdf',
      token: token,
    );
  }
}

Map<String, dynamic> _extractData(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is Map<String, dynamic>) return data;
  return payload;
}

String? _extractId(Map<String, dynamic> payload) {
  final prescription = payload['prescription'];
  final nestedId = prescription is Map<String, dynamic> ? prescription['id'] : null;
  final id = payload['id'] ??
      payload['prescription_id'] ??
      payload['prescriptionId'] ??
      payload['uuid'] ??
      nestedId;
  if (id == null) return null;
  return '$id';
}

bool _isCompletePayload(Map<String, dynamic> payload) {
  final ready = payload['ready'];
  if (ready is bool) {
    return ready;
  }
  final status = payload['status'] ?? payload['state'];
  if (status is String) {
    final normalized = status.toLowerCase();
    if (normalized.contains('processing') ||
        normalized.contains('pending') ||
        normalized.contains('waiting')) {
      return false;
    }
    if (normalized.contains('done') ||
        normalized.contains('ready') ||
        normalized.contains('complete')) {
      return true;
    }
  }
  if (payload['prescription'] != null || payload['result'] != null) {
    return true;
  }
  return false;
}

Future<Map<String, dynamic>> _postJson(
  String baseUrl,
  String path, {
  required Map<String, dynamic> body,
  String? token,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path');
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    debugPrint('POST $uri');
    debugPrint('Request body: ${jsonEncode(body)}');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final status = response.statusCode;
    debugPrint('Response $status from $uri');
    debugPrint('Response body: $text');
    if (status < 200 || status >= 300) {
      throw HttpException('HTTP $status: $text', uri: uri);
    }
    if (text.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _getJson(
  String baseUrl,
  String path, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path');
    final request = await client.getUrl(uri);
    request.headers.contentType = ContentType.json;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    debugPrint('GET $uri');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final status = response.statusCode;
    debugPrint('Response $status from $uri');
    debugPrint('Response body: $text');
    if (status < 200 || status >= 300) {
      throw HttpException('HTTP $status: $text', uri: uri);
    }
    if (text.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _patchJson(
  String baseUrl,
  String path, {
  required Map<String, dynamic> body,
  String? token,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path');
    final request = await client.patchUrl(uri);
    request.headers.contentType = ContentType.json;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    debugPrint('PATCH $uri');
    debugPrint('Request body: ${jsonEncode(body)}');
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final status = response.statusCode;
    debugPrint('Response $status from $uri');
    debugPrint('Response body: $text');
    if (status < 200 || status >= 300) {
      throw HttpException('HTTP $status: $text', uri: uri);
    }
    if (text.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _getBytes(
  String baseUrl,
  String path, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path');
    final request = await client.getUrl(uri);
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.set(HttpHeaders.acceptHeader, 'application/pdf');
    debugPrint('GET $uri');
    final response = await request.close();
    final status = response.statusCode;
    final bytes = await consolidateHttpClientResponseBytes(response);
    debugPrint('Response $status from $uri');
    if (status < 200 || status >= 300) {
      final text = utf8.decode(bytes, allowMalformed: true);
      throw HttpException('HTTP $status: $text', uri: uri);
    }
    return bytes;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _postEmpty(
  String baseUrl,
  String path, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path');
    final request = await client.postUrl(uri);
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    debugPrint('POST $uri (no body)');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final status = response.statusCode;
    debugPrint('Response $status from $uri');
    debugPrint('Response body: $text');
    if (status < 200 || status >= 300) {
      throw HttpException('HTTP $status: $text', uri: uri);
    }
    if (text.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  } finally {
    client.close(force: true);
  }
}
