import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

class LocaleScreen extends ConsumerStatefulWidget {
  const LocaleScreen({super.key});

  @override
  ConsumerState<LocaleScreen> createState() => _LocaleScreenState();
}

class _LocaleScreenState extends ConsumerState<LocaleScreen> {
  List<LocaleInfo> _locales = [];
  List<TimezoneInfo> _timezones = [];
  List<KeyboardLayout> _keyboards = [];
  bool _loading = true;

  String _searchLocale = '';
  String _searchTz = '';

  final _localeFocusNode = FocusNode();
  final _tzSearchCtrl = TextEditingController();
  final _localeSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final backend = ref.read(backendServiceProvider);
    final results = await Future.wait([
      backend.getLocales(),
      backend.getTimezones(),
      backend.getKeyboardLayouts(),
    ]);

    if (mounted) {
      setState(() {
        _locales = results[0] as List<LocaleInfo>;
        _timezones = results[1] as List<TimezoneInfo>;
        _keyboards = results[2] as List<KeyboardLayout>;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _localeFocusNode.dispose();
    _tzSearchCtrl.dispose();
    _localeSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(installerProvider);
    final notifier = ref.read(installerProvider.notifier);

    if (_loading) {
      return const Center(child: LoadingDots(label: 'Loading language settings...'));
    }

    final filteredLocales = _searchLocale.isEmpty
        ? _locales
        : _locales.where((l) => l.name.toLowerCase().contains(_searchLocale.toLowerCase())).toList();

    final filteredTz = _searchTz.isEmpty
        ? _timezones
        : _timezones.where((t) => t.id.toLowerCase().contains(_searchTz.toLowerCase())).toList();

    return StepContainer(
      title: 'Language & Region',
      subtitle: 'Choose your language, timezone, and keyboard layout.',
      footer: NavButtons(
        onBack: null,
        onNext: () async {
          await ref
              .read(backendServiceProvider)
              .setLocaleConfig(state.selectedLocale, state.selectedTimezone, state.selectedKeyboard);
          notifier.nextStep();
        },
        nextEnabled: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language
          const SectionHeader(title: 'Language'),
          TextField(
            controller: _localeSearchCtrl,
            onChanged: (v) => setState(() => _searchLocale = v),
            style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Search language...',
              prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: ListView.builder(
              itemCount: filteredLocales.length,
              itemBuilder: (_, i) {
                final locale = filteredLocales[i];
                final selected = state.selectedLocale == locale.id;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: AppTheme.accent.withOpacity(0.1),
                  title: Text(
                    locale.name,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 13,
                      color: selected ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    locale.id,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppTheme.textMuted),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18)
                      : null,
                  onTap: () => notifier.setLocale(locale.id),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Timezone
          const SectionHeader(title: 'Timezone'),
          TextField(
            controller: _tzSearchCtrl,
            onChanged: (v) => setState(() => _searchTz = v),
            style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Search timezone... (e.g. Europe/Warsaw)',
              prefixIcon: Icon(Icons.schedule_rounded, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: ListView.builder(
              itemCount: filteredTz.length,
              itemBuilder: (_, i) {
                final tz = filteredTz[i];
                final selected = state.selectedTimezone == tz.id;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: AppTheme.accent.withOpacity(0.1),
                  title: Text(
                    tz.city,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 13,
                      color: selected ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    tz.id,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: AppTheme.textMuted),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18)
                      : null,
                  onTap: () => notifier.setTimezone(tz.id),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Keyboard
          const SectionHeader(title: 'Keyboard Layout'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _keyboards.map((kb) {
              final selected = state.selectedKeyboard == kb.id;
              return GestureDetector(
                onTap: () => notifier.setKeyboard(kb.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accent.withOpacity(0.15) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kb.id.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppTheme.accent : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        kb.name,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
