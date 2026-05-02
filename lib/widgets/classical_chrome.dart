import 'package:flutter/material.dart';
import '../theme/small_caps.dart';

class DoubleRule extends StatelessWidget {
  const DoubleRule({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).dividerColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: c),
        const SizedBox(height: 3),
        Divider(height: 1, thickness: 1, color: c),
      ],
    );
  }
}

class DossierPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DossierPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.dividerColor),
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class DossierHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const DossierHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SmallCapsText(
                title,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            trailing ?? const SizedBox.shrink(),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: muted),
        ],
        const SizedBox(height: 10),
        const DoubleRule(),
      ],
    );
  }
}
