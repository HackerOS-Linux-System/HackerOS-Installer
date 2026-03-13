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
  // FIX: poprawne typy z backend_service.dart
  List<LocaleInfo>     _locales   = [];
  List<TimezoneInfo>   _timezones = [];
  List<KeyboardLayout> _keyboards = [];
  bool    _loading      = true;
  String  _searchLocale = '';
  String  _searchTz     = '';

  final _tzCtrl     = TextEditingController();
  final _localeCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _tzCtrl.dispose(); _localeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final b = ref.read(backendServiceProvider);
    // FIX: każda metoda zwraca właściwy typ – nie potrzeba cast
    final locales   = await b.getLocales();
    final timezones = await b.getTimezones();
    final keyboards = await b.getKeyboardLayouts();
    if (mounted) {
      setState(() {
        _locales   = locales;
        _timezones = timezones;
        _keyboards = keyboards;
        _loading   = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state   = ref.watch(installerProvider);
    final notifier = ref.read(installerProvider.notifier);
    final lang    = state.installerLanguage;

    if (_loading) return const Center(child: CircularProgressIndicator());

    final filteredLocales = _searchLocale.isEmpty ? _locales
    : _locales.where((l) => l.name.toLowerCase().contains(_searchLocale.toLowerCase())).toList();

    final filteredTz = _searchTz.isEmpty ? _timezones
    : _timezones.where((t) => t.id.toLowerCase().contains(_searchTz.toLowerCase())).toList();

    return StepContainer(
      title:    _t('title', lang),
      subtitle: _t('subtitle', lang),
      footer: NavButtons(
        onBack: null,
        onNext: () async {
          // FIX: state.selectedLocale jest String? – użyj ?? z fallbackiem
          await ref.read(backendServiceProvider).setLocaleConfig(
            state.selectedLocale   ?? 'en_US.UTF-8',
            state.selectedTimezone ?? 'UTC',
            state.selectedKeyboard ?? 'us',
          );
          notifier.nextStep();
        },
        nextEnabled: true,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Język systemu ─────────────────────────────────────────────────────
        SectionHeader(title: _t('language', lang)),
        TextField(
          controller: _localeCtrl,
          onChanged: (v) => setState(() => _searchLocale = v),
          style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: _t('searchLang', lang),
            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        _ListBox(
          itemCount: filteredLocales.length,
          itemBuilder: (_, i) {
            final l        = filteredLocales[i];
            final selected = state.selectedLocale == l.id;
            return _SelectTile(
              title:    l.name,
              subtitle: l.id,
              selected: selected,
              onTap:    () => notifier.setLocale(l.id),
            );
          },
        ),

        const SizedBox(height: 22),

        // ── Strefa czasowa ────────────────────────────────────────────────────
        SectionHeader(title: _t('timezone', lang)),
        TextField(
          controller: _tzCtrl,
          onChanged: (v) => setState(() => _searchTz = v),
          style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: _t('searchTz', lang),
            prefixIcon: const Icon(Icons.schedule_rounded, color: AppTheme.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        _ListBox(
          itemCount: filteredTz.length,
          itemBuilder: (_, i) {
            final t        = filteredTz[i];
            final selected = state.selectedTimezone == t.id;
            return _SelectTile(
              title:    t.city,
              subtitle: t.id,
              selected: selected,
              onTap:    () => notifier.setTimezone(t.id),
            );
          },
        ),

        const SizedBox(height: 22),

        // ── Klawiatura ────────────────────────────────────────────────────────
        SectionHeader(title: _t('keyboard', lang)),
        // FIX: .map<Widget>(...) żeby Dart wiedział że lista jest List<Widget>
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _keyboards.map<Widget>((kb) {
            final selected = state.selectedKeyboard == kb.id;
            return GestureDetector(
              onTap: () => notifier.setKeyboard(kb.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accent.withOpacity(0.15) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(kb.id.toUpperCase(), style: TextStyle(
                    fontFamily: 'JetBrainsMono', fontSize: 13, fontWeight: FontWeight.w700,
                    color: selected ? AppTheme.accent : AppTheme.textPrimary,
                  )),
                  Text(kb.name, style: const TextStyle(
                    fontFamily: 'Sora', fontSize: 10, color: AppTheme.textMuted,
                  )),
                ]),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),
      ]),
    );
  }
}

class _ListBox extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  const _ListBox({required this.itemCount, required this.itemBuilder});
  @override
  Widget build(BuildContext context) => Container(
    height: 170,
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: AppTheme.surfaceBorder),
    ),
    child: ListView.builder(itemCount: itemCount, itemBuilder: itemBuilder),
  );
}

class _SelectTile extends StatelessWidget {
  final String title, subtitle;
  final bool   selected;
  final VoidCallback onTap;
  const _SelectTile({required this.title, required this.subtitle,
    required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    selected: selected,
    selectedTileColor: AppTheme.accent.withOpacity(0.1),
    title: Text(title, style: TextStyle(
      fontFamily: 'Sora', fontSize: 13,
      color: selected ? AppTheme.accent : AppTheme.textPrimary,
      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
    )),
    subtitle: Text(subtitle, style: const TextStyle(
      fontFamily: 'JetBrainsMono', fontSize: 11, color: AppTheme.textMuted,
    )),
    trailing: selected
    ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18) : null,
    onTap: onTap,
  );
}

String _t(String k, String lang) {
  const m = <String, Map<String, String>>{
    'title':    { 'pl': 'Język systemu i region', 'en': 'Language & Region',
      'de': 'Sprache & Region', 'fr': 'Langue & Région', 'ru': 'Язык и регион' },
      'subtitle': { 'pl': 'Wybierz język, strefę czasową i układ klawiatury instalowanego systemu.',
        'en': 'Choose the language, timezone and keyboard layout for the installed system.' },
        'language': { 'pl': 'Język systemu', 'en': 'System Language',
          'de': 'Systemsprache', 'fr': 'Langue du système', 'ru': 'Язык системы' },
          'timezone': { 'pl': 'Strefa czasowa', 'en': 'Timezone',
            'de': 'Zeitzone', 'fr': 'Fuseau horaire', 'ru': 'Часовой пояс' },
            'keyboard': { 'pl': 'Układ klawiatury', 'en': 'Keyboard Layout',
              'de': 'Tastaturlayout',   'fr': 'Disposition du clavier', 'ru': 'Раскладка клавиатуры' },
              'searchLang':{ 'pl': 'Szukaj języka...', 'en': 'Search language...',
                'de': 'Sprache suchen...','fr': 'Rechercher une langue...', 'ru': 'Поиск языка...' },
                'searchTz': { 'pl': 'Szukaj strefy... (np. Europe/Warsaw)',
                  'en': 'Search timezone... (e.g. Europe/London)',
                  'ru': 'Поиск часового пояса...' },
  };
  return m[k]?[lang] ?? m[k]?['en'] ?? k;
}
