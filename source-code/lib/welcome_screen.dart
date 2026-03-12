import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import '../services/installer_state.dart';
import '../services/backend_service.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _showLangPicker = false;

  @override
  Widget build(BuildContext context) {
    final state   = ref.watch(installerProvider);
    final config  = state.config;
    final lang    = state.installerLanguage;
    final edition = config?.edition ?? 'gaming';
    final isGaming = edition == 'gaming';

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.bgDark),
        child: Stack(
          children: [
            // Tło – dekoracyjne koła
            _buildBg(isGaming),

            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _showLangPicker
                ? _LangPicker(
                  current:  lang,
                  onSelect: (code) {
                    ref.read(installerProvider.notifier).setInstallerLanguage(code);
                    setState(() => _showLangPicker = false);
                  },
                  onBack: () => setState(() => _showLangPicker = false),
                )
                : _buildMain(context, state, config, lang, isGaming),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBg(bool isGaming) {
    final c = isGaming ? AppTheme.accentGaming : AppTheme.accentOfficial;
    return Stack(children: [
      Positioned(right: -80, top: -80,
                 child: Container(width: 320, height: 320,
                                  decoration: BoxDecoration(shape: BoxShape.circle,
                                                            gradient: RadialGradient(colors: [c.withOpacity(0.12), Colors.transparent])))),
                                                            Positioned(left: -60, bottom: -60,
                                                                       child: Container(width: 260, height: 260,
                                                                                        decoration: BoxDecoration(shape: BoxShape.circle,
                                                                                                                  gradient: RadialGradient(colors: [AppTheme.accentSecondary.withOpacity(0.08), Colors.transparent])))),
    ]);
  }

  Widget _buildMain(BuildContext context, InstallerState state,
                    InstallerConfig? config, String lang, bool isGaming) {
    return Column(
      children: [
        // ── Topbar ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            // Logo
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.forEdition(isGaming ? 'gaming' : 'official'),
              ),
              child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('HackerOS Installer', style: const TextStyle(
              fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            )),
            const Spacer(),
            // Przycisk zmiany języka UI instalatora
            InkWell(
              onTap: () => setState(() => _showLangPicker = true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.surfaceBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(kInstallerLanguages.firstWhere(
                    (l) => l.code == lang,
                    orElse: () => kInstallerLanguages.first,
                  ).flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(lang.toUpperCase(), style: const TextStyle(
                    fontFamily: 'Sora', fontSize: 11,
                    fontWeight: FontWeight.w600, color: AppTheme.textSecondary,
                  )),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded, size: 14, color: AppTheme.textMuted),
                ]),
              ),
            ),
          ]),
        ).animate().fade(duration: 400.ms),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Edition badge
              _EditionBadge(edition: config?.edition ?? 'gaming')
              .animate().fade(delay: 100.ms).slideX(begin: -0.1, end: 0),
              const SizedBox(height: 20),

              // Tytuł
              Text('Zainstaluj\nHackerOS', style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppTheme.textPrimary, height: 1.15,
              )).animate().fade(delay: 150.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 10),

              // Opis edycji
              Text(_editionDescription(config?.edition ?? 'gaming', lang),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
              ).animate().fade(delay: 200.ms),
              const SizedBox(height: 28),

              // Baza
              _InfoRow(
                icon: Icons.dns_outlined,
                label: 'Baza systemu',
                value: config?.baseDisplayName ?? 'Debian 13 Trixie (Stable)',
                color: AppTheme.accent,
              ).animate().fade(delay: 250.ms),
              const SizedBox(height: 8),

              // Filesystem
              _InfoRow(
                icon: Icons.storage_outlined,
                label: 'System plików',
                value: isGaming ? 'BTRFS z subvolumes' : 'EXT4',
                color: isGaming ? AppTheme.accentGaming : AppTheme.accentSuccess,
              ).animate().fade(delay: 280.ms),
              const SizedBox(height: 28),

              // Cechy
              _FeaturesGrid(edition: config?.edition ?? 'gaming', lang: lang)
              .animate().fade(delay: 320.ms),

              const SizedBox(height: 32),

              // Przycisk Start
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGaming ? AppTheme.accentGaming : AppTheme.accentOfficial,
                    foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  onPressed: () => ref.read(installerProvider.notifier).nextStep(),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_t('start', lang), style: const TextStyle(
                      fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w600,
                    )),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ]),
                ),
              ).animate().fade(delay: 400.ms).slideY(begin: 0.1, end: 0),

              const SizedBox(height: 12),

              Center(child: Text(
                _t('disclaimer', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Sora', fontSize: 11,
                                       color: AppTheme.textMuted),
              )).animate().fade(delay: 450.ms),
            ]),
          ),
        ),
      ],
    );
                    }
}

// ─── Language Picker ─────────────────────────────────────────────────────────

class _LangPicker extends StatelessWidget {
  final String current;
  final void Function(String) onSelect;
  final VoidCallback onBack;

  const _LangPicker({required this.current, required this.onSelect, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary)),
          const SizedBox(width: 8),
          const Text('Język instalatora', style: TextStyle(
            fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          )),
        ]),
      ),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text('Zmienia tylko język interfejsu instalatora. '
      'Język docelowego systemu wybierzesz w następnym kroku.',
      style: const TextStyle(fontFamily: 'Sora', fontSize: 12,
                             color: AppTheme.textSecondary, height: 1.5))),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: kInstallerLanguages.length,
                      itemBuilder: (_, i) {
                        final l       = kInstallerLanguages[i];
                        final selected = l.code == current;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.surfaceElevated : AppTheme.surface,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: ListTile(
                            leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
                            title: Text(l.name, style: TextStyle(
                              fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w500,
                              color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                            )),
                            trailing: selected
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 18)
                            : null,
                            onTap: () => onSelect(l.code),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                        );
                      },
                    ),
                  ),
    ]);
  }
}

// ─── Edition Badge ───────────────────────────────────────────────────────────

class _EditionBadge extends StatelessWidget {
  final String edition;
  const _EditionBadge({required this.edition});
  @override
  Widget build(BuildContext context) {
    final isGaming = edition == 'gaming';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppGradients.forEdition(edition),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
          color: (isGaming ? AppTheme.accentGaming : AppTheme.accentOfficial).withOpacity(0.3),
          blurRadius: 14,
        )],
      ),
      child: Text(
        isGaming ? '🎮  Gaming Edition' : '🛡️  Official Edition',
        style: const TextStyle(fontFamily: 'Sora', fontSize: 13,
                               fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

// ─── InfoRow ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final Color    color;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.surfaceBorder),
    ),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSecondary)),
      const Spacer(),
      Text(value, style: TextStyle(fontFamily: 'Sora', fontSize: 12,
                                   fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

// ─── Features Grid ───────────────────────────────────────────────────────────

class _FeaturesGrid extends StatelessWidget {
  final String edition, lang;
  const _FeaturesGrid({required this.edition, required this.lang});

  @override
  Widget build(BuildContext context) {
    final features = edition == 'gaming' ? _gamingFeatures : _officialFeatures;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: features.map((f) => _FeatureTile(icon: f.$1, label: f.$2)).toList(),
    );
  }

  static const _gamingFeatures = [
    (Icons.sports_esports_rounded, 'Steam via Distrobox'),
    (Icons.folder_special_outlined, 'BTRFS + Snapshots'),
    (Icons.videogame_asset_rounded, 'gamescope-session'),
    (Icons.memory_outlined, 'Zram Swap'),
    (Icons.shield_outlined, 'Prywatność'),
    (Icons.speed_rounded, 'Zoptymalizowany'),
  ];
  static const _officialFeatures = [
    (Icons.verified_outlined, 'Czysty system'),
    (Icons.build_outlined, 'Pełna kontrola'),
    (Icons.shield_outlined, 'Prywatność'),
    (Icons.speed_rounded, 'Lekki i szybki'),
    (Icons.settings_outlined, 'Konfigurowalny'),
    (Icons.security_outlined, 'Bezpieczny'),
  ];
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _FeatureTile({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.surfaceBorder),
    ),
    child: Row(children: [
      Icon(icon, size: 14, color: AppTheme.accent),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(
        fontFamily: 'Sora', fontSize: 11,
        fontWeight: FontWeight.w500, color: AppTheme.textSecondary,
      ), overflow: TextOverflow.ellipsis)),
    ]),
  );
}

// ─── Tłumaczenia (mini i18n) ──────────────────────────────────────────────────

String _t(String key, String lang) {
  const m = <String, Map<String, String>>{
    'start': {
      'pl': 'Rozpocznij instalację',
      'en': 'Start Installation',
      'de': 'Installation starten',
      'fr': 'Démarrer l\'installation',
      'es': 'Iniciar instalación',
      'it': 'Avvia installazione',
      'ru': 'Начать установку',
      'cs': 'Spustit instalaci',
      'pt': 'Iniciar instalação',
    },
    'disclaimer': {
      'pl': 'Instalacja usunie wszystkie dane na wybranym dysku.',
      'en': 'Installation will erase all data on the selected disk.',
      'de': 'Die Installation löscht alle Daten auf dem ausgewählten Laufwerk.',
      'fr': 'L\'installation effacera toutes les données du disque sélectionné.',
      'es': 'La instalación borrará todos los datos del disco seleccionado.',
      'it': 'L\'installazione cancellerà tutti i dati del disco selezionato.',
      'ru': 'Установка удалит все данные на выбранном диске.',
      'cs': 'Instalace vymaže všechna data na vybraném disku.',
      'pt': 'A instalação apagará todos os dados no disco selecionado.',
    },
  };
  return m[key]?[lang] ?? m[key]?['en'] ?? key;
}

String _editionDescription(String edition, String lang) {
  if (edition == 'official') {
    const m = {
      'pl': 'Czysty, minimalny system Debian bez żadnych dodatkowych pakietów. Idealne dla zaawansowanych użytkowników.',
      'en': 'A clean, minimal Debian system without any extra packages. Perfect for advanced users.',
      'de': 'Ein sauberes, minimales Debian-System ohne zusätzliche Pakete. Perfekt für erfahrene Benutzer.',
      'fr': 'Un système Debian propre et minimal sans packages supplémentaires. Parfait pour les utilisateurs avancés.',
      'es': 'Un sistema Debian limpio y minimal sin paquetes adicionales. Perfecto para usuarios avanzados.',
    };
    return m[lang] ?? m['en']!;
  }
  const m = {
    'pl': 'System stworzony do grania. BTRFS z subvolumes, gamescope-session-steam i Arch Linux w kontenerze dla Steam.',
    'en': 'Built for gaming. BTRFS with subvolumes, gamescope-session-steam and Arch Linux container with Steam.',
    'de': 'Für Gaming konzipiert. BTRFS mit Subvolumes, gamescope-session-steam und Arch Linux Container mit Steam.',
    'fr': 'Conçu pour le gaming. BTRFS avec sous-volumes, gamescope-session-steam et conteneur Arch Linux avec Steam.',
    'es': 'Diseñado para gaming. BTRFS con subvolúmenes, gamescope-session-steam y contenedor Arch Linux con Steam.',
  };
  return m[lang] ?? m['en']!;
}
