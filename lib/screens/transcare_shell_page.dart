import 'package:flutter/material.dart';

import 'prescriptions_page.dart';
import 'transcare_home_page.dart';

class TranscareShellPage extends StatefulWidget {
  const TranscareShellPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<TranscareShellPage> createState() => _TranscareShellPageState();
}

class _TranscareShellPageState extends State<TranscareShellPage> {
  late int _currentIndex;
  final GlobalKey<PrescriptionsPageState> _prescriptionsKey =
      GlobalKey<PrescriptionsPageState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 1);
  }

  void _setIndex(int index) {
    if (index == 0) {
      _prescriptionsKey.currentState?.refreshOnReturn();
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            PrescriptionsPage(key: _prescriptionsKey),
            const TranscareHomePage(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Ordonnances',
                  isActive: _currentIndex == 0,
                  onTap: () => _setIndex(0),
                ),
                const SizedBox(width: 8),
                _NavItem(
                  icon: Icons.mic_none,
                  label: 'Nouvelle',
                  isActive: _currentIndex == 1,
                  onTap: () => _setIndex(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
