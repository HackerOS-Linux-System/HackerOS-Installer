import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StepContainer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final bool scrollable;

  const StepContainer({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: child,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: child,
                ),
        ),
        if (footer != null)
          Container(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.surfaceBorder)),
            ),
            child: footer!,
          ),
      ],
    );
  }
}

class NavButtons extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final String backLabel;
  final bool nextEnabled;
  final bool isLoading;
  final Color? nextColor;

  const NavButtons({
    super.key,
    this.onBack,
    this.onNext,
    this.nextLabel = 'Continue',
    this.backLabel = 'Back',
    this.nextEnabled = true,
    this.isLoading = false,
    this.nextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text(backLabel),
          ),
        const Spacer(),
        ElevatedButton(
          onPressed: nextEnabled && !isLoading ? onNext : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: nextColor ?? AppTheme.accent,
            minimumSize: const Size(140, 52),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nextLabel),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
        ),
      ],
    );
  }
}

class HCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsets? padding;

  const HCard({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent.withOpacity(0.1) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppTheme.accent : AppTheme.surfaceBorder,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor ?? AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class GradientBadge extends StatelessWidget {
  final String text;
  final List<Color>? colors;

  const GradientBadge({super.key, required this.text, this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors ?? [AppTheme.accent, AppTheme.accentSecondary],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class WifiSignalIcon extends StatelessWidget {
  final int bars; // 1-4
  final Color? color;
  final double size;

  const WifiSignalIcon({
    super.key,
    required this.bars,
    this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.accent;
    return Icon(
      bars >= 4
          ? Icons.wifi
          : bars == 3
              ? Icons.wifi_2_bar
              : Icons.wifi_1_bar,
      color: c,
      size: size,
    );
  }
}

class LoadingDots extends StatefulWidget {
  final String label;
  const LoadingDots({super.key, required this.label});

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
          ),
        ),
        const SizedBox(width: 10),
        Text(widget.label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.textInputAction,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppTheme.textMuted,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
