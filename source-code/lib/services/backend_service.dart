import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Provider ────────────────────────────────────────────────────────────────

final backendServiceProvider = Provider<BackendService>((ref) => BackendService());

// ─── InstallerConfig ─────────────────────────────────────────────────────────

class InstallerConfig {
  final String edition;
  final String base;
  final String desktopEnvironment;
  final String bootloader;
  final String swapType;
  final int    swapSizeGb;
  final bool   requireNetwork;
  final bool   configureAptSources;

  const InstallerConfig({
    required this.edition,
    required this.base,
    required this.desktopEnvironment,
    required this.bootloader,
    required this.swapType,
    required this.swapSizeGb,
    required this.requireNetwork,
    required this.configureAptSources,
  });

  factory InstallerConfig.fromJson(Map<String, dynamic> j) => InstallerConfig(
    edition:             j['edition']               ?? 'gaming',
    base:                j['base']                  ?? 'trixie',
    desktopEnvironment:  j['desktop_environment']   ?? 'kde',
    bootloader:          j['bootloader']            ?? 'grub',
    swapType:            j['swap_type']             ?? 'zram',
    swapSizeGb:          (j['swap_size_gb'] as num? ?? 8).toInt(),
    requireNetwork:      j['require_network']       ?? false,
    configureAptSources: j['configure_apt_sources'] ?? true,
  );

  bool   get isGamingEdition   => edition == 'gaming';
  bool   get isOfficialEdition => edition == 'official';
  bool   get requiresNetwork   => requireNetwork || isGamingEdition;
  String get filesystem        => isGamingEdition ? 'btrfs' : 'ext4';

  String get baseDisplayName {
    switch (base.toLowerCase()) {
      case 'trixie':  return 'Debian 13 Trixie (Stable)';
      case 'forky':
      case 'testing': return 'Debian Testing – Forky (Rolling)';
      default:        return base;
    }
  }

  String get editionDisplayName =>
  edition == 'gaming' ? 'Gaming Edition' : 'Official Edition';
}

// ─── DiskInfo ─────────────────────────────────────────────────────────────────

class DiskInfo {
  final String path, name, sizeHuman, model, diskType;
  final int    sizeBytes;
  final bool   removable;
  final List<PartitionInfoModel> partitions;

  const DiskInfo({
    required this.path, required this.name, required this.sizeHuman,
    required this.model, required this.diskType, required this.sizeBytes,
    required this.removable, required this.partitions,
  });

  factory DiskInfo.fromJson(Map<String, dynamic> j) => DiskInfo(
    path:       j['path']       ?? '',
    name:       j['name']       ?? '',
    sizeHuman:  j['size_human'] ?? '',
    model:      j['model']      ?? 'Unknown',
    diskType:   j['disk_type']  ?? 'unknown',
    sizeBytes:  (j['size_bytes'] as num? ?? 0).toInt(),
    removable:  j['removable']  ?? false,
    partitions: (j['partitions'] as List<dynamic>? ?? [])
    .map((p) => PartitionInfoModel.fromJson(p as Map<String, dynamic>)).toList(),
  );

  IconData get icon {
    switch (diskType) {
      case 'nvme': return Icons.memory_outlined;
      case 'ssd':  return Icons.storage_rounded;
      case 'usb':  return Icons.usb_rounded;
      default:     return Icons.album_outlined;
    }
  }
}

class PartitionInfoModel {
  final String path, name, sizeHuman, filesystem;
  final String? mountpoint, label;
  final int     sizeBytes;

  const PartitionInfoModel({
    required this.path, required this.name, required this.sizeHuman,
    required this.filesystem, required this.sizeBytes,
    this.mountpoint, this.label,
  });

  factory PartitionInfoModel.fromJson(Map<String, dynamic> j) => PartitionInfoModel(
    path:       j['path']       ?? '',
    name:       j['name']       ?? '',
    sizeHuman:  j['size_human'] ?? '',
    filesystem: j['filesystem'] ?? '',
    sizeBytes:  (j['size_bytes'] as num? ?? 0).toInt(),
    mountpoint: j['mountpoint'] as String?,
    label:      j['label']      as String?,
  );
}

// ─── NetworkInterface ─────────────────────────────────────────────────────────

class NetworkInterface {
  final String  name, type, state;
  final String? ipAddress, macAddress, ssid;

  const NetworkInterface({
    required this.name, required this.type, required this.state,
    this.ipAddress, this.macAddress, this.ssid,
  });

  factory NetworkInterface.fromJson(Map<String, dynamic> j) {
    // Backend Rust zwraca: connected (bool) + interface_type (String)
    // Normalizujemy do state (String) + type (String)
    final connected = j['connected'] as bool? ?? false;
    final stateStr  = j['state']     as String? ??
    (connected ? 'connected' : 'disconnected');
    final typeStr   = j['type']            as String? ??
    j['interface_type'] as String? ?? 'ethernet';
    return NetworkInterface(
      name:       j['name']        ?? '',
      type:       typeStr,
      state:      stateStr,
      ipAddress:  j['ip_address']  as String?,
      macAddress: j['mac_address'] as String?,
      ssid:       j['ssid']        as String?,
    );
  }

  bool get isWifi      => type == 'wifi';
  bool get isEthernet  => type == 'ethernet';
  bool get isConnected => state == 'connected';
}

// ─── WifiNetwork ─────────────────────────────────────────────────────────────

class WifiNetwork {
  final String ssid, security;
  final int    signal;
  final bool   connected;

  const WifiNetwork({
    required this.ssid, required this.security,
    required this.signal, required this.connected,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> j) => WifiNetwork(
    ssid:      j['ssid']      ?? '',
    security:  j['security']  ?? '',
    signal:    (j['signal'] as num? ?? 0).toInt(),
    connected: j['connected'] ?? false,
  );

  bool get isOpen => security.isEmpty || security.toLowerCase() == 'none';

  int get signalBars {
    if (signal >= 80) return 4;
    if (signal >= 55) return 3;
    if (signal >= 30) return 2;
    return 1;
  }
}

// ─── Locale / Timezone / Keyboard types ──────────────────────────────────────
// Używane przez locale_screen.dart

class LocaleInfo {
  final String id, name;
  const LocaleInfo({required this.id, required this.name});
  factory LocaleInfo.fromJson(Map<String, dynamic> j) =>
  LocaleInfo(id: j['id'] ?? '', name: j['name'] ?? '');
}

class TimezoneInfo {
  final String id, region, city;
  const TimezoneInfo({required this.id, required this.region, required this.city});
  factory TimezoneInfo.fromJson(Map<String, dynamic> j) => TimezoneInfo(
    id:     j['id']     ?? '',
    region: j['region'] ?? '',
    city:   j['city']   ?? '',
  );
}

class KeyboardLayout {
  final String id, name;
  const KeyboardLayout({required this.id, required this.name});
  factory KeyboardLayout.fromJson(Map<String, dynamic> j) =>
  KeyboardLayout(id: j['id'] ?? '', name: j['name'] ?? '');
}

// ─── InstallProgress ─────────────────────────────────────────────────────────

class InstallProgress {
  final String       phase, currentTask;
  final int          percent;
  final List<String> logLines;
  final String?      error;
  final bool         completed, cancelled;

  const InstallProgress({
    required this.phase, required this.currentTask,
    required this.percent, required this.logLines,
    this.error, required this.completed, required this.cancelled,
  });

  factory InstallProgress.initial() => const InstallProgress(
    phase: 'not_started', currentTask: 'Oczekiwanie...',
    percent: 0, logLines: [], completed: false, cancelled: false,
  );

  factory InstallProgress.fromJson(Map<String, dynamic> j) => InstallProgress(
    phase:       j['phase']        ?? 'not_started',
    currentTask: j['current_task'] ?? '',
    percent:     (j['percent'] as num? ?? 0).toInt(),
    logLines:    (j['log_lines'] as List<dynamic>? ?? [])
    .map((e) => e.toString()).toList(),
    error:       j['error'] as String?,
    completed:   j['completed'] ?? false,
    cancelled:   j['cancelled'] ?? false,
  );
}

// ─── SystemInfo ───────────────────────────────────────────────────────────────

class SystemInfo {
  final String cpuModel, ramTotal, hostname;
  final bool   efi;

  const SystemInfo({
    required this.cpuModel, required this.ramTotal,
    required this.hostname, required this.efi,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> j) => SystemInfo(
    cpuModel: j['cpu_model']       ?? 'Unknown CPU',
    ramTotal: j['ram_total_human'] ?? 'Unknown',
    hostname: j['hostname']        ?? 'hackeros',
    efi:      j['is_efi']          ?? false,
  );
}

// ─── BackendService ───────────────────────────────────────────────────────────

class BackendService {
  static const String _socketPath = '/tmp/hackeros-installer.sock';

  Socket?  _socket;
  final    _buf = StringBuffer();
  final    _responseCtrl = StreamController<Map<String, dynamic>>.broadcast();
  InstallerConfig? config;

  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(
        InternetAddress(_socketPath, type: InternetAddressType.unix), 0,
        timeout: const Duration(seconds: 3),
      );
      // FIX: cast do Stream<List<int>> przed transform(utf8.decoder)
      _socket!
      .cast<List<int>>()
      .transform(utf8.decoder)
      .listen(_onData, onError: _onError, onDone: _onDone);
      final pong = await _send({'action': 'Ping'});
      return pong['success'] == true;
    } catch (_) {
      return false;
    }
  }

  void _onData(String data) {
    _buf.write(data);
    final lines = _buf.toString().split('\n');
    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      try { _responseCtrl.add(jsonDecode(line) as Map<String, dynamic>); } catch (_) {}
    }
    _buf.clear();
    _buf.write(lines.last);
  }

  void _onError(dynamic _) { _socket = null; }
  void _onDone()            { _socket = null; }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> req) async {
    if (_socket == null) throw Exception('Brak połączenia z backendem');
    _socket!.write(jsonEncode(req) + '\n');
    final c = Completer<Map<String, dynamic>>();
    late StreamSubscription<Map<String, dynamic>> sub;
    sub = _responseCtrl.stream.listen((r) {
      if (!c.isCompleted) { c.complete(r); sub.cancel(); }
    });
    return c.future.timeout(const Duration(seconds: 30), onTimeout: () {
      sub.cancel();
      throw TimeoutException('Timeout odpowiedzi backendu');
    });
  }

  /// Pyta backend (root) czy jest internet – używa ping/curl po stronie systemu.
  /// Dokładniejsze niż TCP z poziomu Dart (działa nawet gdy Flutter jest sandboxowany).
  Future<bool> checkInternet() async {
    try {
      final r = await _send({'action': 'CheckInternet'});
      return r['data']?['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadConfig() async {
    try {
      final r = await _send({'action': 'GetConfig'});
      if (r['success'] == true && r['data'] != null) {
        config = InstallerConfig.fromJson(r['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<SystemInfo?> getSystemInfo() async {
    try {
      final r = await _send({'action': 'GetSystemInfo'});
      if (r['success'] == true && r['data'] != null) {
        return SystemInfo.fromJson(r['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<List<DiskInfo>> getDisks() async {
    try {
      final r = await _send({'action': 'GetDisks'});
      if (r['success'] == true && r['data'] != null) {
        return (r['data'] as List<dynamic>)
        .map((d) => DiskInfo.fromJson(d as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<NetworkInterface>> getNetworkInterfaces() async {
    try {
      final r = await _send({'action': 'GetNetworkInterfaces'});
      if (r['success'] == true && r['data'] != null) {
        return (r['data'] as List<dynamic>)
        .map((i) => NetworkInterface.fromJson(i as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<WifiNetwork>> getWifiNetworks(String iface) async {
    try {
      final r = await _send({'action': 'GetWifiNetworks', 'data': {'interface': iface}});
      if (r['success'] == true && r['data'] != null) {
        return (r['data'] as List<dynamic>)
        .map((n) => WifiNetwork.fromJson(n as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> connectWifi(String iface, String ssid, {String? password}) async {
    try {
      final r = await _send({'action': 'ConnectWifi', 'data': {
        'interface': iface, 'ssid': ssid, 'password': password,
      }});
      return r['success'] == true;
    } catch (_) { return false; }
  }

  Future<bool> connectEthernet(String iface) async {
    try {
      final r = await _send({'action': 'ConnectEthernet', 'data': {'interface': iface}});
      return r['success'] == true;
    } catch (_) { return false; }
  }

  /// FIX: zwraca List<LocaleInfo> (nie List<dynamic>)
  Future<List<LocaleInfo>> getLocales() async {
    try {
      final r = await _send({'action': 'GetLocales'});
      if (r['success'] == true && r['data'] != null) {
        return (r['data'] as List<dynamic>)
        .map((e) => LocaleInfo.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// FIX: zwraca List<TimezoneInfo>
  Future<List<TimezoneInfo>> getTimezones() async {
    try {
      final r = await _send({'action': 'GetTimezones'});
      if (r['success'] == true && r['data'] != null) {
        return (r['data'] as List<dynamic>)
        .map((e) => TimezoneInfo.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// FIX: zwraca List<KeyboardLayout>
  Future<List<KeyboardLayout>> getKeyboardLayouts() async {
    try {
      final r = await _send({'action': 'GetKeyboardLayouts'});
      if (r['success'] == true && r['data'] != null) {
        return (r['data'] as List<dynamic>)
        .map((e) => KeyboardLayout.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> setLocaleConfig(String locale, String timezone, String keyboard) async {
    await _send({'action': 'SetLocaleConfig', 'data': {
      'locale': locale, 'timezone': timezone, 'keyboard': keyboard,
    }});
  }

  Future<void> setPartitionPlan(Map<String, dynamic> plan) async {
    await _send({'action': 'SetPartitionPlan', 'data': {'plan': plan}});
  }

  Future<void> setUserConfig(Map<String, dynamic> user) async {
    await _send({'action': 'SetUserConfig', 'data': {'user': user}});
  }

  Future<bool> startInstallation() async {
    try {
      final r = await _send({'action': 'StartInstallation'});
      return r['success'] == true;
    } catch (_) { return false; }
  }

  /// FIX: zwraca InstallProgress? (nullable) – install_screen sprawdza != null
  Future<InstallProgress?> getInstallProgress() async {
    try {
      final r = await _send({'action': 'GetInstallProgress'});
      if (r['success'] == true && r['data'] != null) {
        return InstallProgress.fromJson(r['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<void> cancelInstallation() async {
    try { await _send({'action': 'CancelInstallation'}); } catch (_) {}
  }

  void dispose() {
    _socket?.destroy();
    _responseCtrl.close();
  }
}
