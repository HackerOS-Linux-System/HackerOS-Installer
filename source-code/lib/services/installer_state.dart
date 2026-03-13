import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'backend_service.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final installerProvider =
StateNotifierProvider<InstallerNotifier, InstallerState>((ref) {
  return InstallerNotifier(ref.read(backendServiceProvider));
});

// ─── Język instalatora ────────────────────────────────────────────────────────

class InstallerLanguage {
  final String code, name, flag;
  const InstallerLanguage({required this.code, required this.name, required this.flag});
}

const kInstallerLanguages = [
  InstallerLanguage(code: 'pl', name: 'Polski',     flag: '🇵🇱'),
  InstallerLanguage(code: 'en', name: 'English',    flag: '🇬🇧'),
  InstallerLanguage(code: 'de', name: 'Deutsch',    flag: '🇩🇪'),
  InstallerLanguage(code: 'fr', name: 'Français',   flag: '🇫🇷'),
  InstallerLanguage(code: 'es', name: 'Español',    flag: '🇪🇸'),
  InstallerLanguage(code: 'it', name: 'Italiano',   flag: '🇮🇹'),
  InstallerLanguage(code: 'pt', name: 'Português',  flag: '🇵🇹'),
  InstallerLanguage(code: 'ru', name: 'Русский',    flag: '🇷🇺'),
  InstallerLanguage(code: 'cs', name: 'Čeština',    flag: '🇨🇿'),
  InstallerLanguage(code: 'nl', name: 'Nederlands', flag: '🇳🇱'),
  InstallerLanguage(code: 'tr', name: 'Türkçe',     flag: '🇹🇷'),
  InstallerLanguage(code: 'uk', name: 'Українська', flag: '🇺🇦'),
  InstallerLanguage(code: 'zh', name: '中文',         flag: '🇨🇳'),
  InstallerLanguage(code: 'ja', name: '日本語',       flag: '🇯🇵'),
  InstallerLanguage(code: 'ko', name: '한국어',       flag: '🇰🇷'),
  InstallerLanguage(code: 'ar', name: 'العربية',     flag: '🇸🇦'),
];

// ─── Stan instalatora ─────────────────────────────────────────────────────────

class InstallerState {
  final int              currentStep;
  final InstallerConfig? config;
  final String           installerLanguage;
  final String?          selectedLocale;
  final String?          selectedTimezone;
  final String?          selectedKeyboard;
  final bool             networkConnected;
  final String?          connectedSsid;
  final String?          connectedInterface;
  final DiskInfo?        selectedDisk;
  final String           partitionMode;
  final Map<String, dynamic>? partitionPlan;
  final String?          fullName;
  final String?          username;
  final String?          password;
  final String?          hostname;
  final bool             autologin;
  // FIX: installProgress trzymany w stanie
  final InstallProgress? installProgress;

  const InstallerState({
    this.currentStep       = 0,
    this.config,
    this.installerLanguage = 'pl',
    this.selectedLocale,
    this.selectedTimezone,
    this.selectedKeyboard,
    this.networkConnected  = false,
    this.connectedSsid,
    this.connectedInterface,
    this.selectedDisk,
    this.partitionMode     = 'auto',
    this.partitionPlan,
    this.fullName,
    this.username,
    this.password,
    this.hostname,
    this.autologin         = false,
    this.installProgress,
  });

  InstallerState copyWith({
    int?               currentStep,
    InstallerConfig?   config,
    String?            installerLanguage,
    String?            selectedLocale,
    String?            selectedTimezone,
    String?            selectedKeyboard,
    bool?              networkConnected,
    String?            connectedSsid,
    String?            connectedInterface,
    DiskInfo?          selectedDisk,
    String?            partitionMode,
    Map<String, dynamic>? partitionPlan,
    String?            fullName,
    String?            username,
    String?            password,
    String?            hostname,
    bool?              autologin,
    InstallProgress?   installProgress,
  }) => InstallerState(
    currentStep:        currentStep       ?? this.currentStep,
    config:             config            ?? this.config,
    installerLanguage:  installerLanguage ?? this.installerLanguage,
    selectedLocale:     selectedLocale    ?? this.selectedLocale,
    selectedTimezone:   selectedTimezone  ?? this.selectedTimezone,
    selectedKeyboard:   selectedKeyboard  ?? this.selectedKeyboard,
    networkConnected:   networkConnected  ?? this.networkConnected,
    connectedSsid:      connectedSsid     ?? this.connectedSsid,
    connectedInterface: connectedInterface ?? this.connectedInterface,
    selectedDisk:       selectedDisk      ?? this.selectedDisk,
    partitionMode:      partitionMode     ?? this.partitionMode,
    partitionPlan:      partitionPlan     ?? this.partitionPlan,
    fullName:           fullName          ?? this.fullName,
    username:           username          ?? this.username,
    password:           password          ?? this.password,
    hostname:           hostname          ?? this.hostname,
    autologin:          autologin         ?? this.autologin,
    installProgress:    installProgress   ?? this.installProgress,
  );

  bool get canProceedFromNetwork =>
  !(config?.requiresNetwork ?? false) || networkConnected;

  bool get isInstallReady =>
  selectedDisk != null &&
  selectedLocale != null &&
  selectedTimezone != null &&
  username != null && username!.isNotEmpty &&
  password != null && password!.isNotEmpty;
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class InstallerNotifier extends StateNotifier<InstallerState> {
  final BackendService _backend;

  InstallerNotifier(this._backend) : super(const InstallerState());

  void setConfig(InstallerConfig cfg)      => state = state.copyWith(config: cfg);
  void nextStep()                          => state = state.copyWith(currentStep: state.currentStep + 1);
  void prevStep() {
    if (state.currentStep > 0) state = state.copyWith(currentStep: state.currentStep - 1);
  }
  void goToStep(int step)                  => state = state.copyWith(currentStep: step);

  void setInstallerLanguage(String code)   => state = state.copyWith(installerLanguage: code);
  void setLocale(String l)                 => state = state.copyWith(selectedLocale: l);
  void setTimezone(String t)               => state = state.copyWith(selectedTimezone: t);
  void setKeyboard(String k)               => state = state.copyWith(selectedKeyboard: k);

  void setNetworkConnected(bool v, {String? ssid, String? iface}) =>
  state = state.copyWith(
    networkConnected:   v,
    connectedSsid:      ssid,
    connectedInterface: iface,
  );

  void setSelectedDisk(DiskInfo d)           => state = state.copyWith(selectedDisk: d);
  void setPartitionMode(String m)            => state = state.copyWith(partitionMode: m);
  void setPartitionPlan(Map<String, dynamic> p) => state = state.copyWith(partitionPlan: p);

  void setUserInfo({
    String? fullName, String? username, String? password,
    String? hostname, bool? autologin,
  }) => state = state.copyWith(
    fullName:  fullName,
    username:  username,
    password:  password,
    hostname:  hostname,
    autologin: autologin,
  );

  /// FIX: metoda updateProgress wymagana przez install_screen.dart
  void updateProgress(InstallProgress progress) =>
  state = state.copyWith(installProgress: progress);
}

// ─── Kroki instalatora ────────────────────────────────────────────────────────

class InstallerStep {
  final String id, icon;
  final Map<String, String> titles;
  final Map<String, String> subtitles;

  const InstallerStep({
    required this.id,
    required this.icon,
    required this.titles,
    this.subtitles = const {},
  });

  // FIX: title i subtitle są funkcjami przyjmującymi kod języka
  String title(String lang)    => titles[lang]    ?? titles['en'] ?? id;
  String subtitle(String lang) => subtitles[lang] ?? subtitles['en'] ?? '';
}

List<InstallerStep> buildSteps() => [
  InstallerStep(
    id: 'welcome', icon: '👋',
    titles: {
      'pl': 'Witaj',        'en': 'Welcome',    'de': 'Willkommen',
      'fr': 'Bienvenue',    'es': 'Bienvenido', 'it': 'Benvenuto',
      'pt': 'Bem-vindo',    'ru': 'Добро пожаловать', 'cs': 'Vítejte',
    },
    subtitles: {
      'pl': 'Wybierz edycję', 'en': 'Choose edition',
    },
  ),
InstallerStep(
  id: 'locale', icon: '🌍',
  titles: {
    'pl': 'Język i region', 'en': 'Language & Region', 'de': 'Sprache & Region',
    'fr': 'Langue & Région', 'es': 'Idioma & Región',  'it': 'Lingua & Regione',
    'pt': 'Idioma & Região', 'ru': 'Язык и регион',    'cs': 'Jazyk & Region',
  },
  subtitles: {
    'pl': 'Strefa, język, klawiatura', 'en': 'Timezone, language, keyboard',
  },
),
InstallerStep(
  id: 'network', icon: '📡',
  titles: {
    'pl': 'Sieć',   'en': 'Network',  'de': 'Netzwerk',
    'fr': 'Réseau', 'es': 'Red',      'it': 'Rete',
    'pt': 'Rede',   'ru': 'Сеть',     'cs': 'Síť',
  },
  subtitles: {
    'pl': 'WiFi lub Ethernet', 'en': 'WiFi or Ethernet',
  },
),
InstallerStep(
  id: 'disk', icon: '💾',
  titles: {
    'pl': 'Dysk',    'en': 'Storage', 'de': 'Speicher',
    'fr': 'Stockage','es': 'Almacenamiento', 'it': 'Archiviazione',
    'pt': 'Armazenamento', 'ru': 'Диск', 'cs': 'Disk',
  },
  subtitles: {
    'pl': 'Wybierz dysk', 'en': 'Select disk',
  },
),
InstallerStep(
  id: 'user', icon: '👤',
  titles: {
    'pl': 'Konto',  'en': 'Account', 'de': 'Konto',
    'fr': 'Compte', 'es': 'Cuenta',  'it': 'Account',
    'pt': 'Conta',  'ru': 'Аккаунт', 'cs': 'Účet',
  },
  subtitles: {
    'pl': 'Nazwa użytkownika', 'en': 'Username & password',
  },
),
InstallerStep(
  id: 'summary', icon: '📋',
  titles: {
    'pl': 'Podsumowanie', 'en': 'Summary',  'de': 'Zusammenfassung',
    'fr': 'Résumé',       'es': 'Resumen',  'it': 'Riepilogo',
    'pt': 'Resumo',       'ru': 'Итог',     'cs': 'Souhrn',
  },
  subtitles: {
    'pl': 'Sprawdź wybory', 'en': 'Review choices',
  },
),
InstallerStep(
  id: 'install', icon: '⚙️',
  titles: {
    'pl': 'Instalacja', 'en': 'Installing', 'de': 'Installation',
    'fr': 'Installation','es': 'Instalando', 'it': 'Installazione',
    'pt': 'Instalação',  'ru': 'Установка',  'cs': 'Instalace',
  },
  subtitles: {
    'pl': 'Trwa instalacja...', 'en': 'Installing...',
  },
),
InstallerStep(
  id: 'done', icon: '🎉',
  titles: {
    'pl': 'Gotowe!', 'en': 'Done!',     'de': 'Fertig!',
    'fr': 'Terminé!','es': '¡Listo!',   'it': 'Fatto!',
    'pt': 'Concluído!','ru': 'Готово!', 'cs': 'Hotovo!',
  },
  subtitles: {
    'pl': 'Uruchom ponownie', 'en': 'Reboot now',
  },
),
];
