import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/top_notification.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<AuthUser?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<AuthUser?> _loadProfile() {
    return AuthService.instance.fetchUserProfile();
  }

  void _refresh() {
    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  void _showComingSoon(String feature) {
    TopNotification.show(context, '$feature bientot disponible.');
  }

  Future<void> _handleLogout() async {
    final result = await AuthService.instance.logout();
    if (!mounted) return;
    TopNotification.show(context, result.message);
    if (result.success) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: FutureBuilder<AuthUser?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data;
          if (user == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de charger le profil.',
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
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Profil',
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
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor:
                                  colorScheme.primary.withOpacity(0.15),
                              child: Icon(
                                Icons.person,
                                color: colorScheme.primary,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              user.name.isNotEmpty ? user.name : 'Utilisateur',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
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
                    ),
                    const SizedBox(height: 16),
                    _ProfileActionTile(
                      icon: Icons.badge_outlined,
                      label: 'Mes informations',
                      onTap: () => _showComingSoon('Mes informations'),
                    ),
                    _ProfileActionTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Historique des ordonnances',
                      onTap: () =>
                          _showComingSoon('Historique des ordonnances'),
                    ),
                    _ProfileActionTile(
                      icon: Icons.settings_outlined,
                      label: 'Parametres',
                      onTap: () => _showComingSoon('Parametres'),
                    ),
                    _ProfileActionTile(
                      icon: Icons.logout,
                      label: 'Se deconnecter',
                      onTap: _handleLogout,
                    ),
                    const SizedBox(height: 16),
                    _InfoTile(label: 'Nombre de connexions', value: user.loginCount.toString()),
                    if (user.lastLoginAt != null && user.lastLoginAt!.isNotEmpty)
                      _InfoTile(
                        label: 'Derniere connexion',
                        value: user.lastLoginAt!,
                      ),
                  ],
                ),
              ],
            );
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          title: Text(label),
          subtitle: Text(value),
        ),
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
