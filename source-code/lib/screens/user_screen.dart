import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/installer_state.dart';
import '../widgets/shared_widgets.dart';

class UserScreen extends ConsumerStatefulWidget {
  const UserScreen({super.key});

  @override
  ConsumerState<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends ConsumerState<UserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _hostnameCtrl = TextEditingController(text: 'hackeros');
  bool _autologin = false;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl.addListener(_onFullNameChanged);
  }

  void _onFullNameChanged() {
    final name = _fullNameCtrl.text;
    if (name.isNotEmpty) {
      final suggested = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (_usernameCtrl.text.isEmpty || _isAutoUsername) {
        _usernameCtrl.text = suggested;
        _isAutoUsername = true;
      }
    }
  }

  bool _isAutoUsername = true;

  String? _validateUsername(String? v) {
    if (v == null || v.isEmpty) return 'Username is required';
    if (v.length < 2) return 'Username must be at least 2 characters';
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(v)) {
      return 'Use only lowercase letters, numbers, - and _';
    }
    if (['root', 'admin', 'daemon', 'sys', 'bin'].contains(v)) {
      return 'This username is reserved';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  String? _validateHostname(String? v) {
    if (v == null || v.isEmpty) return 'Hostname is required';
    if (!RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$').hasMatch(v)) {
      return 'Use letters, numbers, and hyphens only';
    }
    return null;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _hostnameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() == true) {
      ref.read(installerProvider.notifier).setUserInfo(
            fullName: _fullNameCtrl.text,
            username: _usernameCtrl.text,
            password: _passwordCtrl.text,
            hostname: _hostnameCtrl.text,
            autologin: _autologin,
          );
      ref.read(installerProvider.notifier).nextStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepContainer(
      title: 'Your Account',
      subtitle: 'Set up your user account and computer name.',
      footer: NavButtons(
        onBack: () => ref.read(installerProvider.notifier).prevStep(),
        onNext: _save,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Personal Info'),
            TextFormField(
              controller: _fullNameCtrl,
              validator: (v) => v?.isEmpty == true ? 'Name is required' : null,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                hintText: 'e.g. Jane Smith',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: _usernameCtrl,
              validator: _validateUsername,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _isAutoUsername = false,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'e.g. jsmith',
                prefixIcon: Icon(Icons.alternate_email_rounded),
                helperText: 'Used for your home directory and login',
              ),
            ),

            const SizedBox(height: 24),
            const SectionHeader(title: 'Password'),

            PasswordField(
              controller: _passwordCtrl,
              label: 'Password',
              hint: 'Choose a strong password',
              validator: _validatePassword,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 14),

            PasswordField(
              controller: _confirmCtrl,
              label: 'Confirm Password',
              hint: 'Repeat your password',
              validator: _validateConfirm,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 24),
            const SectionHeader(title: 'Computer Name'),

            TextFormField(
              controller: _hostnameCtrl,
              validator: _validateHostname,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                labelText: 'Hostname',
                hintText: 'e.g. my-hackeros-pc',
                prefixIcon: Icon(Icons.computer_outlined),
                helperText: 'Name of your computer on the network',
              ),
            ),

            const SizedBox(height: 24),
            const SectionHeader(title: 'Login Options'),

            HCard(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Automatic Login',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Sign in automatically on startup (less secure)',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autologin,
                    onChanged: (v) => setState(() => _autologin = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Password strength indicator
            if (_passwordCtrl.text.isNotEmpty)
              _PasswordStrength(password: _passwordCtrl.text),
          ],
        ),
      ),
    );
  }
}

class _PasswordStrength extends StatefulWidget {
  final String password;
  const _PasswordStrength({required this.password});

  @override
  State<_PasswordStrength> createState() => _PasswordStrengthState();
}

class _PasswordStrengthState extends State<_PasswordStrength> {
  @override
  Widget build(BuildContext context) {
    final strength = _calcStrength(widget.password);
    final (label, color, bars) = switch (strength) {
      >= 4 => ('Strong', AppTheme.accentSuccess, 4),
      >= 3 => ('Good', const Color(0xFF84CC16), 3),
      >= 2 => ('Fair', AppTheme.accentWarning, 2),
      _ => ('Weak', AppTheme.accentDanger, 1),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Password Strength: ',
                style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textMuted),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              4,
              (i) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i < bars ? color : AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _calcStrength(String pw) {
    int score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pw)) score++;
    return score;
  }
}
