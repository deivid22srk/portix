import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/formatters.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[p.bg, p.bgSoft],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        Positioned(
          top: -180,
          right: -120,
          child: IgnorePointer(
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    p.primary.withValues(alpha: p.dark ? 0.22 : 0.12),
                    p.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -160,
          left: -140,
          child: IgnorePointer(
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    p.secondary.withValues(alpha: p.dark ? 0.13 : 0.10),
                    p.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.blur = false,
    this.glow = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool blur;
  final bool glow;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: color == null
            ? LinearGradient(
                colors: <Color>[
                  p.surfaceHigh.withValues(alpha: p.dark ? 0.88 : 1),
                  p.surface.withValues(alpha: p.dark ? 0.62 : 0.94),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: color,
        border: Border.all(color: p.line),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          if (glow)
            BoxShadow(
              color: p.primary.withValues(alpha: 0.22),
              blurRadius: 40,
              offset: const Offset(0, 14),
            ),
        ],
      ),
      child: child,
    );
    if (!blur) {
      return panel;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: panel,
      ),
    );
  }
}

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptics = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptics;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (TapDownDetails _) => _setPressed(true) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTapUp: enabled ? (TapUpDetails _) => _setPressed(false) : null,
      onLongPress: widget.onLongPress,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptics) {
                HapticFeedback.selectionClick();
              }
              widget.onTap?.call();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.height = 54,
    this.expand = true,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final bool expand;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final bool enabled = onPressed != null && !isLoading;
    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: enabled ? p.brand : LinearGradient(
          colors: <Color>[p.surfaceHigh, p.surfaceHigh.withValues(alpha: 0.8)],
        ),
        border: enabled ? null : Border.all(color: p.line),
        boxShadow: enabled
            ? <BoxShadow>[
                BoxShadow(
                  color: p.primary.withValues(alpha: 0.32),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (isLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (icon != null)
            Icon(icon, size: 20, color: enabled ? Colors.white : p.muted),
          if (isLoading || icon != null) const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.titleSmall?.copyWith(
                color: enabled ? Colors.white : p.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: expand ? SizedBox(width: double.infinity, child: content) : content,
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 52,
    this.expand = false,
    this.active = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool expand;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: active
              ? p.primary.withValues(alpha: 0.16)
              : p.surface.withValues(alpha: p.dark ? 0.55 : 0.9),
          border: Border.all(
            color: active ? p.primary.withValues(alpha: 0.5) : p.line,
          ),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 19, color: active ? p.primary : p.text),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelLarge?.copyWith(
                  color: active ? p.primary : p.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IconGlassButton extends StatelessWidget {
  const IconGlassButton({
    super.key,
    required this.icon,
    this.onTap,
    this.active = false,
    this.size = 44,
    this.tooltip,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final double size;
  final String? tooltip;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final Widget button = Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? p.primary.withValues(alpha: 0.18)
              : p.surface.withValues(alpha: p.dark ? 0.6 : 0.9),
          border: Border.all(
            color: active ? p.primary.withValues(alpha: 0.55) : p.line,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(icon, size: size * 0.46, color: active ? p.primary : p.text),
            if (badge != null)
              Positioned(top: size * 0.16, right: size * 0.16, child: badge!),
          ],
        ),
      ),
    );
    if (tooltip == null) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: context.texts.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: context.texts.bodySmall?.copyWith(color: p.muted),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: <Widget>[
                    Text(
                      actionLabel!,
                      style: context.texts.labelMedium?.copyWith(
                        color: p.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 18, color: p.secondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.trailing,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 14,
          vertical: dense ? 8 : 10,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? p.primary.withValues(alpha: p.dark ? 0.20 : 0.12)
              : p.surface.withValues(alpha: p.dark ? 0.62 : 0.92),
          border: Border.all(
            color: selected ? p.primary.withValues(alpha: 0.55) : p.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (leading != null) ...<Widget>[leading!, const SizedBox(width: 6)],
            Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: selected ? p.text : p.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (trailing != null) ...<Widget>[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}

class BadgeChip extends StatelessWidget {
  const BadgeChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final Color tone = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class RatingLine extends StatelessWidget {
  const RatingLine({
    super.key,
    required this.rating,
    this.count = 0,
    this.compact = false,
  });

  final double rating;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    if (rating <= 0) {
      return Text(
        '—',
        style: context.texts.labelMedium?.copyWith(color: p.muted),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: compact ? 14 : 16, color: p.warning),
        const SizedBox(width: 3),
        Text(
          formatRating(rating),
          style: context.texts.labelMedium?.copyWith(
            color: p.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (count > 0 && !compact) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: context.texts.labelSmall?.copyWith(color: p.muted),
          ),
        ],
      ],
    );
  }
}

class StarPicker extends StatelessWidget {
  const StarPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 34,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 1; index <= 5; index += 1)
          Pressable(
            onTap: () => onChanged(index),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.08),
              child: Icon(
                index <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: index <= value ? p.warning : p.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class AppToggle extends StatelessWidget {
  const AppToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: value ? p.primary : p.surfaceHigh,
          border: Border.all(color: value ? p.primary : p.line),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : p.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class GradientProgress extends StatelessWidget {
  const GradientProgress({
    super.key,
    required this.value,
    this.height = 8,
  });

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (BuildContext context, double animated, Widget? child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(color: p.surfaceHigh),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: animated,
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: p.brand),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SegmentItem<T> {
  const SegmentItem({required this.value, required this.label});

  final T value;
  final String label;
}

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final List<SegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: p.surface.withValues(alpha: p.dark ? 0.7 : 0.95),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: <Widget>[
          for (final SegmentItem<T> item in items)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(item.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: item.value == value
                        ? p.primary.withValues(alpha: p.dark ? 0.22 : 0.12)
                        : Colors.transparent,
                  ),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: context.texts.labelMedium?.copyWith(
                      color: item.value == value ? p.text : p.muted,
                      fontWeight:
                          item.value == value ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
