import 'dart:io' show Process;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/installer_state.dart';

class DoneScreen extends ConsumerWidget {
  const DoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state   = ref.watch(installerProvider);
    final config  = state.config;
    // FIX: username/hostname są String? – użyj ?. i ?? zamiast .isNotEmpty
    final uname   = state.username?.isNotEmpty == true ? state.username! : 'użytkownik';
    final hname   = state.hostname?.isNotEmpty == true ? state.hostname! : 'hackeros';
    // FIX: distroName / distroVersion nie istnieje – używamy editionDisplayName i base
    final sysName = config != null
    ? 'HackerOS ${config.editionDisplayName}'
    : 'HackerOS';

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.bgDark),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Ikona sukcesu
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.success,
                    boxShadow: [BoxShadow(
                      color: AppTheme.accentSuccess.withOpacity(0.4),
                      blurRadius: 40, spreadRadius: 5,
                    )],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 50),
                )
                .animate()
                .scale(duration: 700.ms, curve: Curves.elasticOut)
                .fade(duration: 400.ms),

                const SizedBox(height: 28),

                Text('Instalacja zakończona!', style: const TextStyle(
                  fontFamily: 'Sora', fontSize: 30, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary, letterSpacing: -0.5,
                )).animate().fade(delay: 200.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0),

                const SizedBox(height: 10),

                Text(
                  '$sysName został pomyślnie zainstalowany na Twoim komputerze.',
                  style: const TextStyle(
                    fontFamily: 'Sora', fontSize: 15, color: AppTheme.textSecondary, height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fade(delay: 300.ms, duration: 400.ms),

                const SizedBox(height: 6),

                const Text(
                  'Wyjmij nośnik instalacyjny i uruchom ponownie komputer,\naby zacząć korzystać z nowego systemu.',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 13,
                                   color: AppTheme.textMuted, height: 1.6),
                           textAlign: TextAlign.center,
                ).animate().fade(delay: 350.ms, duration: 400.ms),

                const SizedBox(height: 40),

                // Co teraz?
                Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.surfaceBorder),
                  ),
                  child: Column(children: [
                    const Text('Co teraz?', style: TextStyle(
                      fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    )),
                    const SizedBox(height: 14),
                    _NextStep(number: '1', text: 'Wyjmij pendrive lub płytę DVD z komputera.'),
                    _NextStep(number: '2', text: 'Kliknij "Uruchom ponownie" aby zrestartować system.'),
                    _NextStep(number: '3', text: 'Zaloguj się używając nazwy: $uname.'),
                    _NextStep(number: '4', text: 'Ciesz się nowym systemem HackerOS! 🎉', isLast: true),
                  ]),
                ).animate().fade(delay: 400.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 32),

                // Info chips
                Wrap(
                  spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
                  children: [
                    _InfoChip(icon: Icons.person_rounded, label: uname),
                    _InfoChip(icon: Icons.computer_rounded, label: hname),
                    if (state.selectedDisk != null)
                      _InfoChip(icon: Icons.storage_rounded, label: state.selectedDisk!.path),
                      if (config != null)
                        _InfoChip(
                          icon: Icons.info_outline_rounded,
                          // FIX: używamy editionDisplayName + base zamiast distroName/distroVersion
                          label: 'HackerOS ${config.editionDisplayName} · ${config.base}',
                          color: AppTheme.accent,
                        ),
                  ],
                ).animate().fade(delay: 450.ms, duration: 400.ms),

                const SizedBox(height: 36),

                // Przycisk restartu
                SizedBox(
                  width: 220,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentSuccess,
                      foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                    label: const Text('Uruchom ponownie',
                                      style: TextStyle(fontFamily: 'Sora', fontSize: 14,
                                                       fontWeight: FontWeight.w600)),
                                             onPressed: () async {
                                               await Process.run('reboot', []);
                                             },
                  ),
                ).animate().fade(delay: 500.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  final String number, text;
  final bool   isLast;
  const _NextStep({required this.number, required this.text, this.isLast = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accentSuccess.withOpacity(0.15),
        ),
        child: Center(child: Text(number, style: const TextStyle(
          fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w700,
          color: AppTheme.accentSuccess,
        ))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(
        fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSecondary, height: 1.5,
      ))),
    ]),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color?   color;
  const _InfoChip({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: color?.withOpacity(0.4) ?? AppTheme.surfaceBorder),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? AppTheme.textMuted),
      const SizedBox(width: 7),
      Text(label, style: TextStyle(
        fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w500,
        color: color ?? AppTheme.textSecondary,
      )),
    ]),
  );
}
