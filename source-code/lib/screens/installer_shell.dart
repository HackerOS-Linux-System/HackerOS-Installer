import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/installer_state.dart';
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
    final lang  = state.installerLanguage;
    // FIX: buildSteps() z installer_state.dart (nie getInstallerSteps)
    final steps = buildSteps();

    final stepId = steps[state.currentStep.clamp(0, steps.length - 1)].id;

    Widget screen;
    switch (stepId) {
      case 'locale':  screen = const LocaleScreen();   break;
      case 'network': screen = const NetworkScreen();  break;
      case 'disk':    screen = const DiskScreen();     break;
      case 'user':    screen = const UserScreen();     break;
      case 'summary': screen = const SummaryScreen();  break;
      case 'install': screen = const InstallScreen();  break;
      case 'done':    screen = const DoneScreen();     break;
      default:        screen = const LocaleScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Row(children: [
        _Sidebar(steps: steps, currentStep: state.currentStep, lang: lang),
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
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.02, 0), end: Offset.zero)
                    .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(state.currentStep), child: screen),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Sidebar ─────────────────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  final List<InstallerStep> steps;
  final int    currentStep;
  final String lang;
  const _Sidebar({required this.steps, required this.currentStep, required this.lang});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config  = ref.watch(installerProvider).config;
    final edition = config?.edition ?? 'gaming';

    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Logo
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 28),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.forEdition(edition),
              ),
              child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 9),
            // FIX: distroName usunięte – zawsze "HackerOS"
            const Text('HackerOS', style: TextStyle(
              fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            )),
          ]),
        ),

        // Kroki
        Expanded(
          child: ListView.builder(
            itemCount: steps.length,
            itemBuilder: (_, i) {
              final step = steps[i];
              final isDone    = i < currentStep;
              final isCurrent = i == currentStep;
              final isLocked  = i > currentStep;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _SidebarStep(
                  // FIX: step.title(lang) i step.subtitle(lang) są metodami
                  label:     step.title(lang),
                  subtitle:  step.subtitle(lang),
                  index:     i,
                  isDone:    isDone,
                  isCurrent: isCurrent,
                  isLocked:  isLocked,
                ),
              );
            },
          ),
        ),

        const Divider(color: AppTheme.surfaceBorder),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            config != null ? '${config.base} · ${config.edition}' : 'Ładowanie...',
            style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textMuted),
          ),
        ]),
      ]),
    );
  }
}

class _SidebarStep extends StatelessWidget {
  final String label, subtitle;
  final int    index;
  final bool   isDone, isCurrent, isLocked;

  const _SidebarStep({
    required this.label, required this.subtitle, required this.index,
    required this.isDone, required this.isCurrent, required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: isCurrent ? AppTheme.accent.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone    ? AppTheme.accentSuccess
              : isCurrent ? AppTheme.accent
              : AppTheme.surface,
              border: Border.all(
                color: isDone    ? AppTheme.accentSuccess
                : isCurrent ? AppTheme.accent
                : AppTheme.surfaceBorder,
                width: 1.5,
              ),
            ),
            child: Center(
              child: isDone
              ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
              : Text('${index + 1}', style: TextStyle(
                fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w700,
                color: isCurrent ? Colors.white : AppTheme.textMuted,
              )),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontFamily: 'Sora', fontSize: 12,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              color: isLocked   ? AppTheme.textMuted
              : isCurrent  ? AppTheme.textPrimary
              : AppTheme.textSecondary,
            )),
            if (isCurrent && subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(
                fontFamily: 'Sora', fontSize: 10, color: AppTheme.accent,
              )),
          ])),
        ]),
      ),
    );
  }
}
