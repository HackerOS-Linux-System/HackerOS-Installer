import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/installer_state.dart';

class DoneScreen extends ConsumerWidget {
  const DoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(installerProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Stack(
        children: [
          // Background glow
          Center(
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentSuccess.withOpacity(0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Success icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.accentSuccess, Color(0xFF059669)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentSuccess.withOpacity(0.4),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 60),
                  )
                      .animate()
                      .scale(duration: 600.ms, curve: Curves.elasticOut)
                      .fade(duration: 400.ms),

                  const SizedBox(height: 36),

                  const Text(
                    'Instalacja zakończona!',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: -1,
                    ),
                  )
                      .animate()
                      .fade(delay: 200.ms, duration: 400.ms)
                      .slideY(begin: 0.2, end: 0),

                  const SizedBox(height: 12),

                  Text(
                    '${state.config?.distroName ?? "HackerOS"} został pomyślnie zainstalowany na Twoim komputerze.',
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 17,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fade(delay: 300.ms, duration: 400.ms),

                  const SizedBox(height: 8),

                  const Text(
                    'Wyjmij nośnik instalacyjny i uruchom ponownie komputer,\naby zacząć korzystać z nowego systemu.',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 14,
                      color: AppTheme.textMuted,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fade(delay: 350.ms, duration: 400.ms),

                  const SizedBox(height: 48),

                  // What's next box
                  Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Co teraz?',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _NextStep(
                          number: '1',
                          text: 'Wyjmij pendrive lub płytę DVD z komputera.',
                        ),
                        _NextStep(
                          number: '2',
                          text: 'Kliknij "Uruchom ponownie" aby zrestartować system.',
                        ),
                        _NextStep(
                          number: '3',
                          text:
                              'Zaloguj się używając nazwy: ${state.username.isNotEmpty ? state.username : "twoja_nazwa"}.',
                        ),
                        _NextStep(
                          number: '4',
                          text: 'Ciesz się swoim nowym systemem HackerOS! 🎉',
                          isLast: true,
                        ),
                      ],
                    ),
                  ).animate().fade(delay: 400.ms, duration: 400.ms).slideY(begin: 0.1, end: 0),

                  const SizedBox(height: 40),

                  // Info chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _InfoChip(
                        icon: Icons.person_rounded,
                        label: state.username.isNotEmpty ? state.username : '—',
                      ),
                      _InfoChip(
                        icon: Icons.computer_rounded,
                        label: state.hostname.isNotEmpty ? state.hostname : '—',
                      ),
                      _InfoChip(
                        icon: Icons.storage_rounded,
                        label: state.selectedDisk?.path ?? '—',
                      ),
                      if (state.config != null)
                        _InfoChip(
                          icon: Icons.info_outline_rounded,
                          label: '${state.config!.distroName} ${state.config!.distroVersion}',
                          color: AppTheme.accent,
                        ),
                    ],
                  ).animate().fade(delay: 450.ms, duration: 400.ms),

                  const SizedBox(height: 40),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => exit(0),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Zamknij instalator'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Process.run('reboot', []);
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 20),
                        label: const Text('Uruchom ponownie'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(200, 52),
                          backgroundColor: AppTheme.accentSuccess,
                        ),
                      ),
                    ],
                  ).animate().fade(delay: 500.ms, duration: 400.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  final String number;
  final String text;
  final bool isLast;

  const _NextStep({
    required this.number,
    required this.text,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentSuccess.withOpacity(0.15),
              border: Border.all(color: AppTheme.accentSuccess.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentSuccess,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color ?? AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
