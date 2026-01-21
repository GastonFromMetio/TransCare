import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AuthResult {
  const AuthResult({
    required this.success,
    required this.message,
    this.token,
    this.user,
  });

  final bool success;
  final String message;
  final String? token;
  final AuthUser? user;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.loginCount,
    this.lastLoginAt,
  });

  final String id;
  final String name;
  final String email;
  final int loginCount;
  final String? lastLoginAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: '${json['id'] ?? json['user_id'] ?? ''}',
      name: '${json['name'] ?? json['full_name'] ?? ''}',
      email: '${json['email'] ?? ''}',
      loginCount: _parseInt(json['login_count']) ?? 0,
      lastLoginAt: json['last_login_at']?.toString(),
    );
  }
}

class AuthService {
  AuthService({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultBaseUrl;

  static final instance = AuthService();
  static const String _defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://transcare.713.fr');
  static const bool _allowGuestAccess = false;

  final String _baseUrl;
  String? _token;

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    if (_baseUrl.isEmpty) {
      return const AuthResult(
        success: false,
        message: 'Serveur indisponible. Utilise "Continuer sans compte".',
      );
    }

    try {
      final response = await _postJson(
        _baseUrl,
        '/api/auth/login',
        body: <String, dynamic>{
          'email': email,
          'password': password,
        },
      );
      debugPrint('Auth login response: $response');
      final token = _extractToken(response);
      final user = _extractUser(response);
      if (token == null || token.isEmpty) {
        return const AuthResult(
          success: false,
          message: 'Token manquant dans la reponse.',
        );
      }
      _token = token;
      return AuthResult(
        success: true,
        message: 'Connexion reussie.',
        token: token,
        user: user,
      );
    } catch (error) {
      if (_allowGuestAccess) {
        return AuthResult(
          success: true,
          message: 'Connexion ignoree (mode invite): $error',
        );
      }
      return AuthResult(
        success: false,
        message: 'Connexion echouee: $error',
      );
    }
  }

  Future<AuthResult> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (_baseUrl.isEmpty) {
      return const AuthResult(
        success: false,
        message: 'Serveur indisponible. Utilise "Continuer sans compte".',
      );
    }

    try {
      final response = await _postJson(
        _baseUrl,
        '/api/auth/register',
        body: <String, dynamic>{
          'name': name,
          'email': email,
          'password': password,
          'password_confirmation': password,
        },
      );
      debugPrint('Auth signup response: $response');
      final token = _extractToken(response);
      final user = _extractUser(response);
      if (token == null || token.isEmpty) {
        return const AuthResult(
          success: false,
          message: 'Token manquant dans la reponse.',
        );
      }
      _token = token;
      return AuthResult(
        success: true,
        message: 'Inscription reussie.',
        token: token,
        user: user,
      );
    } catch (error) {
      if (_allowGuestAccess) {
        return AuthResult(
          success: true,
          message: 'Inscription ignoree (mode invite): $error',
        );
      }
      return AuthResult(
        success: false,
        message: 'Inscription echouee: $error',
      );
    }
  }

  Future<AuthResult> logout() async {
    if (_baseUrl.isEmpty || _token == null) {
      _token = null;
      return const AuthResult(
        success: true,
        message: 'Deconnexion locale.',
      );
    }

    try {
      await _postJson(
        _baseUrl,
        '/api/auth/logout',
        body: const <String, dynamic>{},
        token: _token,
      );
      _token = null;
      return const AuthResult(
        success: true,
        message: 'Deconnexion reussie.',
      );
    } catch (error) {
      if (_allowGuestAccess) {
        _token = null;
        return AuthResult(
          success: true,
          message: 'Deconnexion locale (mode invite): $error',
        );
      }
      return AuthResult(
        success: false,
        message: 'Deconnexion echouee: $error',
      );
    }
  }

  Future<AuthUser?> fetchUserProfile() async {
    if (_baseUrl.isEmpty || _token == null) {
      return null;
    }
    try {
      final response = await _getJson(_baseUrl, '/api/auth/user', token: _token);
      return _extractUser(response);
    } catch (_) {
      return null;
    }
  }
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
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final status = response.statusCode;
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
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final status = response.statusCode;
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

String? _extractToken(Map<String, dynamic> payload) {
  final token = payload['token'] ??
      payload['access_token'] ??
      (payload['data'] is Map<String, dynamic>
          ? (payload['data'] as Map<String, dynamic>)['token']
          : null);
  if (token is String) return token;
  return null;
}

AuthUser? _extractUser(Map<String, dynamic> payload) {
  final user = payload['user'] ??
      (payload['data'] is Map<String, dynamic>
          ? (payload['data'] as Map<String, dynamic>)['user']
          : null) ??
      payload['data'];
  if (user is Map<String, dynamic>) return AuthUser.fromJson(user);
  return null;
}

int? _parseInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
