import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

class DiskScreen extends ConsumerStatefulWidget {
  const DiskScreen({super.key});
  @override
  ConsumerState<DiskScreen> createState() => _DiskScreenState();
}

class _DiskScreenState extends ConsumerState<DiskScreen> {
  List<DiskInfo> _disks = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadDisks(); }

  Future<void> _loadDisks() async {
    setState(() => _loading = true);
    final disks = await ref.read(backendServiceProvider).getDisks();
    if (mounted) setState(() { _disks = disks; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final state   = ref.watch(installerProvider);
    final notifier = ref.read(installerProvider.notifier);
    final config  = state.config;

    return StepContainer(
      title:    'Wybierz dysk',
      subtitle: 'Wybrany dysk zostanie sformatowany. Wszystkie dane zostaną usunięte.',
      footer: NavButtons(
        onBack:      () => notifier.prevStep(),
        onNext:      () => notifier.nextStep(),
        nextEnabled: state.selectedDisk != null,
      ),
      child: _loading
      ? const Center(child: CircularProgressIndicator())
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Info o filesystemie
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppTheme.surfaceBorder),
          ),
          child: Row(children: [
            Icon(
              config?.isGamingEdition == true ? Icons.sports_esports_rounded : Icons.storage_rounded,
              size: 16, color: AppTheme.accent,
            ),
            const SizedBox(width: 10),
            Text(
              config?.isGamingEdition == true
              ? 'Gaming Edition: BTRFS z subvolumes (automatycznie)'
            : 'Official Edition: EXT4 (standardowy)',
            style: const TextStyle(fontFamily: 'Sora', fontSize: 12,
                                   color: AppTheme.textSecondary),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Dostępne dyski'),

        // Lista dysków
        ..._disks.map((disk) {
          final isSelected = state.selectedDisk?.path == disk.path;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () {
                notifier.setSelectedDisk(disk);
                // Ustaw plan partycjonowania
                notifier.setPartitionPlan({
                  'disk': disk.path,
                  'mode': 'auto',
                  'filesystem': config?.filesystem ?? 'ext4',
                  'efi': true,
                  'swap': {
                    'swap_type': config?.swapType ?? 'zram',
                    'size_gb':   config?.swapSizeGb ?? 8,
                  },
                  'partitions': [],
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                  ? AppTheme.accent.withOpacity(0.08)
                  : AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppTheme.accent : AppTheme.surfaceBorder,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                      ? AppTheme.accent.withOpacity(0.15)
                      : AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    // FIX: disk.icon – getter zdefiniowany w DiskInfo
                    child: Icon(
                      disk.icon,
                      color: isSelected ? AppTheme.accent : AppTheme.textMuted,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(disk.model, style: const TextStyle(
                        fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(disk.diskType.toUpperCase(), style: const TextStyle(
                          fontFamily: 'JetBrainsMono', fontSize: 10,
                          color: AppTheme.textMuted,
                        )),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      '${disk.path} · ${disk.sizeHuman}',
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12,
                                             color: AppTheme.textMuted),
                    ),
                    if (disk.partitions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _PartBar(disk: disk),
                    ],
                  ])),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded,
                               color: AppTheme.accent, size: 22),
                ]),
              ),
            ).animate().fade(duration: 300.ms).slideX(begin: 0.05, end: 0),
          );
        }),

        if (_disks.isEmpty && !_loading)
          Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              const Icon(Icons.storage_outlined, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              const Text('Nie znaleziono dysków', style: TextStyle(
                fontFamily: 'Sora', fontSize: 15, color: AppTheme.textMuted,
              )),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadDisks,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Odśwież'),
              ),
            ]),
          )),

          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _loadDisks,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Odśwież listę dysków'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textMuted,
                textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 12)),
          ),
      ]),
    );
  }
}

class _PartBar extends StatelessWidget {
  final DiskInfo disk;
  const _PartBar({required this.disk});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Container(
      height: 6,
      color: AppTheme.surfaceElevated,
      child: Row(
        children: disk.partitions.take(6).map((p) {
          // FIX: używamy p.sizeBytes (pole klasy) zamiast p['size_bytes'] (operator[])
          final frac  = p.sizeBytes;
          final ratio = disk.sizeBytes > 0 ? frac / disk.sizeBytes : 0.1;
          return Flexible(
            flex: (ratio * 1000).toInt().clamp(1, 999),
            // FIX: p.filesystem zamiast p['filesystem']
            child: Container(color: _partColor(p.filesystem)),
          );
        }).toList(),
      ),
    ),
  );

  Color _partColor(String fs) {
    switch (fs.toLowerCase()) {
      case 'fat32':
      case 'vfat':   return AppTheme.accentWarning;
      case 'ext4':   return AppTheme.accent;
      case 'btrfs':  return AppTheme.accentSecondary;
      case 'ntfs':   return const Color(0xFF00BCF2);
      case 'swap':
      case 'linux-swap': return AppTheme.accentDanger;
      default:       return AppTheme.textMuted;
    }
  }
}
