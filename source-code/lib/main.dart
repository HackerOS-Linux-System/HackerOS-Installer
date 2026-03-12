import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'theme/app_theme.dart';
import 'screens/installer_shell.dart';
import 'services/backend_service.dart';
import 'services/installer_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: HackerOSInstallerApp()));
}

class HackerOSInstallerApp extends ConsumerWidget {
  const HackerOSInstallerApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'HackerOS Installer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

// ─── Splash ───────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _status = 'Uruchamianie backendu...';
  bool   _error  = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final backend = ref.read(backendServiceProvider);
    final notifier = ref.read(installerProvider.notifier);

    setState(() => _status = 'Łączenie z backendem...');
    await Future.delayed(const Duration(milliseconds: 600));

    bool connected = false;
    for (int i = 0; i < 12; i++) {
      connected = await backend.connect();
      if (connected) break;
      if (!mounted) return;
      setState(() => _status = 'Czekam na backend... (${i + 1}/12)');
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!connected) {
      if (mounted) setState(() {
        _error = true;
        _status = 'Nie można połączyć z backendem.\nUpewnij się że hackeros-installer-backend jest uruchomiony jako root.';
      });
      return;
    }

    setState(() => _status = 'Wczytywanie konfiguracji...');
    await backend.loadConfig();
    if (backend.config != null) {
      notifier.setConfig(backend.config!);
    }

    setState(() => _status = 'Gotowy!');
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const InstallerShell(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.bgDark),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentSecondary],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  boxShadow: [BoxShadow(
                    color: AppTheme.accent.withOpacity(0.35),
                    blurRadius: 48, spreadRadius: 4,
                  )],
                ),
                child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 50),
              ).animate().scale(duration: 700.ms, curve: Curves.elasticOut).fade(duration: 400.ms),

              const SizedBox(height: 28),

              Text('HackerOS', style: const TextStyle(
                fontFamily: 'Sora', fontSize: 38, fontWeight: FontWeight.w700,
                color: Colors.white, letterSpacing: -0.5,
              )).animate().fade(delay: 200.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),

              const SizedBox(height: 4),

              Text('INSTALLER', style: const TextStyle(
                fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w600,
                color: AppTheme.accent, letterSpacing: 6,
              )).animate().fade(delay: 300.ms, duration: 400.ms),

              const SizedBox(height: 52),

              if (!_error) ...[
                SizedBox(
                  width: 260,
                  child: LinearProgressIndicator(
                    backgroundColor: AppTheme.surface,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ).animate().fade(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 18),
              ],

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _status,
                  key: ValueKey(_status),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora', fontSize: 13,
                    color: _error ? AppTheme.accentDanger : AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ).animate().fade(delay: 400.ms, duration: 400.ms),

              if (_error) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() { _error = false; _status = 'Ponawiam...'; });
                    _init();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Spróbuj ponownie'),
                ).animate().fade(delay: 200.ms, duration: 300.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
