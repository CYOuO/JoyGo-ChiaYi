import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

class TripMember {
  final String id;        // Firestore doc id
  final String? uid;      // Firebase UID (null = 外部成員)
  final String name;
  final String? photoUrl;
  final bool isExternal;

  const TripMember({
    required this.id,
    this.uid,
    required this.name,
    this.photoUrl,
    this.isExternal = false,
  });

  factory TripMember.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TripMember(
      id:         doc.id,
      uid:        d['uid']       as String?,
      name:       d['name']      as String? ?? '未知成員',
      photoUrl:   d['photoUrl']  as String?,
      isExternal: d['isExternal'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid':        uid,
    'name':       name,
    'photoUrl':   photoUrl,
    'isExternal': isExternal,
  };

  /// 用於顯示的頭像首字
  String get initial => name.isNotEmpty ? name[0] : '?';
}

class ExpenseRecord {
  final String id;
  final String title;
  final String category;
  final int amount;
  final String paidByMemberId;   // TripMember.id
  final List<String> splitMemberIds;
  final DateTime date;
  final DateTime createdAt;

  const ExpenseRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.paidByMemberId,
    required this.splitMemberIds,
    required this.date,
    required this.createdAt,
  });

  factory ExpenseRecord.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ExpenseRecord(
      id:              doc.id,
      title:           d['title']    as String? ?? '',
      category:        d['category'] as String? ?? '其他',
      amount:          (d['amount']  as num?)?.toInt() ?? 0,
      paidByMemberId:  d['paidByMemberId'] as String? ?? '',
      splitMemberIds:  List<String>.from(d['splitMemberIds'] ?? []),
      date:            (d['date']      as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt:       (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'title':          title,
    'category':       category,
    'amount':         amount,
    'paidByMemberId': paidByMemberId,
    'splitMemberIds': splitMemberIds,
    'date':           Timestamp.fromDate(date),
    'createdAt':      FieldValue.serverTimestamp(),
  };

  int get perShare =>
      splitMemberIds.isEmpty ? 0 : (amount / splitMemberIds.length).round();
}

// ═══════════════════════════════════════════════════════════
// ExpenseService
// ═══════════════════════════════════════════════════════════

class ExpenseService {
  static final _db   = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // ── Members ───────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> _membersRef(String tripId) =>
      _db.collection('trips').doc(tripId).collection('expenseMembers');

  static Stream<List<TripMember>> membersStream(String tripId) =>
      _membersRef(tripId)
          .orderBy('addedAt')
          .snapshots()
          .map((s) => s.docs.map(TripMember.fromDoc).toList());

  /// 加入行程成員（用 Firebase 用戶）
  static Future<TripMember> addFirebaseMember(String tripId, User user) async {
    final ref = _membersRef(tripId).doc(user.uid);
    final data = {
      'uid':        user.uid,
      'name':       user.displayName ?? user.email ?? user.uid.substring(0, 6),
      'photoUrl':   user.photoURL,
      'isExternal': false,
      'addedAt':    FieldValue.serverTimestamp(),
    };
    await ref.set(data, SetOptions(merge: true));
    return TripMember(
      id: user.uid, uid: user.uid,
      name: data['name'] as String,
      photoUrl: user.photoURL,
    );
  }

  /// 加入外部成員（無 app 帳號）
  static Future<TripMember> addExternalMember(String tripId, String name) async {
    final ref = _membersRef(tripId).doc();
    await ref.set({
      'uid':        null,
      'name':       name,
      'photoUrl':   null,
      'isExternal': true,
      'addedAt':    FieldValue.serverTimestamp(),
    });
    return TripMember(id: ref.id, name: name, isExternal: true);
  }

  static Future<void> removeMember(String tripId, String memberId) =>
      _membersRef(tripId).doc(memberId).delete();

  /// 確保行程建立者已在成員清單中
  static Future<void> ensureSelfInMembers(String tripId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await _membersRef(tripId).doc(user.uid).get();
    if (!doc.exists) await addFirebaseMember(tripId, user);
  }

  // ── Expenses ──────────────────────────────────────────────
  static CollectionReference<Map<String, dynamic>> _expensesRef(String tripId) =>
      _db.collection('trips').doc(tripId).collection('expenses');

  static Stream<List<ExpenseRecord>> expensesStream(String tripId) =>
      _expensesRef(tripId)
          .orderBy('date', descending: true)
          .snapshots()
          .map((s) => s.docs.map(ExpenseRecord.fromDoc).toList());

  static Future<void> addExpense(String tripId, ExpenseRecord rec) =>
      _expensesRef(tripId).add(rec.toMap());

  static Future<void> deleteExpense(String tripId, String expenseId) =>
      _expensesRef(tripId).doc(expenseId).delete();

  static Future<void> updateExpense(
      String tripId, String expenseId, Map<String, dynamic> data) =>
      _expensesRef(tripId).doc(expenseId).update(data);

  // ── Settlement calc (pure, no Firebase) ──────────────────
  static Map<String, int> calcPaid(List<ExpenseRecord> expenses, List<TripMember> members) {
    final map = {for (final m in members) m.id: 0};
    for (final e in expenses) {
      map[e.paidByMemberId] = (map[e.paidByMemberId] ?? 0) + e.amount;
    }
    return map;
  }

  static Map<String, int> calcOwed(List<ExpenseRecord> expenses, List<TripMember> members) {
    final map = {for (final m in members) m.id: 0};
    for (final e in expenses) {
      if (e.splitMemberIds.isEmpty) continue;
      final share = (e.amount / e.splitMemberIds.length).round();
      for (final mid in e.splitMemberIds) {
        map[mid] = (map[mid] ?? 0) + share;
      }
    }
    return map;
  }

  static Map<String, int> calcBalance(List<ExpenseRecord> expenses, List<TripMember> members) {
    final paid  = calcPaid (expenses, members);
    final owed  = calcOwed (expenses, members);
    return {for (final m in members) m.id: (paid[m.id] ?? 0) - (owed[m.id] ?? 0)};
  }

  /// 最少轉帳方案
  static List<({String fromId, String toId, int amount})> calcSettlements(
      List<ExpenseRecord> expenses, List<TripMember> members) {
    final balance = Map<String, int>.from(calcBalance(expenses, members));
    final result  = <({String fromId, String toId, int amount})>[];
    while (true) {
      final debtors   = balance.entries.where((e) => e.value < -1)
          .toList()..sort((a, b) => a.value.compareTo(b.value));
      final creditors = balance.entries.where((e) => e.value > 1)
          .toList()..sort((a, b) => b.value.compareTo(a.value));
      if (debtors.isEmpty || creditors.isEmpty) break;
      final debtor = debtors.first, creditor = creditors.first;
      final amt = debtor.value.abs() < creditor.value
          ? debtor.value.abs() : creditor.value;
      result.add((fromId: debtor.key, toId: creditor.key, amount: amt));
      balance[debtor.key]   = (balance[debtor.key] ?? 0) + amt;
      balance[creditor.key] = (balance[creditor.key] ?? 0) - amt;
    }
    return result;
  }
}
