// lib/services/app_scope.dart
import 'package:flutter/foundation.dart';

enum AppScopeMode { local, workspace }

class WorkspaceRef {
  final String id;
  final String name;
  const WorkspaceRef({required this.id, required this.name});
}

class AppScope extends ChangeNotifier {
  AppScope._();
  static final AppScope instance = AppScope._();

  AppScopeMode _mode = AppScopeMode.local;
  WorkspaceRef? _ws;

  AppScopeMode get mode => _mode;
  WorkspaceRef? get workspace => _ws;

  /// Read-only label for UI badges (“Local” or workspace name)
  String get label =>
      _mode == AppScopeMode.local ? 'Local' : (_ws?.name ?? 'Workspace');

  /// These will be called from a central Settings screen (app-wide).
  void setLocal() {
    _mode = AppScopeMode.local;
    _ws = null;
    notifyListeners();
  }

  void setWorkspace(WorkspaceRef ref) {
    _mode = AppScopeMode.workspace;
    _ws = ref;
    notifyListeners();
  }

  /// Convenience: initialize from elsewhere (e.g., after sign-in)
  void setFrom({required AppScopeMode mode, WorkspaceRef? workspace}) {
    _mode = mode;
    _ws = workspace;
    notifyListeners();
  }
}
