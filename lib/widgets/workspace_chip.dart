import 'package:flutter/material.dart';
import 'workspace_scope.dart';

class WorkspaceChip extends StatelessWidget {
  const WorkspaceChip({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceScope.of(context);
    final usingWs = scope?.usingWorkspace ?? false;
    final label = usingWs ? 'Workspace' : 'Local';
    return ActionChip(
      avatar: Icon(usingWs ? Icons.groups : Icons.phone_iphone, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
