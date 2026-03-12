import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/installer_state.dart';
import '../services/backend_service.dart';
import 'locale_screen.dart';
import 'network_screen.dart';
import 'disk_screen.dart';
import 'user_screen.dart';
import 'summary_screen.dart';
import 'install_screen.dart';
import 'done_screen.dart';

class InstallerShell extends ConsumerWidget {
  const InstallerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(installerProvider);
    final config = state.config;
    final steps = getInstallerSteps(config);

    Widget currentScreen;
    switch (steps[state.currentStep].id) {
      case 'locale':
        currentScreen = const LocaleScreen();
        break;
      case 'network':
        currentScreen = const NetworkScreen();
        break;
      case 'disk':
        currentScreen = const DiskScreen();
        break;
      case 'user':
        currentScreen = const UserScreen();
        break;
      case 'summary':
        currentScreen = const SummaryScreen();
        break;
      case 'install':
        currentScreen = const InstallScreen();
        break;
      case 'done':
        currentScreen = const DoneScreen();
        break;
      default:
        currentScreen = const LocaleScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Row(
        children: [
          // Sidebar
          _InstallerSidebar(steps: steps, currentStep: state.currentStep),

          // Content area
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgBase,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.surfaceBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.02, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(parent: animation, curve: Curves.easeOut),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(state.currentStep),
                    child: currentScreen,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallerSidebar extends ConsumerWidget {
  final List<InstallerStep> steps;
  final int currentStep;

  const _InstallerSidebar({
    required this.steps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(installerProvider).config;

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 32),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.accent, AppTheme.accentSecondary],
                    ),
                  ),
                  child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  config?.distroName ?? 'HackerOS',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Steps
          Expanded(
            child: ListView.builder(
              itemCount: steps.length,
              itemBuilder: (context, index) {
                final step = steps[index];
                final isDone = index < currentStep;
                final isCurrent = index == currentStep;
                final isLocked = index > currentStep;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _SidebarStep(
                    step: step,
                    index: index,
                    isDone: isDone,
                    isCurrent: isCurrent,
                    isLocked: isLocked,
                  ),
                );
              },
            ),
          ),

          // Footer
          const Divider(color: AppTheme.surfaceBorder),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                config != null ? '${config.base} (${config.edition})' : 'Loading...',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarStep extends StatelessWidget {
  final InstallerStep step;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final bool isLocked;

  const _SidebarStep({
    required this.step,
    required this.index,
    required this.isDone,
    required this.isCurrent,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? AppTheme.accent.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            // Step indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? AppTheme.accentSuccess
                    : isCurrent
                        ? AppTheme.accent
                        : AppTheme.surface,
                border: Border.all(
                  color: isDone
                      ? AppTheme.accentSuccess
                      : isCurrent
                          ? AppTheme.accent
                          : AppTheme.surfaceBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? Colors.white : AppTheme.textMuted,
                        ),
                      ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                      color: isLocked
                          ? AppTheme.textMuted
                          : isCurrent
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                    ),
                  ),
                  if (isCurrent)
                    Text(
                      step.subtitle,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 11,
                        color: AppTheme.accent,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
