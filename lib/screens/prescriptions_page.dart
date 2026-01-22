import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/prescription_service.dart';

class PrescriptionsPage extends StatefulWidget {
  const PrescriptionsPage({super.key});

  @override
  State<PrescriptionsPage> createState() => _PrescriptionsPageState();
}

class _PrescriptionsPageState extends State<PrescriptionsPage> {
  late Future<List<Map<String, dynamic>>> _prescriptionsFuture;
  late Future<AuthUser?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _prescriptionsFuture = _loadPrescriptions();
    _profileFuture = _loadProfile();
  }

  Future<List<Map<String, dynamic>>> _loadPrescriptions() {
    return PrescriptionService().fetchPrescriptions();
  }

  Future<AuthUser?> _loadProfile() {
    return AuthService.instance.fetchUserProfile();
  }

  void _refresh() {
    setState(() {
      _prescriptionsFuture = _loadPrescriptions();
      _profileFuture = _loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surface,
                colorScheme.surface.withOpacity(0.6),
              ],
            ),
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _prescriptionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Impossible de charger les ordonnances.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _refresh,
                        child: const Text('Reessayer'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final prescriptions = snapshot.data ?? [];
            if (prescriptions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Aucune ordonnance pour le moment.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _refresh,
                        child: const Text('Rafraichir'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                for (final prescription in prescriptions)
                  _PrescriptionCard(prescription: prescription),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Mes ordonnances',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Rafraichir',
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<AuthUser?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final user = snapshot.data;
            final name =
                user == null || user.name.isEmpty ? 'Medecin' : user.name;
            final email = user == null ? '' : user.email;
            return InkWell(
              onTap: () => Navigator.of(context).pushNamed('/profile'),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colorScheme.primary.withOpacity(0.12),
                      child: Icon(
                        Icons.person,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (email.isNotEmpty)
                            Text(
                              email,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.prescription});

  final Map<String, dynamic> prescription;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final patientName = '${prescription['patient_name'] ?? ''}'.trim();
    final status = '${prescription['status'] ?? 'en attente'}'.trim();
    final createdAt = '${prescription['created_at'] ?? ''}'.trim();
    final medications = prescription['medications'];
    final medicationsCount =
        medications is List ? medications.length : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              patientName.isEmpty ? 'Patient non renseigne' : patientName,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Medicaments: $medicationsCount',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (createdAt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Cree le $createdAt',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
