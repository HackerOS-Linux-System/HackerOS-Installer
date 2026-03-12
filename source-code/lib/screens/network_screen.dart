import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key});

  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen> {
  List<NetworkInterface> _interfaces = [];
  List<WifiNetwork> _wifiNetworks = [];
  String? _selectedInterface;
  bool _loadingInterfaces = true;
  bool _scanningWifi = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInterfaces();
  }

  Future<void> _loadInterfaces() async {
    setState(() => _loadingInterfaces = true);
    try {
      final ifaces = await ref.read(backendServiceProvider).getNetworkInterfaces();
      if (mounted) {
        setState(() {
          _interfaces = ifaces;
          _loadingInterfaces = false;
          // Select first connected or first interface
          final connected = ifaces.where((i) => i.connected).toList();
          if (connected.isNotEmpty) {
            _selectedInterface = connected.first.name;
            if (connected.first.isWifi) {
              _wifiNetworks = [];
            }
          } else if (ifaces.isNotEmpty) {
            _selectedInterface = ifaces.first.name;
          }
        });

        // Check if already connected
        final connectedIface = ifaces.where((i) => i.connected).toList();
        if (connectedIface.isNotEmpty) {
          ref.read(installerProvider.notifier).setNetworkConnected(
                true,
                ssid: connectedIface.first.ssid,
                interface: connectedIface.first.name,
              );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingInterfaces = false);
    }
  }

  Future<void> _scanWifi(String interface) async {
    setState(() {
      _scanningWifi = true;
      _error = null;
    });
    try {
      final networks = await ref.read(backendServiceProvider).getWifiNetworks(interface);
      if (mounted) setState(() => _wifiNetworks = networks);
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
      if (password == null) return; // User cancelled
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      final success = await ref.read(backendServiceProvider).connectWifi(
            _selectedInterface!,
            network.ssid,
            password: password,
          );

      if (success && mounted) {
        ref.read(installerProvider.notifier).setNetworkConnected(
              true,
              ssid: network.ssid,
              interface: _selectedInterface,
            );
        await _loadInterfaces();
      } else {
        setState(() => _error = 'Connection failed. Check your password and try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connectEthernet(String interface) async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      final success = await ref.read(backendServiceProvider).connectEthernet(interface);
      if (success && mounted) {
        ref.read(installerProvider.notifier).setNetworkConnected(true, interface: interface);
        await _loadInterfaces();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<String?> _showPasswordDialog(String ssid) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Connect to "$ssid"',
          style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary),
        ),
        content: PasswordField(
          controller: ctrl,
          label: 'WiFi Password',
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(installerProvider);
    final isRequired = state.config?.requiresNetwork ?? false;
    final isConnected = state.networkConnected;

    final selectedIface = _interfaces
        .where((i) => i.name == _selectedInterface)
        .firstOrNull;

    return StepContainer(
      title: 'Network Connection',
      subtitle: isRequired
          ? 'An internet connection is required for this edition.'
          : 'Connect to the internet to download updates and extras.',
      footer: NavButtons(
        onBack: () => ref.read(installerProvider.notifier).prevStep(),
        onNext: () => ref.read(installerProvider.notifier).nextStep(),
        nextEnabled: isRequired ? isConnected : true,
        nextLabel: !isRequired && !isConnected ? 'Skip' : 'Continue',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection status banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isConnected
                  ? AppTheme.accentSuccess.withOpacity(0.1)
                  : AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isConnected ? AppTheme.accentSuccess : AppTheme.surfaceBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: isConnected ? AppTheme.accentSuccess : AppTheme.textMuted,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? 'Connected' : 'Not connected',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isConnected ? AppTheme.accentSuccess : AppTheme.textPrimary,
                        ),
                      ),
                      if (isConnected && (state.connectedSsid != null || state.connectedInterface != null))
                        Text(
                          state.connectedSsid ?? state.connectedInterface ?? '',
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
                  onPressed: _loadInterfaces,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentDanger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accentDanger.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppTheme.accentDanger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        color: AppTheme.accentDanger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_loadingInterfaces)
            const Center(child: LoadingDots(label: 'Detecting network interfaces...'))
          else ...[
            // Interface selector
            const SectionHeader(title: 'Network Interface'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _interfaces.map((iface) {
                final selected = _selectedInterface == iface.name;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedInterface = iface.name;
                      _wifiNetworks = [];
                    });
                    if (iface.isWifi) _scanWifi(iface.name);
                    if (iface.isEthernet && !iface.connected) _connectEthernet(iface.name);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accent.withOpacity(0.12) : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          iface.isWifi ? Icons.wifi_rounded : Icons.cable_rounded,
                          size: 18,
                          color: iface.connected
                              ? AppTheme.accentSuccess
                              : selected
                                  ? AppTheme.accent
                                  : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              iface.name,
                              style: TextStyle(
                                fontFamily: 'JetBrainsMono',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected ? AppTheme.accent : AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              iface.connected ? (iface.ipAddress ?? 'Connected') : iface.interfaceType,
                              style: const TextStyle(fontFamily: 'Sora', fontSize: 10, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // WiFi networks
            if (selectedIface?.isWifi == true) ...[
              SectionHeader(
                title: 'Available WiFi Networks',
                trailing: _scanningWifi
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: () => _scanWifi(_selectedInterface!),
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Scan'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 12),
                        ),
                      ),
              ),
              if (_wifiNetworks.isEmpty && !_scanningWifi)
                GestureDetector(
                  onTap: () => _scanWifi(_selectedInterface!),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: const Center(
                      child: Text(
                        'Tap to scan for WiFi networks',
                        style: TextStyle(fontFamily: 'Sora', color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.surfaceBorder),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _wifiNetworks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.surfaceBorder),
                    itemBuilder: (_, i) {
                      final net = _wifiNetworks[i];
                      final isCurrentlyConnected = state.networkConnected && state.connectedSsid == net.ssid;
                      return ListTile(
                        leading: WifiSignalIcon(
                          bars: net.signalBars,
                          color: isCurrentlyConnected ? AppTheme.accentSuccess : null,
                        ),
                        title: Text(
                          net.ssid,
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isCurrentlyConnected ? AppTheme.accentSuccess : AppTheme.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${net.security} • ${net.signal}%',
                          style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textMuted),
                        ),
                        trailing: _connecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : isCurrentlyConnected
                                ? const Icon(Icons.check_circle_rounded, color: AppTheme.accentSuccess, size: 20)
                                : Icon(
                                    net.isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                                    size: 16,
                                    color: AppTheme.textMuted,
                                  ),
                        onTap: _connecting ? null : () => _connectWifi(net),
                      );
                    },
                  ),
                ),
            ],

            if (selectedIface?.isEthernet == true) ...[
              const SectionHeader(title: 'Ethernet'),
              HCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.cable_rounded,
                      color: selectedIface!.connected ? AppTheme.accentSuccess : AppTheme.textMuted,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedIface.name,
                            style: const TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            selectedIface.connected
                                ? 'Connected — ${selectedIface.ipAddress ?? ''}'
                                : 'Plug in ethernet cable to connect automatically',
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!selectedIface.connected && !_connecting)
                      ElevatedButton(
                        onPressed: () => _connectEthernet(selectedIface.name),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                        child: const Text('Connect', style: TextStyle(fontFamily: 'Sora', fontSize: 13)),
                      ),
                    if (_connecting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
