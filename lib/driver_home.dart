// driver_home.dart
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'API/api_service.dart';
import 'utils/auth_storage.dart';
import 'driver_report_detail.dart';
import 'models/api_damage_report.dart';
import 'utils/push_fcm.dart';
import 'main.dart' show LoginPage;

// ✅ NEW (Firestore Inbox Notifications)
import '../utils/notifications_page.dart';
import 'utils/firestore_service.dart';

class DriverHomePage extends StatefulWidget {
  final String token;
  const DriverHomePage({super.key, required this.token});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  late final ApiService api;

  int _tab = 0;
  bool loadingVehicles = false;
  bool loadingReports = false;

  String? errVehicles;
  String? errReports;
  String? msg;

  /// NOTE:
  /// Backend myVehicles() return list of VehicleAssignment with relation vehicle
  /// -> vehicles list here = assignments
  List<dynamic> vehicles = [];
  List<ApiDamageReport> reports = [];

  // ===== FILTER STATE =====
  String statusFilter = 'all';
  String searchPlate = '';

  String? selectedPlate;
  final descC = TextEditingController();

  // ===== Firebase listeners =====
  bool _fcmHandledInitial = false;

  // =====================================================
  // ✅ QUICK BOOKING (Opsi A: panel di Home via tombol "Booking")
  // =====================================================
  bool loadingQuickBooking = false;
  Map<String, dynamic>? quickBooking;

  DateTime? quickPreferredAt;
  final quickBookingNoteC = TextEditingController();

  // =====================================================
  // ✅ Firestore Notifications (Inbox)
  // =====================================================
  String? _userId;
  bool _loadingMe = false;

  @override
  void initState() {
    super.initState();
    api = ApiService(mode: ApiMode.dio, token: widget.token);

    _loadAll();
    _bindFirebaseHandlers();

    // ✅ ambil userId dari /me untuk path Firestore users/{userId}/notifications
    _loadMe();
  }

  // =====================================================
  // FIREBASE: Tap notif -> buka detail report driver
  // =====================================================
  void _bindFirebaseHandlers() {
    _handleInitialMessageOnce();

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleTapNotification(message.data);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final ctx = navKey.currentContext ?? context;
      final title = message.notification?.title ?? 'Notifikasi';
      final body = message.notification?.body ?? '';
      if (!mounted) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('$title${body.isNotEmpty ? " — $body" : ""}'),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _handleInitialMessageOnce() async {
    if (_fcmHandledInitial) return;
    _fcmHandledInitial = true;

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _handleTapNotification(initial.data);
      }
    } catch (_) {}
  }

  // =====================================================
  // ✅ UPDATED: support type = service_booking juga (sesuai controller admin)
  // - type: damage_report / service_booking
  // - role: driver
  // - report_id ada di payload
  // =====================================================
  void _handleTapNotification(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    final role = (data['role'] ?? '').toString().toLowerCase();
    final reportId =
        int.tryParse((data['report_id'] ?? data['id'] ?? '').toString()) ?? 0;

    // ✅ terima notif lama (damage_report) dan notif booking (service_booking)
    if (type != 'damage_report' && type != 'service_booking') return;
    if (role != 'driver') return;
    if (reportId <= 0) return;

    final ctx = navKey.currentContext ?? context;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) =>
            DriverReportDetailPage(token: widget.token, reportId: reportId),
      ),
    );
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadVehicles(), _loadReports()]);
  }

  // =========================
  // ✅ SAFE JSON HELPERS
  // =========================
  Map<String, dynamic>? _toMap(dynamic x) {
    if (x is Map<String, dynamic>) return x;
    if (x is Map) return Map<String, dynamic>.from(x);
    return null;
  }

  List<dynamic> _unwrapList(dynamic res) {
    // Backend driver endpoints mostly return list/object directly,
    // but keep tolerant unwrapping if ApiService wraps it.
    if (res is List) return res;
    if (res is Map && res['data'] is List) return res['data'] as List;
    if (res is Map && res['data'] is Map && (res['data']['data'] is List)) {
      return res['data']['data'] as List;
    }
    return <dynamic>[];
  }

  String _str(dynamic v, [String fallback = '-']) {
    final s = v?.toString();
    if (s == null || s.trim().isEmpty) return fallback;
    return s;
  }

  int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  // =====================================================
  // ✅ GET /me untuk ambil userId Firestore
  // - tetap tolerant dengan response {data:{...}} atau {...}
  // =====================================================
  Future<void> _loadMe() async {
    if (_loadingMe) return;
    _loadingMe = true;

    try {
      final me = await api.me();
      final m = _toMap(me);
      final dataMap = (m != null && m['data'] is Map) ? _toMap(m['data']) : null;

      // ambil id dari m atau m['data']
      final id = (m?['id'] ?? dataMap?['id'])?.toString();

      if (id != null && id.trim().isNotEmpty) {
        if (mounted) setState(() => _userId = id.trim());
      }
    } catch (_) {
      // kalau gagal, tombol notif tetap disabled
    } finally {
      _loadingMe = false;
    }
  }

  // =========================
  // Helpers: vehicle parsing (assignment-safe)
  // =========================
  Map<String, dynamic>? _vehicleMap(dynamic v) {
    final m = _toMap(v);
    if (m == null) return null;
    final vv = _toMap(m['vehicle']);
    return vv ?? m; // if already vehicle
  }

  String _plateFromVehicle(dynamic v) {
    final vv = _vehicleMap(v);
    return _str(vv?['plate_number'], '-');
  }

  String _brandFromVehicle(dynamic v) {
    final vv = _vehicleMap(v);
    return _str(vv?['brand'], '-');
  }

  /// ✅ IMPORTANT FIX:
  /// myVehicles() returns VehicleAssignment, so v['id'] is assignment id.
  /// Reminder endpoint expects vehicle id.
  int _vehicleIdFromVehicle(dynamic v) {
    final vv = _vehicleMap(v);
    return _toInt(vv?['id'], 0);
  }

  String _nextServiceAtFromVehicle(dynamic v) {
    final vv = _vehicleMap(v);
    return _str(vv?['next_service_at'], '-');
  }

  bool _reminderEnabledFromVehicle(dynamic v) {
    final vv = _vehicleMap(v);
    final x = vv?['reminder_enabled'];
    if (x is bool) return x;
    if (x == null) return false;
    return x.toString() == '1' || x.toString().toLowerCase() == 'true';
  }

  int _reminderDaysBeforeFromVehicle(dynamic v) {
    final vv = _vehicleMap(v);
    final x = vv?['reminder_days_before'];
    return _toInt(x, 3);
  }

  // =========================
  // ✅ Dropdown helper (anti duplikat & anti value tidak ada)
  // =========================
  Map<String, dynamic> _uniqueVehiclesByPlate() {
    final unique = <String, dynamic>{};
    for (final v in vehicles) {
      final plate = _plateFromVehicle(v).trim();
      if (plate.isEmpty || plate == '-') continue;
      unique.putIfAbsent(plate, () => v); // ambil yang pertama
    }
    return unique;
  }

  String? _safeSelectedPlateFromItems(List<DropdownMenuItem<String>> items) {
    final current = selectedPlate?.trim();
    if (current != null && current.isNotEmpty) {
      final exists = items.any((it) => it.value == current);
      if (exists) return current;
    }
    if (items.isNotEmpty) return items.first.value;
    return null;
  }

  // =========================
  // LOADERS
  // =========================
  Future<void> _loadVehicles() async {
    setState(() {
      loadingVehicles = true;
      errVehicles = null;
      msg = null;
    });

    try {
      final v = await api.driverVehicles(); // backend: myVehicles()
      setState(() {
        vehicles = v;
      });

      // ensure selectedPlate valid
      final unique = _uniqueVehiclesByPlate();
      final plates = unique.keys.toList();

      if (plates.isEmpty) {
        if (mounted) setState(() => selectedPlate = null);
      } else {
        final cur = selectedPlate?.trim();
        if (cur == null || cur.isEmpty || !unique.containsKey(cur)) {
          if (mounted) setState(() => selectedPlate = plates.first);
        }
      }
    } catch (e) {
      setState(() => errVehicles = e.toString());
    } finally {
      if (mounted) setState(() => loadingVehicles = false);
    }
  }

  Future<void> _loadReports() async {
    setState(() {
      loadingReports = true;
      errReports = null;
      msg = null;
    });

    try {
      // backend: DamageReportController@index
      // status=menunggu => special case handled backend
      final res = await api.getDamageReportsDriver(
        status: statusFilter == 'all' ? null : statusFilter,
      );

      final list = _unwrapList(res);

      final parsed = list
          .map(_toMap)
          .whereType<Map<String, dynamic>>()
          .map(ApiDamageReport.fromJson)
          .toList();

      setState(() => reports = parsed);
    } catch (e) {
      setState(() => errReports = e.toString());
    } finally {
      if (mounted) setState(() => loadingReports = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Kamu akan keluar dari akun ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await api.logout();
    } catch (_) {}

    await AuthStorage.clear();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // =========================
  // ✅ Helpers: report parsing (PAKAI MODEL)
  // =========================
  int _idFromReport(ApiDamageReport r) => r.id;

  String _plateFromReport(ApiDamageReport r) {
    final v = r.vehicle;
    return _str(v?.plateNumber, '-');
  }

  String _descFromReport(ApiDamageReport r) => _str(r.description, '-');

  String _statusFromReport(ApiDamageReport r) => _str(r.status, 'menunggu');

  String _noteFromReport(ApiDamageReport r) => _str(r.note, '-');

  bool _isLocked(ApiDamageReport r) {
    // UI rule: locked if status != menunggu
    return _statusFromReport(r) != 'menunggu';
  }

  // =========================
  // Filter logic
  // =========================
  bool _matchesStatus(ApiDamageReport r) {
    if (statusFilter == 'all') return true;
    return _statusFromReport(r).toLowerCase() == statusFilter.toLowerCase();
  }

  List<ApiDamageReport> _filteredReports() {
    final q = searchPlate.trim().toLowerCase();

    return reports.where((r) {
      final plate = _plateFromReport(r).toLowerCase();
      if (q.isNotEmpty && !plate.contains(q)) return false;
      if (!_matchesStatus(r)) return false;
      return true;
    }).toList();
  }

  Future<void> _submitReport() async {
    FocusScope.of(context).unfocus();
    setState(() => msg = null);

    final plate = selectedPlate?.trim();
    final desc = descC.text.trim();

    if (plate == null || plate.isEmpty) {
      setState(() => msg = '❌ Pilih kendaraan dulu.');
      return;
    }
    if (desc.isEmpty) {
      setState(() => msg = '❌ Deskripsi kerusakan wajib diisi.');
      return;
    }

    try {
      // backend verifyVehicle() optional but good UX
      await api.verifyVehicle(plate);
      // backend store() create report
      await api.createDamageReportDriver(plateNumber: plate, description: desc);

      descC.clear();
      setState(() => msg = '✅ Laporan kerusakan terkirim.');
      await _loadReports();

      if (mounted) setState(() => _tab = 2);
    } catch (e) {
      setState(() => msg = '❌ ${e.toString()}');
    }
  }

  // =========================
  // ✅ Service Reminder Dialog (match backend)
  // PUT /driver/vehicles/{vehicle}/service-reminder
  // body: next_service_at (nullable date), reminder_enabled (bool), reminder_days_before (1..30)
  // =========================
  Future<void> _openReminderDialog(dynamic assignmentOrVehicle) async {
    final vid = _vehicleIdFromVehicle(assignmentOrVehicle);
    if (vid <= 0) {
      _toast('❌ Vehicle ID tidak valid.');
      return;
    }

    bool enabled = _reminderEnabledFromVehicle(assignmentOrVehicle);
    int daysBefore = _reminderDaysBeforeFromVehicle(assignmentOrVehicle);
    DateTime? nextService;

    final raw = _nextServiceAtFromVehicle(assignmentOrVehicle);
    if (raw != '-' && raw.trim().isNotEmpty) {
      nextService = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    }

    DateTime? pickedDate = nextService;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Pengingat Jadwal Servis'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: (v) => setLocal(() => enabled = v),
                title: const Text('Aktifkan reminder'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jadwal servis berikutnya'),
                subtitle: Text(
                  pickedDate == null ? 'Belum di-set' : pickedDate.toString(),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: pickedDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (d == null) return;

                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(
                        pickedDate ?? DateTime.now(),
                      ),
                    );
                    if (t == null) return;

                    setLocal(() {
                      pickedDate = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        t.hour,
                        t.minute,
                      );
                    });
                  },
                  child: const Text('Pilih'),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: (daysBefore < 1 || daysBefore > 30) ? 3 : daysBefore,
                items: List.generate(30, (i) {
                  final d = i + 1;
                  return DropdownMenuItem(
                    value: d,
                    child: Text('$d hari sebelum'),
                  );
                }),
                onChanged: (v) => setLocal(() => daysBefore = v ?? 3),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Kirim reminder',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Aturan backend: jika reminder aktif, next_service_at wajib diisi.',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    if (enabled && pickedDate == null) {
      _toast('❌ Jika reminder aktif, jadwal servis wajib diisi.');
      return;
    }

    try {
      await api.updateVehicleServiceReminder(
        vehicleId: vid,
        nextServiceAt: pickedDate,
        reminderEnabled: enabled,
        reminderDaysBefore: daysBefore,
      );
      _toast('✅ Reminder servis tersimpan.');
      await _loadVehicles();
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  // =====================================================
  // ✅ QUICK BOOKING (panel)
  // =====================================================

  Future<void> _loadQuickBooking(int reportId) async {
    setState(() {
      loadingQuickBooking = true;
      quickBooking = null;
    });

    try {
      final res = await api.getBookingDriver(reportId);
      setState(() => quickBooking = _toMap(res));
    } catch (_) {
      setState(() => quickBooking = null);
    } finally {
      if (mounted) setState(() => loadingQuickBooking = false);
    }
  }

  Future<void> _pickQuickPreferredAt(BuildContext ctx) async {
    final d = await showDatePicker(
      context: ctx,
      initialDate: quickPreferredAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(quickPreferredAt ?? DateTime.now()),
    );
    if (t == null) return;

    setState(() {
      quickPreferredAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  String _fmtDateTime(dynamic raw) {
    final s = _str(raw, '-');
    if (s == '-' || s.trim().isEmpty) return '-';
    return s;
  }

  Future<void> _submitQuickBooking(int reportId) async {
    try {
      await api.createBookingDriver(
        reportId: reportId,
        preferredAt: quickPreferredAt,
        noteDriver: quickBookingNoteC.text.trim().isEmpty
            ? null
            : quickBookingNoteC.text.trim(),
      );
      _toast('✅ Booking berhasil diajukan.');
      await _loadQuickBooking(reportId);
      await _loadReports(); // optional: refresh list
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  Future<void> _cancelQuickBooking(int reportId) async {
    final b = quickBooking;
    if (b == null) return;

    final id = _toInt(b['id']);
    if (id <= 0) {
      _toast('❌ Booking ID tidak valid.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Booking?'),
        content: const Text('Booking akan dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await api.cancelBookingDriver(bookingId: id);
      _toast('✅ Booking dibatalkan.');
      await _loadQuickBooking(reportId);
      await _loadReports();
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  Future<void> _openBookingSheet(ApiDamageReport r) async {
    final reportId = _idFromReport(r);
    if (reportId <= 0) {
      _toast('❌ Report ID tidak valid.');
      return;
    }

    // reset form tiap buka panel (biar ga nyangkut)
    quickPreferredAt = null;
    quickBookingNoteC.text = '';

    await _loadQuickBooking(reportId);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final b = quickBooking;

            final bookingStatus = _str(b?['status'], '-');
            final canCancel = b != null &&
                ['requested', 'approved', 'rescheduled']
                    .contains(bookingStatus.toLowerCase());

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: 16 + bottomInset,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Booking • ${_plateFromReport(r)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (loadingQuickBooking) const LinearProgressIndicator(),

                    // =============================
                    // CASE: belum ada booking
                    // =============================
                    if (!loadingQuickBooking && b == null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.25)),
                        ),
                        child: Text(
                          'Belum ada booking.\nDriver hanya mengajukan, jadwal final ditentukan admin.',
                          style: TextStyle(color: Colors.black.withOpacity(0.75)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Preferensi jadwal (opsional)'),
                        subtitle: Text(
                          quickPreferredAt == null
                              ? 'Belum dipilih'
                              : quickPreferredAt.toString(),
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            await _pickQuickPreferredAt(ctx2);
                            setLocal(() {});
                          },
                          child: const Text('Pilih'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: quickBookingNoteC,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Catatan untuk admin (opsional)',
                          hintText: 'Contoh: minta pagi / kendaraan dipakai sore',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          await _submitQuickBooking(reportId);
                          setLocal(() {});
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('Ajukan Booking'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx2),
                        child: const Text('Tutup'),
                      ),
                    ],

                    // =============================
                    // CASE: booking sudah ada
                    // =============================
                    if (!loadingQuickBooking && b != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Status: $bookingStatus',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Reload',
                            onPressed: () async {
                              await _loadQuickBooking(reportId);
                              setLocal(() {});
                            },
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      _kv('Requested at', _fmtDateTime(b['requested_at'])),
                      _kv('Jadwal final (admin)', _fmtDateTime(b['scheduled_at'])),
                      _kv('Estimasi selesai', _fmtDateTime(b['estimated_finish_at'])),
                      _kv('Catatan driver', _str(b['note_driver'])),
                      _kv('Catatan admin', _str(b['note_admin'])),

                      const SizedBox(height: 12),
                      const Divider(height: 18),

                      // ==== Update request (karena backend updateOrCreate) ====
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Update permintaan booking (opsional)',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Preferensi jadwal'),
                              subtitle: Text(
                                quickPreferredAt == null
                                    ? 'Tidak diisi'
                                    : quickPreferredAt.toString(),
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  await _pickQuickPreferredAt(ctx2);
                                  setLocal(() {});
                                },
                                child: const Text('Ubah'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: quickBookingNoteC,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Catatan baru untuk admin',
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () async {
                                await _submitQuickBooking(reportId);
                                setLocal(() {});
                              },
                              icon: const Icon(Icons.update),
                              label: const Text('Update Booking Request'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: canCancel
                                  ? () async {
                                      await _cancelQuickBooking(reportId);
                                      setLocal(() {});
                                    }
                                  : null,
                              icon: const Icon(Icons.cancel),
                              label: Text(
                                canCancel ? 'Batalkan' : 'Tidak bisa dibatalkan',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx2),
                              child: const Text('Tutup'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Admin yang mengisi jadwal final & estimasi.',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  void dispose() {
    descC.dispose();
    quickBookingNoteC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[_tabVehicles(), _tabCreateReport(), _tabReports()];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver'),
        actions: [
          // ✅ NOTIFICATIONS BUTTON + BADGE (Firestore)
          if (_userId == null)
            IconButton(
              tooltip: 'Notifikasi (butuh /me id)',
              onPressed: null,
              icon: const Icon(Icons.notifications),
            )
          else
            StreamBuilder<int>(
              stream: FirestoreService.streamUnreadCount(userId: _userId!),
              builder: (context, snap) {
                final unread = snap.data ?? 0;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Notifikasi',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationsPage(
                              token: widget.token,
                              userId: _userId!,
                              role: 'driver',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.notifications),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : unread.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(child: tabs[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_car),
            label: 'Kendaraan',
          ),
          NavigationDestination(icon: Icon(Icons.report), label: 'Lapor'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Status'),
        ],
      ),
    );
  }

  Widget _tabVehicles() {
    return RefreshIndicator(
      onRefresh: _loadVehicles,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Kendaraan Saya'),
          const SizedBox(height: 8),
          if (loadingVehicles) const LinearProgressIndicator(),
          if (errVehicles != null) _errorBox(errVehicles!),
          if (!loadingVehicles && errVehicles == null && vehicles.isEmpty)
            _infoBox('Belum ada kendaraan yang di-assign oleh admin.'),
          const SizedBox(height: 8),
          ...vehicles.map((v) {
            final plate = _plateFromVehicle(v);
            final brand = _brandFromVehicle(v);
            final nextServiceAt = _nextServiceAtFromVehicle(v);
            final enabled = _reminderEnabledFromVehicle(v);
            final daysBefore = _reminderDaysBeforeFromVehicle(v);

            return Card(
              child: ListTile(
                leading: const Icon(Icons.directions_car),
                title: Text(plate),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Merk: $brand'),
                    const SizedBox(height: 4),
                    Text(
                      'Servis berikutnya: $nextServiceAt',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Reminder: ${enabled ? "ON" : "OFF"} • $daysBefore hari sebelum',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                trailing: TextButton(
                  onPressed: () => _openReminderDialog(v),
                  child: const Text('Reminder'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _tabCreateReport() {
    // ✅ dedup item dropdown + pastikan value ada di items
    final unique = _uniqueVehiclesByPlate();

    final plateItems = unique.entries.map((e) {
      final plate = e.key;
      final v = e.value;
      return DropdownMenuItem<String>(
        value: plate,
        child: Text('$plate — ${_brandFromVehicle(v)}'),
      );
    }).toList();

    final safeValue = _safeSelectedPlateFromItems(plateItems);

    // sync state biar konsisten (tanpa bikin loop)
    if (selectedPlate != safeValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => selectedPlate = safeValue);
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Buat Laporan Kerusakan'),
        const SizedBox(height: 10),
        if (msg != null) _msgBox(msg!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Pilih Kendaraan (Plat)'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: safeValue,
                  isExpanded: true,
                  items: plateItems,
                  onChanged: (val) => setState(() => selectedPlate = val),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Pilih kendaraan',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Deskripsi Kerusakan'),
                const SizedBox(height: 6),
                TextField(
                  controller: descC,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Contoh: mesin bunyi, rem tidak pakem, oli bocor...',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submitReport,
                  icon: const Icon(Icons.send),
                  label: const Text('Kirim Laporan'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabReports() {
    final filtered = _filteredReports();

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Status Laporan'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: statusFilter,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('Semua status'),
                      ),
                      DropdownMenuItem(
                        value: 'menunggu',
                        child: Text('Menunggu'),
                      ),
                      DropdownMenuItem(value: 'proses', child: Text('Proses')),
                      DropdownMenuItem(
                        value: 'butuh_followup_admin',
                        child: Text('Butuh Follow-up Admin'),
                      ),
                      DropdownMenuItem(value: 'fatal', child: Text('Fatal')),
                      DropdownMenuItem(
                        value: 'selesai',
                        child: Text('Selesai'),
                      ),
                    ],
                    onChanged: (v) async {
                      setState(() => statusFilter = v ?? 'all');
                      await _loadReports();
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Filter Status',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setState(() => searchPlate = v),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Search Plat',
                      hintText: 'contoh: N 1234 ABC',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        setState(() {
                          statusFilter = 'all';
                          searchPlate = '';
                        });
                        await _loadReports();
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (loadingReports) const LinearProgressIndicator(),
          if (errReports != null) _errorBox(errReports!),
          if (!loadingReports && errReports == null && reports.isEmpty)
            _infoBox('Belum ada laporan kerusakan.'),
          if (!loadingReports &&
              errReports == null &&
              reports.isNotEmpty &&
              filtered.isEmpty)
            _infoBox('Tidak ada hasil sesuai filter.'),
          const SizedBox(height: 8),
          ...filtered.map((r) {
            final plate = _plateFromReport(r);
            final desc = _descFromReport(r);
            final status = _statusFromReport(r);
            final note = _noteFromReport(r);

            final id = _idFromReport(r);
            final locked = _isLocked(r);

            return Card(
              child: ListTile(
                leading: const Icon(Icons.car_crash),
                title: Text('$plate • $status'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(desc),
                    const SizedBox(height: 4),
                    Text(
                      'Note: $note',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.6),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Klik "Booking" untuk ajukan/ubah booking dari sini.',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                isThreeLine: true,

                // ✅ tombol panel booking
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _openBookingSheet(r),
                      child: const Text('Booking'),
                    ),
                    locked
                        ? const Icon(Icons.lock)
                        : const Icon(Icons.chevron_right),
                  ],
                ),

                // onTap tetap ke detail (fitur lama)
                onTap: () async {
                  if (id <= 0) {
                    _showReportDetail(r, note);
                    return;
                  }

                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverReportDetailPage(
                        token: widget.token,
                        reportId: id,
                      ),
                    ),
                  );

                  if (changed == true) {
                    await _loadReports();
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showReportDetail(ApiDamageReport report, String note) {
    final plate = _plateFromReport(report);
    final desc = _descFromReport(report);
    final status = _statusFromReport(report);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Detail Laporan • $plate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $status'),
            const SizedBox(height: 8),
            Text('Deskripsi:\n$desc'),
            const SizedBox(height: 8),
            Text('Catatan terakhir:\n$note'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  // =========================
  // UI helpers
  // =========================
  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      );

  Widget _errorBox(String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Text(t, style: const TextStyle(color: Colors.red)),
      );

  Widget _infoBox(String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Text(t),
      );

  Widget _msgBox(String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.startsWith('❌')
              ? Colors.red.withOpacity(0.08)
              : Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: t.startsWith('❌')
                ? Colors.red.withOpacity(0.3)
                : Colors.green.withOpacity(0.3),
          ),
        ),
        child: Text(t),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                k,
                style: TextStyle(color: Colors.black.withOpacity(0.7)),
              ),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
