import 'package:flutter/material.dart';

// TODO: import your real service once ready
// import '../services/workspace_service.dart';

class WorkspaceSetupScreen extends StatefulWidget {
  const WorkspaceSetupScreen({super.key});

  @override
  State<WorkspaceSetupScreen> createState() => _WorkspaceSetupScreenState();
}

class _WorkspaceSetupScreenState extends State<WorkspaceSetupScreen> {
  final codeCtrl = TextEditingController();
  String? createdCode;
  bool busy = false;

  // TODO: replace with Firestore stream of memberships
  final List<_Workspace> myWorkspaces = [];

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => busy = true);
    // final res = await WorkspaceService.instance.createWorkspace();
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      createdCode = 'ABC123'; // res.joinCode;
      myWorkspaces.add(_Workspace(id: 'w1', name: 'Home Budget'));
      busy = false;
    });
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workspace Created'),
        content: Text(
          'Share this join code with your partner:\n\n$createdCode',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _join() async {
    setState(() => busy = true);
    // final ok = await WorkspaceService.instance.joinByCode(codeCtrl.text);
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      myWorkspaces.add(_Workspace(id: 'w2', name: 'Parents Budget'));
      busy = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Joined workspace')));
  }

  Future<void> _leave(_Workspace w) async {
    // await WorkspaceService.instance.leaveWorkspace(w.id);
    setState(() => myWorkspaces.remove(w));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your workspaces',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (myWorkspaces.isEmpty)
            const Text('You are not in any workspaces yet.')
          else
            ...myWorkspaces.map(
              (w) => Card(
                child: ListTile(
                  title: Text(w.name),
                  subtitle: Text('ID: ${w.id}'),
                  trailing: TextButton(
                    onPressed: () => _leave(w),
                    child: const Text('Leave'),
                  ),
                  onTap: () {
                    // TODO: set active workspace in app state
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Selected ${w.name}')),
                    );
                  },
                ),
              ),
            ),
          const Divider(height: 32),
          FilledButton.icon(
            onPressed: busy ? null : _create,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Create Workspace'),
          ),
          if (createdCode != null) ...[
            const SizedBox(height: 8),
            Text('Your join code: $createdCode'),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: codeCtrl,
            decoration: const InputDecoration(
              labelText: 'Join code',
              hintText: 'e.g. 7XK9QZ',
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : _join,
            icon: const Icon(Icons.login),
            label: const Text('Join Workspace'),
          ),
        ],
      ),
    );
  }
}

class _Workspace {
  _Workspace({required this.id, required this.name});
  final String id;
  final String name;
}
