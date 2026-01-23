import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/auth_service.dart';
import 'whisper_model_loader.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(WhisperModelLoader.warmUp());
  await AuthService.instance.initialize();
  runApp(const TranscareApp());
}
