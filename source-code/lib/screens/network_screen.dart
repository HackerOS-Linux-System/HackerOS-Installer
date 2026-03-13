import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────

enum _NetStatus { checking, connected, noInternet }

// ─────────────────────────────────────────────────────────────────────────────

class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key});
  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen> {
  _NetStatus _status = _NetStatus.checking;

  // UI konfiguracji (gdy brak internetu)
  List<NetworkInterface> _interfaces   = [];
  List<WifiNetwork>      _wifiNetworks = [];
  String? _selectedInterface;
  bool    _loadingIfaces = false;
  bool    _scanningWifi  = false;
  bool    _connecting    = false;
  String? _error;

  // info o wykrytym połączeniu
  String? _autoIfaceName;
  String? _autoIpAddress;
  String? _autoIfaceType;

  @override
  void initState() {
    super.initState();
    _checkInternet();
  }

  // ── Sprawdzenie internetu ─────────────────────────────────────────────────
  // Kolejność:
  //   1. Zapytaj backend (ping/curl po stronie roota) – najdokładniejsze
  //   2. Fallback: dart:io NetworkInterface.list() – sprawdź czy jest IP != 127/169
  //   3. Fallback: dart:io Socket.connect do 8.8.8.8:53

  Future<void> _checkInternet() async {
    if (mounted) setState(() { _status = _NetStatus.checking; _error = null; });

    bool hasInternet = false;

    // ── Metoda 1: backend CheckInternet (ping/curl) ──────────────────────────
    try {
      final backend = ref.read(backendServiceProvider);
      hasInternet = await backend.checkInternet();
    } catch (_) {
      // Backend niedostępny – przechodzimy do fallbacków
    }

    // ── Metoda 2: dart:io NetworkInterface.list() ────────────────────────────
    // Sprawdza czy jest publiczny lub prywatny adres IPv4 (nie loopback, nie link-local)
    if (!hasInternet) {
      try {
        final ifaces = await io.NetworkInterface.list(
          type: io.InternetAddressType.IPv4,
          includeLinkLocal: false,
          includeLoopback: false,
        );
        for (final iface in ifaces) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            // Wyklucz loopback (127.x) i link-local (169.254.x)
            if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) {
              hasInternet = true;
              _autoIfaceName = iface.name;
              _autoIpAddress = ip;
              _autoIfaceType = iface.name.startsWith('wl') ? 'wifi' : 'ethernet';
              break;
            }
          }
          if (hasInternet) break;
        }
      } catch (_) {}
    }

    // ── Metoda 3: TCP do 8.8.8.8:53 ─────────────────────────────────────────
    if (!hasInternet) {
      try {
        final sock = await io.Socket.connect(
          '8.8.8.8', 53,
          timeout: const Duration(seconds: 5),
        );
        sock.destroy();
        hasInternet = true;
      } catch (_) {}
    }

    if (!mounted) return;

    if (hasInternet) {
      // Pobierz dodatkowe info o interfejsie jeśli jeszcze nie mamy
      if (_autoIfaceName == null) {
        await _detectActiveIface();
      }
      if (!mounted) return;
      setState(() => _status = _NetStatus.connected);
      ref.read(installerProvider.notifier).setNetworkConnected(
        true, iface: _autoIfaceName, ssid: null,
      );
    } else {
      setState(() => _status = _NetStatus.noInternet);
      await _loadIfaces();
    }
  }

  Future<void> _detectActiveIface() async {
    try {
      final ifaces = await ref.read(backendServiceProvider).getNetworkInterfaces();
      final connected = ifaces.where((i) => i.isConnected).toList();
      if (connected.isNotEmpty) {
        final i = connected.first;
        _autoIfaceName = i.name;
        _autoIpAddress = i.ipAddress;
        _autoIfaceType = i.type;
      }
    } catch (_) {}
  }

  // ── Ładowanie interfejsów do ręcznej konfiguracji ─────────────────────────

  Future<void> _loadIfaces() async {
    setState(() => _loadingIfaces = true);
    try {
      final ifaces = await ref.read(backendServiceProvider).getNetworkInterfaces();
      if (!mounted) return;
      final connected = ifaces.where((i) => i.isConnected).toList();
      setState(() {
        _interfaces        = ifaces;
        _loadingIfaces     = false;
        _selectedInterface = connected.isNotEmpty ? connected.first.name
        : ifaces.isNotEmpty ? ifaces.first.name : null;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingIfaces = false);
    }
  }

  // ── WiFi ──────────────────────────────────────────────────────────────────

  Future<void> _scanWifi(String iface) async {
    setState(() { _scanningWifi = true; _error = null; });
    try {
      final nets = await ref.read(backendServiceProvider).getWifiNetworks(iface);
      if (mounted) setState(() => _wifiNetworks = nets);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanningWifi = false);
    }
  }

  Future<void> _connectWifi(WifiNetwork network) async {
    String? password;
    if (!network.isOpen) {
      password = await _showPasswordDialog(network.ssid);
      if (password == null) return;
    }
    setState(() { _connecting = true; _error = null; });
    try {
      final ok = await ref.read(backendServiceProvider)
      .connectWifi(_selectedInterface!, network.ssid, password: password);
      if (!mounted) return;
      if (ok) {
        await _checkInternet();
      } else {
        setState(() => _error = 'Połączenie nie powiodło się. Sprawdź hasło.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connectEthernet(String iface) async {
    setState(() { _connecting = true; _error = null; });
    try {
      final ok = await ref.read(backendServiceProvider).connectEthernet(iface);
      if (!mounted) return;
      if (ok) {
        await _checkInternet();
      } else {
        setState(() => _error = 'Nie udało się połączyć przez Ethernet.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<String?> _showPasswordDialog(String ssid) => showDialog<String>(
    context: context,
    builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Połącz z "$ssid"',
                    style: const TextStyle(color: AppTheme.textPrimary)),
                    content: PasswordField(controller: ctrl, label: 'Hasło WiFi',
                                           textInputAction: TextInputAction.done),
                         actions: [
                           TextButton(onPressed: () => Navigator.pop(ctx),
                           child: const Text('Anuluj', style: TextStyle(color: AppTheme.textMuted))),
                           ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text),
                           child: const Text('Połącz')),
                         ],
      );
    },
  );

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state      = ref.watch(installerProvider);
    final isRequired = state.config?.requiresNetwork ?? false;

    return StepContainer(
      title:    'Połączenie sieciowe',
      subtitle: isRequired
      ? 'Edycja Gaming wymaga połączenia z internetem.'
    : 'Połączenie zalecane. Możesz też pominąć ten krok.',
    footer: NavButtons(
      onBack: () => ref.read(installerProvider.notifier).prevStep(),
      onNext: () => ref.read(installerProvider.notifier).nextStep(),
      nextEnabled: _status == _NetStatus.connected || !isRequired,
      nextLabel:   _status != _NetStatus.connected && !isRequired ? 'Pomiń' : 'Dalej',
    ),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: switch (_status) {
        _NetStatus.checking   => _buildChecking(),
        _NetStatus.connected  => _buildConnected(),
        _NetStatus.noInternet => _buildNoInternet(state, isRequired),
      },
    ),
    );
  }

  // ── Sprawdzanie ───────────────────────────────────────────────────────────

  Widget _buildChecking() => Center(
    key: const ValueKey('checking'),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 52, height: 52,
                     child: CircularProgressIndicator(strokeWidth: 3)),
                     const SizedBox(height: 24),
                     const Text('Sprawdzanie połączenia z internetem...',
                                style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                                const SizedBox(height: 8),
                                const Text('Testowanie dostępności sieci...',
                                           style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
    ]).animate().fade(duration: 300.ms),
  );

  // ── Internet wykryty ──────────────────────────────────────────────────────

  Widget _buildConnected() {
    final icon = _autoIfaceType == 'wifi' ? Icons.wifi_rounded
    : _autoIfaceType == 'virtual'     ? Icons.cloud_done_rounded
    : Icons.cable_rounded;

    return Column(
      key: const ValueKey('connected'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Główny banner sukcesu
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.accentSuccess.withOpacity(0.18),
                AppTheme.accentSuccess.withOpacity(0.06),
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.accentSuccess.withOpacity(0.45), width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppTheme.accentSuccess.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                                color: AppTheme.accentSuccess, size: 30),
            ),
            const SizedBox(width: 18),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Internet działa!', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppTheme.accentSuccess,
                )),
                SizedBox(height: 4),
                Text(
                  'Wykryto aktywne połączenie. Możesz przejść dalej '
                'bez żadnej dodatkowej konfiguracji.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                ),
              ])),
          ]),
        ).animate().fade(duration: 450.ms).slideY(begin: -0.04, end: 0),

        const SizedBox(height: 18),

        // Szczegóły interfejsu
        if (_autoIfaceName != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: Row(children: [
              Icon(icon, color: AppTheme.accentSuccess, size: 20),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text(_autoIfaceName!, style: const TextStyle(
                                         fontSize: 14, fontWeight: FontWeight.w600,
                                         color: AppTheme.textPrimary,
                                       )),
                                     if (_autoIpAddress != null)
                                       Text('IP: $_autoIpAddress', style: const TextStyle(
                                         fontSize: 12, color: AppTheme.textMuted,
                                       )),
                                     ])),
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                         decoration: BoxDecoration(
                           color: AppTheme.accentSuccess.withOpacity(0.12),
                           borderRadius: BorderRadius.circular(8),
                         ),
                         child: const Text('Połączono', style: TextStyle(
                           fontSize: 11, fontWeight: FontWeight.w600,
                           color: AppTheme.accentSuccess,
                         )),
                       ),
            ]),
          ).animate().fade(delay: 150.ms, duration: 350.ms),

          const SizedBox(height: 22),

          // Wskazówka "idź dalej"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppTheme.surfaceBorder),
            ),
            child: Row(children: [
              const Icon(Icons.east_rounded, color: AppTheme.accent, size: 16),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'Kliknij "Dalej" aby przejść do wyboru dysku.',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              )),
            ]),
          ).animate().fade(delay: 220.ms, duration: 350.ms),

          const SizedBox(height: 14),

          // Link ręcznej konfiguracji
          TextButton.icon(
            onPressed: () {
              setState(() {
                _status = _NetStatus.noInternet;
                _wifiNetworks = [];
              });
              _loadIfaces();
            },
            icon: const Icon(Icons.settings_rounded, size: 14),
            label: const Text('Skonfiguruj sieć ręcznie'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textMuted,
                textStyle: const TextStyle(fontSize: 12),
            ),
          ).animate().fade(delay: 280.ms, duration: 350.ms),
      ],
    );
  }

  // ── Brak internetu – pełny UI konfiguracji ────────────────────────────────

  Widget _buildNoInternet(InstallerState state, bool isRequired) {
    final selectedIface = _interfaces
    .where((i) => i.name == _selectedInterface).firstOrNull;

    return Column(
      key: const ValueKey('noInternet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Banner ostrzeżenia / informacji
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isRequired
              ? AppTheme.accentWarning.withOpacity(0.5)
              : AppTheme.surfaceBorder,
            ),
          ),
          child: Row(children: [
            Icon(Icons.wifi_off_rounded,
                 color: isRequired ? AppTheme.accentWarning : AppTheme.textMuted,
                 size: 22),
                 const SizedBox(width: 12),
                 Expanded(child: Text(
                   isRequired
                   ? 'Brak internetu. Gaming Edition wymaga sieci do pobrania pakietów.'
                 : 'Nie wykryto połączenia. Skonfiguruj sieć lub pomiń ten krok.',
                 style: TextStyle(
                   fontSize: 13,
                   color: isRequired ? AppTheme.accentWarning : AppTheme.textSecondary,
                 ),
                 )),
                 if (isRequired)
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     decoration: BoxDecoration(
                       color: AppTheme.accentWarning.withOpacity(0.15),
                       borderRadius: BorderRadius.circular(7),
                     ),
                     child: const Text('Wymagane', style: TextStyle(
                       fontSize: 11, fontWeight: FontWeight.w600,
                       color: AppTheme.accentWarning,
                     )),
                   ),
          ]),
        ),

        // Przycisk "Sprawdź ponownie"
        Row(children: [
          TextButton.icon(
            onPressed: _checkInternet,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Sprawdź ponownie'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accent,
                textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const Spacer(),
        ]),

        // Błąd
        if (_error != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentDanger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.accentDanger.withOpacity(0.3)),
            ),
            child: Text(_error!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.accentDanger)),
          ),
        ],

        const SizedBox(height: 16),

        // Interfejsy
        if (_loadingIfaces)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator()))
          else ...[

            const SectionHeader(title: 'Interfejsy sieciowe'),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _interfaces.map((iface) {
                final sel = iface.name == _selectedInterface;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedInterface = iface.name;
                      _wifiNetworks = [];
                    });
                    if (iface.isEthernet && !iface.isConnected) _connectEthernet(iface.name);
                    if (iface.isWifi) _scanWifi(iface.name);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.accent.withOpacity(0.12) : AppTheme.surface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: sel ? AppTheme.accent : AppTheme.surfaceBorder,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        iface.isWifi ? Icons.wifi_rounded : Icons.cable_rounded,
                        size: 17,
                        color: iface.isConnected
                        ? AppTheme.accentSuccess
                        : sel ? AppTheme.accent : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(iface.name, style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: sel ? AppTheme.accent : AppTheme.textPrimary,
                        )),
                        Text(
                          iface.isConnected ? (iface.ipAddress ?? 'Połączono') : iface.type,
                          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                        ),
                      ]),
                    ]),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 18),

            // WiFi
            if (selectedIface?.isWifi == true) ...[
              SectionHeader(
                title: 'Dostępne sieci WiFi',
                trailing: _scanningWifi
                ? const SizedBox(width: 16, height: 16,
                                 child: CircularProgressIndicator(strokeWidth: 2,
                                                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent)))
                : TextButton.icon(
                  onPressed: () => _scanWifi(_selectedInterface!),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Skanuj'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_wifiNetworks.isEmpty && !_scanningWifi)
                GestureDetector(
                  onTap: () => _scanWifi(_selectedInterface!),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: const Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_find_rounded, color: AppTheme.textMuted, size: 32),
                      SizedBox(height: 8),
                      Text('Kliknij aby skanować sieci WiFi',
                           style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    ]),
                  ),
                )
                else if (_wifiNetworks.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _wifiNetworks.length,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppTheme.surfaceBorder),
                      itemBuilder: (_, i) {
                        final net = _wifiNetworks[i];
                        final isCurrent = state.networkConnected &&
                        state.connectedSsid == net.ssid;
                        return ListTile(
                          leading: WifiSignalIcon(bars: net.signalBars,
                                                  color: isCurrent ? AppTheme.accentSuccess : null),
                                        title: Text(net.ssid, style: TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w500,
                                          color: isCurrent ? AppTheme.accentSuccess : AppTheme.textPrimary,
                                        )),
                                        subtitle: Text(
                                          '${net.isOpen ? "Otwarta" : net.security} · ${net.signal}%',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                        trailing: _connecting
                                        ? const SizedBox(width: 18, height: 18,
                                                         child: CircularProgressIndicator(strokeWidth: 2))
                                        : isCurrent
                                        ? const Icon(Icons.check_circle_rounded,
                                                     color: AppTheme.accentSuccess, size: 20)
                                        : Icon(net.isOpen
                                        ? Icons.lock_open_rounded : Icons.lock_rounded,
                                        size: 16, color: AppTheme.textMuted),
                                        onTap: _connecting ? null : () => _connectWifi(net),
                        );
                      },
                    ),
                  ),
            ],

            // Ethernet
            if (selectedIface?.isEthernet == true) ...[
              const SectionHeader(title: 'Ethernet'),
              HCard(
                child: Row(children: [
                  Icon(Icons.cable_rounded,
                       color: selectedIface!.isConnected
                       ? AppTheme.accentSuccess : AppTheme.textMuted,
                       size: 26),
                       const SizedBox(width: 12),
                       Expanded(child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start, children: [
                           Text(selectedIface.name, style: const TextStyle(
                             fontWeight: FontWeight.w600,
                             color: AppTheme.textPrimary, fontSize: 14,
                           )),
                           Text(
                             selectedIface.isConnected
                             ? 'Połączono — ${selectedIface.ipAddress ?? ""}'
                           : 'Podłącz kabel ethernet i kliknij "Połącz"',
                           style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                           ),
                         ])),
                         if (!selectedIface.isConnected && !_connecting)
                           ElevatedButton(
                             onPressed: () => _connectEthernet(selectedIface.name),
                             style: ElevatedButton.styleFrom(
                               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                               child: const Text('Połącz', style: TextStyle(fontSize: 13)),
                           ),
                           if (_connecting)
                             const SizedBox(width: 20, height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ),
            ],
          ],
      ],
    );
  }
}
