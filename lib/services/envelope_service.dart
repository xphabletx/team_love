import 'package:cloud_firestore/cloud_firestore.dart';

class EnvelopeDto {
  final String id;
  final String name;
  final double target;
  final double balance;
  final double incomeShare;
  final String currency;
  final int? colorHex;

  EnvelopeDto({
    required this.id,
    required this.name,
    required this.target,
    required this.balance,
    required this.incomeShare,
    this.currency = 'GBP',
    this.colorHex,
  });

  factory EnvelopeDto.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data()!;
    return EnvelopeDto(
      id: d.id,
      name: (data['name'] ?? '') as String,
      target: (data['target'] as num? ?? 0).toDouble(),
      balance: (data['balance'] as num? ?? 0).toDouble(),
      incomeShare: (data['incomeShare'] as num? ?? 0).toDouble(),
      currency: (data['currency'] as String?) ?? 'GBP',
      colorHex: data['colorHex'] as int?,
    );
  }
}

class EnvelopeService {
  EnvelopeService._();
  static final instance = EnvelopeService._();
  final _db = FirebaseFirestore.instance;

  Stream<List<EnvelopeDto>> streamEnvelopes(String workspaceId) {
    return _db
        .collection('workspaces')
        .doc(workspaceId)
        .collection('envelopes')
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => EnvelopeDto.fromDoc(d)).toList());
  }

  Future<void> addEnvelope(
    String workspaceId, {
    required String name,
    double target = 0,
    double balance = 0,
    double incomeShare = 0,
  }) async {
    await _db
        .collection('workspaces')
        .doc(workspaceId)
        .collection('envelopes')
        .add({
          'name': name,
          'currency': 'GBP',
          'target': target,
          'balance': balance,
          'incomeShare': incomeShare,
          'colorHex': null,
        });
  }
}
