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
  Timer? _pollTimer;
  bool _started = false;
  bool _showLogs = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _startInstall();
  }

  Future<void> _startInstall() async {
    if (_started) return;
    _started = true;

    final backend = ref.read(backendServiceProvider);
    await backend.startInstallation();

    // Poll progress every second
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final progress = await backend.getInstallProgress();
      if (progress != null && mounted) {
        ref.read(installerProvider.notifier).updateProgress(progress);

        if (progress.completed || progress.error != null) {
          _pollTimer?.cancel();
          if (progress.completed) {
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) ref.read(installerProvider.notifier).nextStep();
          }
        }

        // Auto-scroll logs
        if (_showLogs) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients) {
              _scrollCtrl.animateTo(
                _scrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
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
    final progress = ref.watch(installerProvider).installProgress;
    final percent = progress?.percent ?? 0;
    final phase = progress?.phase ?? 'not_started';
    final task = progress?.currentTask ?? 'Starting...';
    final hasError = progress?.error != null;

    return Scaffold(
      backgroundColor: AppTheme.bgBase,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Central animation
                  _InstallAnimation(percent: percent, hasError: hasError),

                  const SizedBox(height: 36),

                  // Phase heading
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      hasError
                      ? 'Installation Failed'
                    : percent == 100
                    ? 'Installation Complete!'
                    : 'Installing HackerOS...',
                    key: ValueKey(percent == 100 || hasError),
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Current task
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      hasError ? (progress?.error ?? 'Unknown error') : task,
                      key: ValueKey(task),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 15,
                        color: hasError ? AppTheme.accentDanger : AppTheme.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Progress bar
                  if (!hasError) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percent / 100.0,
                        minHeight: 8,
                        backgroundColor: AppTheme.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          percent == 100 ? AppTheme.accentSuccess : AppTheme.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Phase steps
                  _PhaseSteps(currentPhase: phase),

                  const SizedBox(height: 32),

                  // Log toggle
                  TextButton.icon(
                    onPressed: () => setState(() => _showLogs = !_showLogs),
                    icon: Icon(
                      _showLogs ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                    ),
                    label: Text(_showLogs ? 'Hide Log' : 'Show Log'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textMuted,
                        textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 12),
                    ),
                  ),

                  if (_showLogs) ...[
                    const SizedBox(height: 12),
                    Container(
                      height: 200,
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.bgDeep,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.surfaceBorder),
                      ),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        itemCount: progress?.logLines.length ?? 0,
                        itemBuilder: (_, i) {
                          final line = progress!.logLines[i];
                          return Text(
                            line,
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              height: 1.6,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallAnimation extends StatefulWidget {
  final int percent;
  final bool hasError;

  const _InstallAnimation({required this.percent, required this.hasError});

  @override
  State<_InstallAnimation> createState() => _InstallAnimationState();
}

class _InstallAnimationState extends State<_InstallAnimation>
with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDone = widget.percent == 100;
    final hasError = widget.hasError;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer ring
        if (!isDone && !hasError)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.rotate(
              angle: _ctrl.value * 6.28,
              child: SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: widget.percent / 100.0,
                  strokeWidth: 3,
                  backgroundColor: AppTheme.surface,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                ),
              ),
            ),
          ),

          // Center circle
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasError
                ? [AppTheme.accentDanger, const Color(0xFF991B1B)]
                : isDone
                ? [AppTheme.accentSuccess, const Color(0xFF059669)]
                : [AppTheme.accent, AppTheme.accentSecondary],
              ),
              boxShadow: [
                BoxShadow(
                  color: (hasError
                  ? AppTheme.accentDanger
                  : isDone
                  ? AppTheme.accentSuccess
                  : AppTheme.accent)
                  .withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              hasError
              ? Icons.error_outline_rounded
              : isDone
              ? Icons.check_rounded
              : Icons.download_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
      ],
    );
  }
}

class _PhaseSteps extends StatelessWidget {
  final String currentPhase;

  const _PhaseSteps({required this.currentPhase});

  static const _phases = [
    ('partitioning',          'Partycjonowanie'),
    ('formatting',            'Formatowanie'),
    ('mounting_filesystems',  'Montowanie'),
    ('installing_base',       'System bazowy'),
    ('installing_packages',   'Pakiety'),
    ('configuring_system',    'Konfiguracja'),
    ('installing_bootloader', 'GRUB'),
    ('creating_users',        'Użytkownicy'),
    ('gaming_setup',          'Gaming Setup'),
    ('final_setup',           'Finalizacja'),
    ('complete',              'Gotowe'),
  ];

  int get _currentIndex {
    return _phases.indexWhere((p) => p.$1 == currentPhase);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: _phases.asMap().entries.map((entry) {
        final i = entry.key;
        final phase = entry.value;
        final isDone = i < current;
        final isCurrent = i == current;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDone
            ? AppTheme.accentSuccess.withOpacity(0.15)
            : isCurrent
            ? AppTheme.accent.withOpacity(0.15)
            : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDone
              ? AppTheme.accentSuccess.withOpacity(0.4)
              : isCurrent
              ? AppTheme.accent
              : AppTheme.surfaceBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDone)
                const Icon(Icons.check_rounded, size: 12, color: AppTheme.accentSuccess)
                else if (isCurrent)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  )
                  else
                    const SizedBox(width: 12, height: 12),
                    const SizedBox(width: 5),
                    Text(
                      phase.$2,
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 11,
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                        color: isDone
                        ? AppTheme.accentSuccess
                        : isCurrent
                        ? AppTheme.accent
                        : AppTheme.textMuted,
                      ),
                    ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
