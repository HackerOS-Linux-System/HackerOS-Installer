import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

class InstallScreen extends ConsumerStatefulWidget {
  const InstallScreen({super.key});
  @override
  ConsumerState<InstallScreen> createState() => _InstallScreenState();
}

class _InstallScreenState extends ConsumerState<InstallScreen> {
  Timer?  _pollTimer;
  bool    _started   = false;
  bool    _showLogs  = false;
  final   _scrollCtrl = ScrollController();

  @override
  void initState() { super.initState(); _startInstall(); }

  Future<void> _startInstall() async {
    if (_started) return;
    _started = true;

    final backend = ref.read(backendServiceProvider);
    await backend.startInstallation();

    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final progress = await backend.getInstallProgress();
      // FIX: getInstallProgress zwraca InstallProgress? – sprawdź != null
      if (progress != null && mounted) {
        // FIX: updateProgress – metoda zdefiniowana w InstallerNotifier
        ref.read(installerProvider.notifier).updateProgress(progress);

        if (progress.completed || progress.error != null) {
          _pollTimer?.cancel();
          if (progress.completed) {
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) ref.read(installerProvider.notifier).nextStep();
          }
        }

        if (_showLogs) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
                                    duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIX: installProgress z InstallerState (dodane pole)
    final progress = ref.watch(installerProvider).installProgress;
    final percent  = progress?.percent      ?? 0;
    final phase    = progress?.phase        ?? 'not_started';
    final task     = progress?.currentTask  ?? 'Uruchamianie...';
    final hasError = progress?.error != null;
    final logs     = progress?.logLines     ?? [];

    return Scaffold(
      backgroundColor: AppTheme.bgBase,
      body: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.settings_rounded, color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
              Text('Instalacja', style: Theme.of(context).textTheme.headlineLarge),
            ]),
            const SizedBox(height: 6),
            const Text('Nie wyłączaj komputera ani nie odłączaj zasilania.',
                       style: TextStyle(fontFamily: 'Sora', fontSize: 13,
                                        color: AppTheme.textSecondary)),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Progress bar
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_phaseDisplayName(phase), style: const TextStyle(
                    fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  )),
                  Text('$percent%', style: const TextStyle(
                    fontFamily: 'JetBrainsMono', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppTheme.accent,
                  )),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    backgroundColor: AppTheme.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      hasError ? AppTheme.accentDanger : AppTheme.accent,
                    ),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 10),
                Text(task, style: const TextStyle(
                  fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSecondary,
                )),
              ]),

              if (hasError) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accentDanger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentDanger.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.accentDanger, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(progress!.error!,
                                         style: const TextStyle(fontFamily: 'Sora', fontSize: 12,
                                                                color: AppTheme.accentDanger))),
                  ]),
                ),
              ],

              const SizedBox(height: 24),

              // Fazy
              _PhaseList(currentPhase: phase),

              const SizedBox(height: 20),

              // Logi
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Logi instalacji', style: TextStyle(
                  fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                )),
                TextButton(
                  onPressed: () => setState(() => _showLogs = !_showLogs),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent, minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 12)),
                      child: Text(_showLogs ? 'Ukryj' : 'Pokaż'),
                ),
              ]),

              if (_showLogs)
                Container(
                  height: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgDeep,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppTheme.surfaceBorder),
                  ),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    itemCount: logs.length,
                    itemBuilder: (_, i) => Text(logs[i], style: const TextStyle(
                      fontFamily: 'JetBrainsMono', fontSize: 11,
                      color: AppTheme.textSecondary, height: 1.5,
                    )),
                  ),
                ).animate().fade(duration: 200.ms),
            ]),
          ),
        ),
      ]),
    );
  }

  String _phaseDisplayName(String phase) {
    const m = {
      'not_started':          'Oczekiwanie...',
      'partitioning':         'Partycjonowanie dysku',
      'formatting':           'Formatowanie partycji',
      'mounting_filesystems': 'Montowanie systemów plików',
      'installing_base':      'Instalowanie systemu bazowego',
      'installing_packages':  'Instalowanie pakietów',
      'configuring_system':   'Konfigurowanie systemu',
      'installing_bootloader':'Instalowanie GRUB',
      'creating_users':       'Tworzenie kont użytkowników',
      'gaming_setup':         'Konfigurowanie środowiska gaming',
      'final_setup':          'Finalizacja',
      'complete':             'Instalacja zakończona!',
      'failed':               'Błąd instalacji',
    };
    return m[phase] ?? phase;
  }
}

class _PhaseList extends StatelessWidget {
  final String currentPhase;
  const _PhaseList({required this.currentPhase});

  static const _phases = [
    ('partitioning',          'Partycjonowanie'),
    ('formatting',            'Formatowanie'),
    ('mounting_filesystems',  'Montowanie FS'),
    ('installing_base',       'System bazowy'),
    ('installing_packages',   'Pakiety'),
    ('configuring_system',    'Konfiguracja'),
    ('installing_bootloader', 'Bootloader'),
    ('creating_users',        'Użytkownicy'),
    ('gaming_setup',          'Gaming setup'),
    ('final_setup',           'Finalizacja'),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = _phases.indexWhere((p) => p.$1 == currentPhase);
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: _phases.asMap().entries.map((e) {
        final done    = e.key < idx;
        final current = e.key == idx;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: done    ? AppTheme.accentSuccess.withOpacity(0.12)
            : current ? AppTheme.accent.withOpacity(0.15)
            : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: done    ? AppTheme.accentSuccess.withOpacity(0.4)
              : current ? AppTheme.accent.withOpacity(0.5)
              : AppTheme.surfaceBorder,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (done)
              const Icon(Icons.check_rounded, size: 11, color: AppTheme.accentSuccess)
              else if (current)
                const SizedBox(width: 11, height: 11,
                               child: CircularProgressIndicator(strokeWidth: 1.5,
                                                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent))),
                                                                const SizedBox(width: 5),
                                                                Text(e.value.$2, style: TextStyle(
                                                                  fontFamily: 'Sora', fontSize: 11,
                                                                  color: done    ? AppTheme.accentSuccess
                                                                  : current ? AppTheme.accent
                                                                  : AppTheme.textMuted,
                                                                  fontWeight: current ? FontWeight.w600 : FontWeight.normal,
                                                                )),
          ]),
        );
      }).toList(),
    );
  }
}
