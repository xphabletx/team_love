// lib/widgets/scope_badge.dart
import 'package:flutter/material.dart';
import '../services/app_scope.dart';

class ScopeBadge extends StatefulWidget {
  const ScopeBadge({super.key});
  @override
  State<ScopeBadge> createState() => _ScopeBadgeState();
}

class _ScopeBadgeState extends State<ScopeBadge> {
  final _scope = AppScope.instance;

  @override
  void initState() {
    super.initState();
    _scope.addListener(_onScope);
  }

  @override
  void dispose() {
    _scope.removeListener(_onScope);
    super.dispose();
  }

  void _onScope() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = _scope.label; // “Local” or workspace name
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _scope.mode == AppScopeMode.local
                  ? Icons.phone_iphone
                  : Icons.group,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: fg)),
          ],
        ),
      ),
    );
  }
}
