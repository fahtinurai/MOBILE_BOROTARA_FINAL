import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Path: users/{userId}/notifications
  static CollectionReference<Map<String, dynamic>> _col(String userId) {
    return _db.collection('users').doc(userId).collection('notifications');
  }

  /// Stream list notifikasi sehingga yang terbaru diatas
  /// - orderBy created_at (kalau string ISO, tetap bisa diorder kalau format ISO)
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamNotifications({
    required String userId,
    int limit = 100,
  }) {
    return _col(userId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Stream untuk menghitung unread badge
  static Stream<int> streamUnreadCount({
    required String userId,
  }) {
    return _col(userId)
        .where('unread', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Menandai 1 notifikasi supaya terbaca
  static Future<void> markAsRead({
    required String userId,
    required String notificationId,
  }) async {
    final uid = userId.trim();
    final nid = notificationId.trim();
    if (uid.isEmpty || nid.isEmpty) return;

    await _col(uid).doc(nid).update({
      'unread': false,
      'read_at': DateTime.now().toIso8601String(),
    });
  }

  /// Menandai semua notifikasi dari unread menjadi read
  static Future<void> markAllAsRead({
    required String userId,
    int batchSize = 200,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    final q = await _col(uid)
        .where('unread', isEqualTo: true)
        .limit(batchSize)
        .get();

    if (q.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {
        'unread': false,
        'read_at': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit();
  }
}
