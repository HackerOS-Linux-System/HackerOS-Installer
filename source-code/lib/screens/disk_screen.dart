import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  void initState() {
    super.initState();
    _loadDisks();
  }

  Future<void> _loadDisks() async {
    setState(() => _loading = true);
    final disks = await ref.read(backendServiceProvider).getDisks();
    if (mounted) {
      setState(() {
        _disks = disks;
        _loading = false;
      });
    }
  }

  void _selectDisk(DiskInfo disk) {
    final state = ref.read(installerProvider);
    final config = state.config;
    final filesystem = config?.filesystem ?? 'ext4';

    ref.read(installerProvider.notifier).setSelectedDisk(disk);

    // Build auto partition plan
    final plan = {
      'disk': disk.path,
      'mode': 'auto',
      'filesystem': filesystem,
      'efi': true,
      'swap': {
        'swap_type': config?.swapType ?? 'zram',
        'size_gb': config?.swapSizeGb ?? 4,
      },
      'partitions': _buildAutoPartitions(filesystem, config),
    };

    ref.read(installerProvider.notifier).setPartitionPlan(plan);
  }

  List<Map<String, dynamic>> _buildAutoPartitions(String fs, InstallerConfig? config) {
    final partitions = <Map<String, dynamic>>[];

    // EFI
    partitions.add({
      'mountpoint': '/boot/efi',
      'size_mb': 512,
      'filesystem': 'fat32',
      'flags': ['esp', 'boot'],
      'btrfs_subvolume': null,
    });

    // Root
    if (fs == 'btrfs') {
      partitions.add({
        'mountpoint': '/',
        'size_mb': null,
        'filesystem': 'btrfs',
        'flags': [],
        'btrfs_subvolume': '@',
      });
    } else {
      partitions.add({
        'mountpoint': '/',
        'size_mb': null,
        'filesystem': fs,
        'flags': [],
        'btrfs_subvolume': null,
      });
    }

    return partitions;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(installerProvider);
    final config = state.config;
    final filesystem = config?.filesystem ?? 'ext4';
    final isGaming   = config?.isGamingEdition   ?? false;
    final isOfficial = config?.isOfficialEdition  ?? false;

    return StepContainer(
      title: 'Storage',
      subtitle: 'Choose where to install HackerOS. This will erase the selected disk.',
      footer: NavButtons(
        onBack: () => ref.read(installerProvider.notifier).prevStep(),
        onNext: () {
          if (state.selectedDisk != null) {
            ref.read(installerProvider.notifier).nextStep();
          }
        },
        nextEnabled: state.selectedDisk != null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filesystem info banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(
                  isGaming   ? Icons.sports_esports_rounded
                  : isOfficial ? Icons.verified_outlined
                  : Icons.folder_outlined,
                  color: isGaming   ? const Color(0xFFFF6B35)
                  : isOfficial ? AppTheme.accentSuccess
                  : AppTheme.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSecondary),
                      children: [
                        const TextSpan(text: 'Filesystem: '),
                        TextSpan(
                          text: filesystem.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            fontFamily: 'JetBrainsMono',
                          ),
                        ),
                        if (isGaming)
                          const TextSpan(text: '  ·  Edycja Gaming: BTRFS z subvolumes dla snapshotów.'),
                          if (isOfficial)
                            const TextSpan(text: '  ·  Edycja Official: czysty system, brak dodatkowych pakietów.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Warning
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentWarning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentWarning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppTheme.accentWarning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The selected disk will be completely erased. Make sure you have backups of important data.',
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      color: AppTheme.accentWarning,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SectionHeader(
            title: 'Available Disks',
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.textMuted),
              onPressed: _loadDisks,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),

          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: LoadingDots(label: 'Detecting disks...'),
            ))
            else if (_disks.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.storage_rounded, color: AppTheme.textMuted, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'No suitable disks found.\nDisks must be at least 8 GB.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Sora', color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadDisks,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              )
              else
                Column(
                  children: _disks.map((disk) {
                    final isSelected = state.selectedDisk?.path == disk.path;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: HCard(
                        selected: isSelected,
                        onTap: () => _selectDisk(disk),
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            // Disk icon
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isSelected
                                ? AppTheme.accent.withOpacity(0.15)
                                : AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                disk.icon,
                                color: isSelected ? AppTheme.accent : AppTheme.textMuted,
                                size: 24,
                              ),
                            ),

                            const SizedBox(width: 16),

                            // Disk info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        disk.model,
                                        style: const TextStyle(
                                          fontFamily: 'Sora',
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _DiskTypeBadge(type: disk.diskType),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${disk.path} · ${disk.sizeHuman}',
                                    style: const TextStyle(
                                      fontFamily: 'JetBrainsMono',
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  if (disk.partitions.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _DiskPartitionBar(disk: disk),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(width: 12),

                            // Size
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  disk.sizeHuman,
                                  style: TextStyle(
                                    fontFamily: 'Sora',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded,
                                             color: AppTheme.accent, size: 20),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                if (state.selectedDisk != null) ...[
                  const SizedBox(height: 20),
                  const SectionHeader(title: 'Partition Layout (Auto)'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                        _PartitionRow(
                          label: '/boot/efi',
                          size: '512 MB',
                          fs: 'FAT32',
                          color: const Color(0xFF6366F1),
                        ),
                        const Divider(color: AppTheme.surfaceBorder, height: 1),
                        _PartitionRow(
                          label: '/',
                          size: 'Remaining',
                          fs: filesystem.toUpperCase(),
                          color: AppTheme.accent,
                          isRoot: true,
                        ),
                        if ((config?.swapType ?? 'zram') == 'zram') ...[
                          const Divider(color: AppTheme.surfaceBorder, height: 1),
                          _PartitionRow(
                            label: 'zram swap',
                            size: '${config?.swapSizeGb ?? 4} GB (virtual)',
                            fs: 'ZRAM',
                            color: AppTheme.accentSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
        ],
      ),
    );
  }
}

class _DiskTypeBadge extends StatelessWidget {
  final String type;
  const _DiskTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'nvme' => ('NVMe', const Color(0xFF6366F1)),
      'ssd' => ('SSD', AppTheme.accentSuccess),
      'usb' => ('USB', AppTheme.accentWarning),
      _ => ('HDD', AppTheme.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DiskPartitionBar extends StatelessWidget {
  final DiskInfo disk;
  const _DiskPartitionBar({required this.disk});

  @override
  Widget build(BuildContext context) {
    if (disk.sizeBytes == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 6,
        color: AppTheme.surfaceElevated,
        child: Row(
          children: disk.partitions.take(6).map((p) {
            final fraction = p['size_bytes'] as int? ?? 0;
            final ratio = fraction / disk.sizeBytes;
            return Flexible(
              flex: (ratio * 1000).toInt().clamp(1, 999),
              child: Container(
                color: _partColor(p['filesystem'] as String? ?? ''),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _partColor(String fs) {
    switch (fs) {
      case 'ext4':
        return AppTheme.accent;
      case 'btrfs':
        return AppTheme.accentSecondary;
      case 'ntfs':
        return const Color(0xFF0078D7);
      case 'vfat':
      case 'fat32':
        return const Color(0xFF6366F1);
      default:
        return AppTheme.textMuted;
    }
  }
}

class _PartitionRow extends StatelessWidget {
  final String label;
  final String size;
  final String fs;
  final Color color;
  final bool isRoot;

  const _PartitionRow({
    required this.label,
    required this.size,
    required this.fs,
    required this.color,
    this.isRoot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 13,
                color: isRoot ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: isRoot ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            size,
            style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              fs,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
