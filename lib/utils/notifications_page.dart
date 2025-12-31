import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_service.dart';
import '../driver_report_detail.dart';

class NotificationsPage extends StatefulWidget {
  final String token;
  final String userId; // ✅ sesuai driver_home.dart (String)
  final String role;   // 'driver' / 'technician' dll

  const NotificationsPage({
    super.key,
    required this.token,
    required this.userId,
    required this.role,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    // ✅ mark as read otomatis saat buka inbox
    _markAllRead();
  }

  Future<void> _markAllRead() async {
    if (_marking) return;
    _marking = true;
    try {
      await FirestoreService.markAllAsRead(userId: widget.userId);
    } catch (_) {
      // jangan crash
    } finally {
      _marking = false;
    }
  }

  Map<String, dynamic> _toMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  String _str(dynamic v, [String fallback = '']) {
    final s = v?.toString();
    if (s == null || s.trim().isEmpty) return fallback;
    return s;
  }

  DateTime? _parseCreatedAt(dynamic createdAt) {
    try {
      if (createdAt is Timestamp) return createdAt.toDate();

      // kalau server kamu pernah simpan epoch ms
      if (createdAt is int) {
        // heuristik: kalau terlalu kecil, anggap seconds
        if (createdAt < 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
        }
        return DateTime.fromMillisecondsSinceEpoch(createdAt);
      }

      final s = createdAt?.toString().trim() ?? '';
      if (s.isEmpty) return null;

      // ISO string dari Laravel now()->toISOString()
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  String _fmtDateTime(dynamic createdAt) {
    final dt = _parseCreatedAt(createdAt);
    if (dt == null) return '';

    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _handleTap({
    required String notifId,
    required Map<String, dynamic> notif,
  }) async {
    // ✅ mark as read saat ditap
    try {
      await FirestoreService.markAsRead(
        userId: widget.userId,
        notificationId: notifId,
      );
    } catch (_) {}

    // payload bisa ada di field "data"
    final payload = _toMap(notif['data']);
    final merged = <String, dynamic>{...notif, ...payload};

    final role = _str(merged['role'], '').toLowerCase();
    if (role.isNotEmpty && role != widget.role.toLowerCase()) {
      return; // role beda → abaikan
    }

    // ✅ tap notif → buka DriverReportDetailPage
    final reportId = _toInt(merged['report_id'] ?? merged['id'], 0);
    if (reportId > 0) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverReportDetailPage(
            token: widget.token,
            reportId: reportId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.userId.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          IconButton(
            tooltip: 'Tandai semua dibaca',
            onPressed: _markAllRead,
            icon: const Icon(Icons.done_all),
          ),
        ],
      ),
      body: uid.isEmpty
          ? const Center(child: Text('User ID kosong.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.streamNotifications(userId: uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Gagal memuat notifikasi.\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Belum ada notifikasi.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();

                    final title = _str(m['title'], 'Notifikasi');
                    final body = _str(m['body'], '');
                    final unread = (m['unread'] == true);
                    final when = _fmtDateTime(m['created_at']);

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          unread
                              ? Icons.notifications_active
                              : Icons.notifications,
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: unread ? FontWeight.w900 : FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (body.isNotEmpty) Text(body),
                            if (when.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  when,
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: unread
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        onTap: () => _handleTap(notifId: d.id, notif: m),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
