import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'whisper_model_loader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(WhisperModelLoader.warmUp());
  runApp(const PrescriptionNormalizerApp());
}
