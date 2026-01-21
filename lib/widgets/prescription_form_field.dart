import 'package:flutter/material.dart';

class PrescriptionFormField extends StatelessWidget {
  const PrescriptionFormField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
  });

  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? (initialValue ?? '') : null,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const UnderlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
