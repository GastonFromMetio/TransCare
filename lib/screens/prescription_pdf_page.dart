import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../services/prescription_service.dart';
import 'signature_pad_page.dart';
import 'transcare_shell_page.dart';

class PrescriptionPdfPage extends StatefulWidget {
  const PrescriptionPdfPage({
    super.key,
    required this.prescriptionId,
    this.title,
  });

  final String prescriptionId;
  final String? title;

  @override
  State<PrescriptionPdfPage> createState() => _PrescriptionPdfPageState();
}

class _PrescriptionPdfPageState extends State<PrescriptionPdfPage> {
  bool _isLoading = true;
  String? _error;
  File? _pdfFile;
  bool _didRetryWithSignature = false;
  String? _pdfPath;
  bool _isSignatureMissing = false;
  bool _didRequestSignature = false;
  bool _isValidating = false;
  bool _hasValidated = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isSignatureMissing = false;
      _validationError = null;
    });
    try {
      final signatureReady = await _ensureSignatureReady();
      if (!signatureReady) {
        final didHandle = await _handleMissingSignature();
        if (!didHandle) return;
      }
      final file = await _downloadPdf();
      if (!mounted) return;
      setState(() {
        _pdfFile = file;
        _pdfPath = file.path;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final retried = await _retryWithSignatureIfPossible(error);
      if (retried) {
        return;
      }
      final signatureReady = await _ensureSignatureReady();
      if (!signatureReady) {
        final didHandle = await _handleMissingSignature();
        if (!didHandle) return;
      }
      setState(() {
        _error = 'Recuperation PDF echouee: $error';
        _isLoading = false;
      });
    }
  }

  Future<File> _downloadPdf() async {
    final service = PrescriptionService();
    final bytes = await service.fetchPrescriptionPdfBytes(
      widget.prescriptionId,
    );
    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/prescription_${widget.prescriptionId}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<bool> _retryWithSignatureIfPossible(Object error) async {
    if (_didRetryWithSignature) return false;
    final signatureBase64 =
        await AuthService.instance.loadSignatureBase64();
    if (signatureBase64 == null || signatureBase64.trim().isEmpty) {
      return false;
    }
    final normalized = error.toString().toLowerCase();
    if (!normalized.contains('signature') &&
        !normalized.contains('missing') &&
        !normalized.contains('unauthorized') &&
        !normalized.contains('403') &&
        !normalized.contains('404')) {
      return false;
    }
    try {
      _didRetryWithSignature = true;
      await AuthService.instance.updateSignature(signatureBase64);
      final file = await _downloadPdf();
      if (!mounted) return true;
      setState(() {
        _pdfFile = file;
        _pdfPath = file.path;
        _isLoading = false;
        _error = null;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureSignatureReady() async {
    try {
      final hasSignature = await AuthService.instance.hasSignature();
      if (hasSignature) return true;
    } catch (_) {
      // Ignore and fall back to local signature check.
    }
    final signatureBase64 =
        await AuthService.instance.loadSignatureBase64();
    if (signatureBase64 == null || signatureBase64.trim().isEmpty) {
      return false;
    }
    try {
      await AuthService.instance.updateSignature(signatureBase64);
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<bool> _handleMissingSignature() async {
    if (_didRequestSignature) {
      if (!mounted) return false;
      setState(() {
        _isSignatureMissing = true;
        _isLoading = false;
      });
      return false;
    }
    _didRequestSignature = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SignaturePadPage(),
      ),
    );
    if (!mounted) return false;
    final signatureReady = await _ensureSignatureReady();
    if (!signatureReady) {
      setState(() {
        _isSignatureMissing = true;
        _isLoading = false;
      });
      return false;
    }
    final validated = await _validatePrescription();
    if (!validated) {
      setState(() {
        _isLoading = false;
      });
      return false;
    }
    return true;
  }

  Future<bool> _validatePrescription() async {
    if (_isValidating || _hasValidated) return true;
    setState(() {
      _isValidating = true;
      _validationError = null;
    });
    try {
      final service = PrescriptionService();
      await service.validatePrescription(widget.prescriptionId);
      if (!mounted) return true;
      setState(() {
        _isValidating = false;
        _hasValidated = true;
      });
      await _showValidationSuccess();
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _isValidating = false;
        _validationError = 'Validation echouee: $error';
      });
      return false;
    }
    return false;
  }

  Future<void> _showValidationSuccess() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _ValidationSuccessDialog();
      },
    );
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const TranscareShellPage(initialIndex: 0),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Ordonnance PDF'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_isSignatureMissing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ajoutez votre signature pour generer le PDF.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  _didRequestSignature = false;
                  await _loadPdf();
                },
                child: const Text('Signer maintenant'),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error ?? ''),
        ),
      );
    }
    final file = _pdfFile;
    if (file == null) {
      return const Center(child: Text('PDF indisponible.'));
    }
    final path = _pdfPath ?? file.path;
    if (path.isEmpty) {
      return const Center(child: Text('Chargement du PDF...'));
    }
    return Column(
      children: [
        Expanded(
          child: PDFView(
            filePath: path,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            onError: (error) {
              setState(() {
                _error = 'Affichage PDF echoue: $error';
              });
            },
          ),
        ),
        if (_validationError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _validationError ?? '',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _hasValidated || _isValidating
                  ? null
                  : _validatePrescription,
              child: _isValidating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_hasValidated ? 'Ordonnance validee' : 'Valider'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ValidationSuccessDialog extends StatefulWidget {
  const _ValidationSuccessDialog();

  @override
  State<_ValidationSuccessDialog> createState() =>
      _ValidationSuccessDialogState();
}

class _ValidationSuccessDialogState extends State<_ValidationSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Center(
        child: ScaleTransition(
          scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ordonnance enregistree',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Redirection vers la liste des ordonnances...',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
