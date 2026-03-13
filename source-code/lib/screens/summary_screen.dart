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
    final state  = ref.watch(installerProvider);
    final config = state.config;

    return StepContainer(
      title:    'Podsumowanie',
      subtitle: 'Sprawdź konfigurację przed instalacją.',
      footer: NavButtons(
        onBack: () => ref.read(installerProvider.notifier).prevStep(),
        onNext: () async {
          final backend = ref.read(backendServiceProvider);
          if (state.partitionPlan != null) {
            await backend.setPartitionPlan(state.partitionPlan!);
          }
          await backend.setUserConfig({
            'full_name': state.fullName   ?? '',
            'username':  state.username   ?? '',
            'password':  state.password   ?? '',
            'hostname':  state.hostname   ?? 'hackeros',
            'autologin': state.autologin,
            'root_password': null,
            'use_same_password_for_root': true,
          });
          ref.read(installerProvider.notifier).nextStep();
        },
        nextLabel: 'Zainstaluj teraz',
        nextColor: AppTheme.accentDanger,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        const SectionHeader(title: 'System'),
        _SummaryCard(icon: Icons.computer_outlined, items: [
          ('Edycja',     config?.editionDisplayName ?? '—'),
          ('Baza',       _baseDisplayName(config?.base ?? 'trixie')),
          ('Pulpit',     config?.desktopEnvironment.toUpperCase() ?? '—'),
          // FIX: config.bootloader istnieje w InstallerConfig
          ('Bootloader', config?.bootloader.toUpperCase() ?? '—'),
        ]),

        const SizedBox(height: 16),
        const SectionHeader(title: 'Język i region'),
        _SummaryCard(icon: Icons.language_rounded, items: [
          // FIX: String? → użyj ?? '—'
          ('Locale',   state.selectedLocale   ?? '—'),
          ('Strefa',   state.selectedTimezone ?? '—'),
          ('Klawiatura', (state.selectedKeyboard ?? '—').toUpperCase()),
        ]),

        const SizedBox(height: 16),
        const SectionHeader(title: 'Dysk'),
        _SummaryCard(icon: Icons.storage_rounded, items: [
          ('Dysk',      state.selectedDisk?.path     ?? '—'),
          ('Model',     state.selectedDisk?.model    ?? '—'),
          ('Rozmiar',   state.selectedDisk?.sizeHuman ?? '—'),
          ('FS',        _editionFs(config?.edition   ?? 'official')),
          ('Swap',      '${(config?.swapType ?? 'zram').toUpperCase()} (${config?.swapSizeGb ?? 8} GB)'),
        ]),

        const SizedBox(height: 16),
        const SectionHeader(title: 'Konto użytkownika'),
        _SummaryCard(icon: Icons.person_outline_rounded, items: [
          // FIX: String? → użyj ?? '—'
          ('Imię i nazwisko', state.fullName  ?? '—'),
          ('Nazwa użytkownika', state.username ?? '—'),
          ('Hostname',   state.hostname ?? '—'),
          ('Auto-login', state.autologin ? 'Tak' : 'Nie'),
        ]),

        const SizedBox(height: 20),

        // Ostrzeżenie
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentDanger.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.accentDanger.withOpacity(0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.accentDanger, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(
              'Kliknięcie "Zainstaluj teraz" spowoduje trwałe usunięcie wszystkich danych '
            'z dysku ${state.selectedDisk?.path ?? ""}. Tego nie można cofnąć.',
            style: const TextStyle(fontFamily: 'Sora', fontSize: 13,
                                   color: AppTheme.accentDanger),
            )),
          ]),
        ),
      ]),
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

String _editionFs(String edition) =>
edition.toLowerCase() == 'gaming' ? 'BTRFS (z subvolumes)' : 'EXT4';

class _SummaryCard extends StatelessWidget {
  final IconData           icon;
  final List<(String, String)> items;

  const _SummaryCard({required this.icon, required this.items});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.surfaceBorder),
    ),
    child: Column(
      children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        final item   = e.value;
        return Column(children: [
          Row(children: [
            SizedBox(width: 140, child: Text(item.$1, style: const TextStyle(
              fontFamily: 'Sora', fontSize: 13, color: AppTheme.textMuted,
            ))),
            Expanded(child: Text(item.$2, style: const TextStyle(
              fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ))),
          ]),
          if (!isLast) const Divider(color: AppTheme.surfaceBorder, height: 16),
        ]);
      }).toList(),
    ),
  );
}
