import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/auth_service.dart';
import '../widgets/top_notification.dart';

class SignaturePadPage extends StatefulWidget {
  const SignaturePadPage({super.key});

  @override
  State<SignaturePadPage> createState() => _SignaturePadPageState();
}

class _SignaturePadPageState extends State<SignaturePadPage> {
  final GlobalKey _paintKey = GlobalKey();
  final List<Offset?> _points = [];
  bool _isSaving = false;
  String? _savedBase64;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final value = await AuthService.instance.loadSignatureBase64();
    if (!mounted) return;
    setState(() {
      _savedBase64 = value;
    });
  }

  Future<void> _saveSignature() async {
    if (_points.whereType<Offset>().isEmpty) {
      TopNotification.show(context, 'Signature vide.');
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final boundary =
          _paintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Canvas indisponible.');
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Capture PNG impossible.');
      }
      final bytes = byteData.buffer.asUint8List();
      final base64 = base64Encode(bytes);
      await AuthService.instance.updateSignature(base64);
      await AuthService.instance.saveSignatureBase64(base64);
      if (!mounted) return;
      setState(() {
        _savedBase64 = base64;
        _isSaving = false;
      });
      TopNotification.show(context, 'Signature enregistree.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      TopNotification.show(context, 'Enregistrement echoue: $error');
    }
  }

  void _addPoint(Offset globalPosition, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final localPosition = box?.globalToLocal(globalPosition);
    if (localPosition == null) return;
    setState(() {
      _points.add(localPosition);
    });
  }

  void _clearSignature() {
    setState(() {
      _points.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signature'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Signez avec votre doigt sur l\'ecran.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.25),
                ),
              ),
              child: Builder(
                builder: (context) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _addPoint(details.globalPosition, context),
                    onPanUpdate: (details) =>
                        _addPoint(details.globalPosition, context),
                    onPanEnd: (_) {
                      setState(() {
                        _points.add(null);
                      });
                    },
                    child: RepaintBoundary(
                      key: _paintKey,
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          points: List<Offset?>.unmodifiable(_points),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _clearSignature,
                    child: const Text('Effacer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _isSaving ? null : _saveSignature,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_savedBase64 != null && _savedBase64!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signature actuelle',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.15),
                      ),
                    ),
                    child: Center(
                      child: Image.memory(
                        base64Decode(_savedBase64!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.points});

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < points.length - 1; i += 1) {
      final current = points[i];
      final next = points[i + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, paint);
      } else if (current != null && next == null) {
        canvas.drawPoints(ui.PointMode.points, [current], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
