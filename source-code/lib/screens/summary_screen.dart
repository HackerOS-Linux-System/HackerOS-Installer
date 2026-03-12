// summary_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(installerProvider);
    final config = state.config;

    return StepContainer(
      title: 'Summary',
      subtitle: 'Review your choices before installation begins.',
      footer: NavButtons(
        onBack: () => ref.read(installerProvider.notifier).prevStep(),
        onNext: () async {
          // Send all configs to backend then start
          final backend = ref.read(backendServiceProvider);

          if (state.partitionPlan != null) {
            await backend.setPartitionPlan(state.partitionPlan!);
          }

          await backend.setUserConfig({
            'full_name': state.fullName,
            'username': state.username,
            'password': state.password,
            'hostname': state.hostname,
            'autologin': state.autologin,
            'root_password': null,
            'use_same_password_for_root': true,
          });

          ref.read(installerProvider.notifier).nextStep();
        },
        nextLabel: 'Install Now',
        nextColor: AppTheme.accentDanger,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // System
          const SectionHeader(title: 'System'),
          _SummaryCard(
            icon: Icons.computer_outlined,
            items: [
              ('Edition', config?.edition.toUpperCase() ?? '—'),
              ('Base', _baseDisplayName(config?.base ?? 'trixie')),
              ('Desktop', config?.desktopEnvironment.toUpperCase() ?? '—'),
              ('Bootloader', config?.bootloader.toUpperCase() ?? '—'),
            ],
          ),

          const SizedBox(height: 16),
          const SectionHeader(title: 'Language & Region'),
          _SummaryCard(
            icon: Icons.language_rounded,
            items: [
              ('Locale', state.selectedLocale),
              ('Timezone', state.selectedTimezone),
              ('Keyboard', state.selectedKeyboard.toUpperCase()),
            ],
          ),

          const SizedBox(height: 16),
          const SectionHeader(title: 'Storage'),
          _SummaryCard(
            icon: Icons.storage_rounded,
            items: [
              ('Disk', state.selectedDisk?.path ?? '—'),
              ('Model', state.selectedDisk?.model ?? '—'),
              ('Size', state.selectedDisk?.sizeHuman ?? '—'),
              ('Filesystem', _editionFilesystem(config?.edition ?? 'standard')),
              ('Swap', '${config?.swapType?.toUpperCase() ?? 'ZRAM'} (${config?.swapSizeGb ?? 4} GB)'),
            ],
          ),

          const SizedBox(height: 16),
          const SectionHeader(title: 'User Account'),
          _SummaryCard(
            icon: Icons.person_outline_rounded,
            items: [
              ('Full Name', state.fullName),
              ('Username', state.username),
              ('Hostname', state.hostname),
              ('Auto-login', state.autologin ? 'Yes' : 'No'),
            ],
          ),

          const SizedBox(height: 20),

          // Final warning
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentDanger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.accentDanger.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppTheme.accentDanger, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Clicking "Install Now" will start the installation. '
                  'The disk ${state.selectedDisk?.path ?? ""} will be erased. '
                  'This cannot be undone.',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 13,
                    color: AppTheme.accentDanger,
                  ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _baseDisplayName(String base) {
  switch (base.toLowerCase()) {
    case 'trixie':  return 'Debian 13 Trixie (Stable)';
    case 'forky':
    case 'testing': return 'Debian Testing – Forky (Rolling)';
    default:        return base;
  }
}

String _editionFilesystem(String edition) {
  return edition.toLowerCase() == 'gaming' ? 'BTRFS (z subvolumes)' : 'EXT4';
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final List<(String, String)> items;

  const _SummaryCard({required this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        children: items.map((item) {
          final isLast = item == items.last;
          return Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      item.$1,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.$2,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isLast) const Divider(color: AppTheme.surfaceBorder, height: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}
