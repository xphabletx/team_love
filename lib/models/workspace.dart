// lib/models/workspace.dart
import 'package:flutter/foundation.dart';

enum ConsentLevel {
  none, // no access
  view, // can see my data
  contribute, // can add items but not edit mine
  edit, // can edit my items
}

@immutable
class MemberConsent {
  final String memberUid; // Firebase UID or locally generated id
  final Map<String, ConsentLevel> feature;
  // keys: 'budget', 'ledger', 'calendar', 'meals', 'shopping', 'recipes'
  // values: ConsentLevel for *my* data visibility/editing by this member

  const MemberConsent({required this.memberUid, required this.feature});

  factory MemberConsent.empty(String uid) =>
      MemberConsent(memberUid: uid, feature: const {});

  Map<String, dynamic> toJson() => {
    'memberUid': memberUid,
    'feature': feature.map((k, v) => MapEntry(k, v.name)),
  };

  factory MemberConsent.fromJson(Map<String, dynamic> m) => MemberConsent(
    memberUid: m['memberUid'] as String,
    feature: (m['feature'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(
        k,
        ConsentLevel.values.firstWhere(
          (e) => e.name == (v as String? ?? 'none'),
          orElse: () => ConsentLevel.none,
        ),
      ),
    ),
  );
}

@immutable
class WorkspaceMember {
  final String uid; // unique id (Firebase Auth uid or local id)
  final String display; // "Terry", "Alex", etc.
  final String? avatarUrl;

  const WorkspaceMember({
    required this.uid,
    required this.display,
    this.avatarUrl,
  });

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'display': display,
    'avatarUrl': avatarUrl,
  };

  factory WorkspaceMember.fromJson(Map<String, dynamic> m) => WorkspaceMember(
    uid: m['uid'] as String,
    display: m['display'] as String? ?? '',
    avatarUrl: m['avatarUrl'] as String?,
  );
}

@immutable
class Workspace {
  final String id; // workspace id
  final String name;
  final List<WorkspaceMember> members;
  // “My consent given to others about *my* data”
  final List<MemberConsent> consents;

  const Workspace({
    required this.id,
    required this.name,
    required this.members,
    required this.consents,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'members': members.map((e) => e.toJson()).toList(),
    'consents': consents.map((e) => e.toJson()).toList(),
  };

  factory Workspace.fromJson(Map<String, dynamic> m) => Workspace(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    members: (m['members'] as List<dynamic>? ?? [])
        .map((e) => WorkspaceMember.fromJson(e as Map<String, dynamic>))
        .toList(),
    consents: (m['consents'] as List<dynamic>? ?? [])
        .map((e) => MemberConsent.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
