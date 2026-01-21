import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prescription_normalizer/services/auth_service.dart';

class _TestServer {
  _TestServer(this.server);

  final HttpServer server;
  String? lastAuthHeader;
  Map<String, dynamic>? lastBody;

  String get baseUrl => 'http://${server.address.address}:${server.port}';

  Future<void> close() async {
    await server.close(force: true);
  }
}

Future<_TestServer> _startServer(
  Future<void> Function(HttpRequest request, _TestServer serverState) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final state = _TestServer(server);
  server.listen((request) async {
    await handler(request, state);
  });
  return state;
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  if (body.isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  return <String, dynamic>{'data': decoded};
}

void main() {
  test('login success returns token and user', () async {
    final server = await _startServer((request, state) async {
      expect(request.uri.path, '/api/auth/login');
      state.lastBody = await _readJson(request);
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'token': 'token-123',
          'user': <String, dynamic>{
            'id': 3,
            'name': 'Jean',
            'email': 'jean@example.com',
            'login_count': 2,
          },
        }),
      );
      await request.response.close();
    });
    addTearDown(server.close);

    final service = AuthService(baseUrl: server.baseUrl);
    final result = await service.login(
      email: 'jean@example.com',
      password: 'secret',
    );

    expect(result.success, isTrue);
    expect(result.token, 'token-123');
    expect(result.user?.email, 'jean@example.com');
    expect(result.user?.loginCount, 2);
    expect(server.lastBody?['email'], 'jean@example.com');

  });

  test('signup success returns token and user', () async {
    final server = await _startServer((request, state) async {
      expect(request.uri.path, '/api/auth/register');
      state.lastBody = await _readJson(request);
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{
          'access_token': 'signup-token',
          'data': <String, dynamic>{
            'id': 7,
            'full_name': 'Aline',
            'email': 'aline@example.com',
            'login_count': '0',
          },
        }),
      );
      await request.response.close();
    });
    addTearDown(server.close);

    final service = AuthService(baseUrl: server.baseUrl);
    final result = await service.signUp(
      name: 'Aline',
      email: 'aline@example.com',
      password: 'password123',
    );

    expect(result.success, isTrue);
    expect(result.token, 'signup-token');
    expect(result.user?.name, 'Aline');
    expect(result.user?.loginCount, 0);
    expect(server.lastBody?['name'], 'Aline');
    expect(server.lastBody?['password_confirmation'], 'password123');
  });

  test('logout sends bearer token and clears state', () async {
    final server = await _startServer((request, state) async {
      if (request.uri.path == '/api/auth/login') {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'token': 'logout-token',
            'user': <String, dynamic>{
              'id': 1,
              'name': 'Mina',
              'email': 'mina@example.com',
              'login_count': 1,
            },
          }),
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/api/auth/logout') {
        state.lastAuthHeader =
            request.headers.value(HttpHeaders.authorizationHeader);
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
    addTearDown(server.close);

    final service = AuthService(baseUrl: server.baseUrl);
    final loginResult = await service.login(
      email: 'mina@example.com',
      password: 'secret',
    );
    expect(loginResult.success, isTrue);

    final logoutResult = await service.logout();
    expect(logoutResult.success, isTrue);
    expect(server.lastAuthHeader, 'Bearer logout-token');

  });

  test('login fails on server error', () async {
    final server = await _startServer((request, state) async {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, dynamic>{'message': 'Invalid credentials'}),
      );
      await request.response.close();
    });
    addTearDown(server.close);

    final service = AuthService(baseUrl: server.baseUrl);
    final result = await service.login(
      email: 'fail@example.com',
      password: 'bad',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('HTTP 401'));

  });

  test('login blocked when API base url is missing', () async {
    final service = AuthService(baseUrl: '');
    final result = await service.login(
      email: 'nope@example.com',
      password: 'secret',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('Serveur indisponible'));
  });
}
