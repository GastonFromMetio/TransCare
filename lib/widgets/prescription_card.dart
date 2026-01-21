import 'package:flutter/material.dart';

import '../prescription_engine.dart';
import 'prescription_form_field.dart';

typedef PrescriptionFieldUpdater = void Function({
  String? libelle,
  String? dci,
  String? dosage,
  String? posologie,
  String? voie,
  String? dispositif,
  String? duree,
  String? notes,
});

class PrescriptionCard extends StatefulWidget {
  const PrescriptionCard({
    super.key,
    required this.index,
    required this.prescription,
    required this.drugOptions,
    required this.onChanged,
  });

  final int index;
  final Prescription prescription;
  final List<DrugDef> drugOptions;
  final PrescriptionFieldUpdater onChanged;

  @override
  State<PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends State<PrescriptionCard> {
  late final TextEditingController _dciController;
  late final TextEditingController _dosageController;
  late final TextEditingController _posologieController;
  late final TextEditingController _voieController;
  late final TextEditingController _dispositifController;
  late final TextEditingController _dureeController;
  late final TextEditingController _notesController;
  DrugDef? _selectedDrug;

  @override
  void initState() {
    super.initState();
    _selectedDrug = _findDrug(widget.prescription.libelle);
    _dciController =
        TextEditingController(text: widget.prescription.dci ?? '');
    _dosageController =
        TextEditingController(text: widget.prescription.dosage ?? '');
    _posologieController =
        TextEditingController(text: widget.prescription.posologie ?? '');
    _voieController =
        TextEditingController(text: widget.prescription.voie ?? '');
    _dispositifController =
        TextEditingController(text: widget.prescription.dispositif ?? '');
    _dureeController =
        TextEditingController(text: widget.prescription.duree ?? '');
    _notesController =
        TextEditingController(text: widget.prescription.notes ?? '');
  }

  @override
  void didUpdateWidget(covariant PrescriptionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedDrug = _findDrug(widget.prescription.libelle);
    _syncController(_dciController, widget.prescription.dci);
    _syncController(_dosageController, widget.prescription.dosage);
    _syncController(_posologieController, widget.prescription.posologie);
    _syncController(_voieController, widget.prescription.voie);
    _syncController(_dispositifController, widget.prescription.dispositif);
    _syncController(_dureeController, widget.prescription.duree);
    _syncController(_notesController, widget.prescription.notes);
  }

  @override
  void dispose() {
    _dciController.dispose();
    _dosageController.dispose();
    _posologieController.dispose();
    _voieController.dispose();
    _dispositifController.dispose();
    _dureeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String? value) {
    final next = value ?? '';
    if (controller.text != next) {
      controller.text = next;
    }
  }

  DrugDef? _findDrug(String? key) {
    if (key == null) return null;
    for (final drug in widget.drugOptions) {
      if (drug.key == key) return drug;
    }
    return null;
  }

  void _selectDrug(DrugDef? drug) {
    setState(() {
      _selectedDrug = drug;
    });
    if (drug == null) {
      widget.onChanged(libelle: null);
      return;
    }
    _dciController.text = drug.dci;
    widget.onChanged(libelle: drug.key, dci: drug.dci);
  }

  Widget _twoColumnRow(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prescription ${widget.index}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          _twoColumnRow(
            DropdownButtonFormField<DrugDef>(
              value: _selectedDrug,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Médicament',
                border: UnderlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              items: widget.drugOptions
                  .map(
                    (drug) => DropdownMenuItem<DrugDef>(
                      value: drug,
                      child: Text('${drug.key} (${drug.dci})'),
                    ),
                  )
                  .toList(),
              onChanged: _selectDrug,
            ),
            PrescriptionFormField(
              label: 'DCI',
              controller: _dciController,
              onChanged: (value) => widget.onChanged(dci: value),
            ),
          ),
          const SizedBox(height: 12),
          _twoColumnRow(
            PrescriptionFormField(
              label: 'Dosage',
              controller: _dosageController,
              onChanged: (value) => widget.onChanged(dosage: value),
            ),
            PrescriptionFormField(
              label: 'Posologie',
              controller: _posologieController,
              onChanged: (value) => widget.onChanged(posologie: value),
            ),
          ),
          const SizedBox(height: 12),
          _twoColumnRow(
            PrescriptionFormField(
              label: 'Voie',
              controller: _voieController,
              onChanged: (value) => widget.onChanged(voie: value),
            ),
            PrescriptionFormField(
              label: 'Dispositif',
              controller: _dispositifController,
              onChanged: (value) => widget.onChanged(dispositif: value),
            ),
          ),
          const SizedBox(height: 12),
          _twoColumnRow(
            PrescriptionFormField(
              label: 'Durée',
              controller: _dureeController,
              onChanged: (value) => widget.onChanged(duree: value),
            ),
            PrescriptionFormField(
              label: 'Notes',
              controller: _notesController,
              onChanged: (value) => widget.onChanged(notes: value),
            ),
          ),
          const Divider(height: 32),
        ],
      ),
    );
  }
}
