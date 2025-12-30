// technician_home.dart
// ✅ FULL FILE (UI lengkap) + Service Jobs (booking approved/rescheduled)
// - Tidak mengubah fungsi lama (Inbox/Respond/Sparepart/CostEstimate/FCM/Logout tetap).
//
// ✅ Tambahan (PATCH):
// - Tab baru "Reviews" untuk teknisi:
//   GET /api/technician/reviews
//   Menampilkan: summary (avg_rating & total_reviews) + list review (bintang + komentar)
//
// ⚠️ NOTE:
// - Patch ini TIDAK mengubah ApiService kamu.
// - Karena ApiService belum punya method getTechnicianReviews(), tab Reviews di file ini
//   memakai Dio langsung (dengan Bearer token yang sama) supaya benar-benar "load GET /technician/reviews"
//   tanpa mengubah file lain.

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';

import 'API/api_service.dart';
import 'utils/auth_storage.dart';
import 'main.dart';

// =====================================================
// STATUS LABEL HELPER (DamageReport/TechnicianResponse)
// =====================================================
String statusLabel(String s) {
  switch (s) {
    case 'menunggu':
      return 'Menunggu';
    case 'proses':
      return 'Proses';
    case 'butuh_followup_admin':
      return 'Butuh Follow-up Admin';
    case 'approved_followup_admin':
      return 'Approved (Admin)';
    case 'fatal':
      return 'Fatal';
    case 'selesai':
      return 'Selesai';
    default:
      return s;
  }
}

// =====================================================
// STATUS LABEL HELPER (Service Booking / Service Job)
// =====================================================
String jobStatusLabel(String s) {
  switch (s) {
    case 'requested':
      return 'Requested';
    case 'approved':
      return 'Approved';
    case 'rescheduled':
      return 'Rescheduled';
    case 'in_progress':
      return 'In Progress';
    case 'completed':
      return 'Completed';
    case 'canceled':
      return 'Canceled';
    default:
      return s;
  }
}

// =====================================================
// ✅ FIX: NORMALIZE DROPDOWN VALUE (biar gak crash)
// Backend respond validate: proses|butuh_followup_admin|fatal|selesai
// =====================================================
String normalizeTechnicianRespondStatus(String s) {
  const allowed = {
    'proses',
    'butuh_followup_admin',
    'fatal',
    'selesai',
  };
  final x = s.trim().toLowerCase();
  if (allowed.contains(x)) return x;
  return 'proses';
}

// =====================================================
// SAFE PARSERS
// =====================================================
int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? fallback;
}

String? _toStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.trim().isEmpty ? null : s;
}

Map<String, dynamic>? _toMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

List<dynamic> _toList(dynamic v) => (v is List) ? v : <dynamic>[];

// =====================================================
// MODELS (minimal untuk halaman teknisi)
// =====================================================
class ApiVehicle {
  final int id;
  final String? brand;
  final String? model;
  final String? plateNumber;
  final int? year;

  ApiVehicle({
    required this.id,
    this.brand,
    this.model,
    this.plateNumber,
    this.year,
  });

  factory ApiVehicle.fromJson(Map<String, dynamic> j) {
    return ApiVehicle(
      id: _toInt(j['id']),
      brand: _toStr(j['brand']),
      model: _toStr(j['model']),
      plateNumber: _toStr(j['plate_number'] ?? j['plate'] ?? j['plateNumber']),
      year: j['year'] is int ? j['year'] as int : int.tryParse('${j['year']}'),
    );
  }

  String get displayName {
    final b = brand ?? '';
    final m = model ?? '';
    final name = ('$b $m').trim();
    return name.isEmpty ? 'Kendaraan' : name;
  }
}

class ApiTechnicianResponse {
  final int id;
  final String? status;
  final String? note;
  final String? createdAt;

  ApiTechnicianResponse({
    required this.id,
    this.status,
    this.note,
    this.createdAt,
  });

  factory ApiTechnicianResponse.fromJson(Map<String, dynamic> j) {
    return ApiTechnicianResponse(
      id: _toInt(j['id']),
      status: _toStr(j['status']),
      note: _toStr(j['note']),
      createdAt: _toStr(j['created_at'] ?? j['updated_at']),
    );
  }
}

class ApiCostEstimate {
  final int id;
  final int damageReportId;
  final int technicianId;
  final int laborCost;
  final int partsCost;
  final int otherCost;
  final int totalCost;
  final String? note;
  final String status; // draft|submitted|approved|rejected

  ApiCostEstimate({
    required this.id,
    required this.damageReportId,
    required this.technicianId,
    required this.laborCost,
    required this.partsCost,
    required this.otherCost,
    required this.totalCost,
    this.note,
    required this.status,
  });

  factory ApiCostEstimate.fromJson(Map<String, dynamic> j) {
    return ApiCostEstimate(
      id: _toInt(j['id']),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId']),
      technicianId: _toInt(j['technician_id'] ?? j['technicianId']),
      laborCost: _toInt(j['labor_cost'] ?? j['laborCost']),
      partsCost: _toInt(j['parts_cost'] ?? j['partsCost']),
      otherCost: _toInt(j['other_cost'] ?? j['otherCost']),
      totalCost: _toInt(j['total_cost'] ?? j['totalCost']),
      note: _toStr(j['note']),
      status: _toStr(j['status']) ?? 'draft',
    );
  }

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class ApiDamageReport {
  final int id;
  final String description;
  final String status; // computed fallback menunggu
  final String? note;
  final String? createdAt;

  final ApiVehicle? vehicle;
  final ApiTechnicianResponse? latestResponse;
  final List<ApiTechnicianResponse> responses;

  final ApiCostEstimate? costEstimate;

  ApiDamageReport({
    required this.id,
    required this.description,
    required this.status,
    this.note,
    this.createdAt,
    this.vehicle,
    this.latestResponse,
    this.responses = const [],
    this.costEstimate,
  });

  factory ApiDamageReport.fromJson(Map<String, dynamic> j) {
    ApiVehicle? v;
    final vMap = _toMap(j['vehicle']);
    if (vMap != null) v = ApiVehicle.fromJson(vMap);

    final respRaw = j['technician_responses'] ?? j['technicianResponses'];
    final respList = _toList(respRaw)
        .map(_toMap)
        .whereType<Map<String, dynamic>>()
        .map(ApiTechnicianResponse.fromJson)
        .toList();

    ApiTechnicianResponse? latest;
    final latestRaw =
        j['latest_technician_response'] ?? j['latestTechnicianResponse'];
    final latestMap = _toMap(latestRaw);
    if (latestMap != null) latest = ApiTechnicianResponse.fromJson(latestMap);

    final computedStatus = _toStr(latest?.status) ??
        (respList.isNotEmpty ? _toStr(respList.last.status) : null) ??
        _toStr(j['status']) ??
        'menunggu';

    final computedNote = _toStr(latest?.note) ??
        (respList.isNotEmpty ? _toStr(respList.last.note) : null);

    ApiCostEstimate? ce;
    final ceMap = _toMap(j['cost_estimate'] ?? j['costEstimate']);
    if (ceMap != null) ce = ApiCostEstimate.fromJson(ceMap);

    return ApiDamageReport(
      id: _toInt(j['id']),
      description: (j['description'] ?? '').toString(),
      status: computedStatus,
      note: computedNote,
      createdAt: _toStr(j['created_at']),
      vehicle: v,
      latestResponse: latest,
      responses: respList,
      costEstimate: ce,
    );
  }

  String get plate => vehicle?.plateNumber ?? '-';
}

// =====================================================
// ✅ NEW: Service Job model (ServiceBooking + DamageReport nested)
// =====================================================
class ApiServiceJob {
  final int id; // booking id
  final String status; // approved/rescheduled/in_progress/completed/...
  final String? scheduledAt;
  final String? estimatedFinishAt;
  final String? startedAt;
  final String? completedAt;
  final String? noteAdmin;
  final String? noteDriver;

  final int damageReportId;
  final ApiDamageReport? damageReport;

  ApiServiceJob({
    required this.id,
    required this.status,
    required this.damageReportId,
    this.scheduledAt,
    this.estimatedFinishAt,
    this.startedAt,
    this.completedAt,
    this.noteAdmin,
    this.noteDriver,
    this.damageReport,
  });

  factory ApiServiceJob.fromJson(Map<String, dynamic> j) {
    final drMap = _toMap(j['damage_report'] ?? j['damageReport']);
    ApiDamageReport? dr;
    if (drMap != null) {
      dr = ApiDamageReport.fromJson(drMap);
    }

    return ApiServiceJob(
      id: _toInt(j['id']),
      status: _toStr(j['status']) ?? '-',
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId']),
      scheduledAt: _toStr(j['scheduled_at'] ?? j['scheduledAt']),
      estimatedFinishAt:
          _toStr(j['estimated_finish_at'] ?? j['estimatedFinishAt']),
      startedAt: _toStr(j['started_at'] ?? j['startedAt']),
      completedAt: _toStr(j['completed_at'] ?? j['completedAt']),
      noteAdmin: _toStr(j['note_admin'] ?? j['noteAdmin']),
      noteDriver: _toStr(j['note_driver'] ?? j['noteDriver']),
      damageReport: dr,
    );
  }

  String get plate => damageReport?.plate ?? '-';
  String get vehicleName => damageReport?.vehicle?.displayName ?? 'Kendaraan';
  String get driverNotePreview => (noteDriver ?? '-');
  String get adminNotePreview => (noteAdmin ?? '-');
}

// =====================================================
// ✅ NEW: Technician Review models
// Response controller:
// {
//   summary: { avg_rating: 4.5, total_reviews: 10 },
//   data: { data: [ ... ], ...pagination }
// }
// =====================================================
class ApiTechnicianReviewSummary {
  final double avgRating;
  final int totalReviews;

  ApiTechnicianReviewSummary({
    required this.avgRating,
    required this.totalReviews,
  });

  factory ApiTechnicianReviewSummary.fromJson(Map<String, dynamic> j) {
    final rawAvg = j['avg_rating'];
    double avg;
    if (rawAvg is num) {
      avg = rawAvg.toDouble();
    } else {
      avg = double.tryParse('${rawAvg ?? 0}') ?? 0.0;
    }

    return ApiTechnicianReviewSummary(
      avgRating: double.parse(avg.toStringAsFixed(2)),
      totalReviews: _toInt(j['total_reviews'], 0),
    );
  }
}

class ApiTechnicianReviewItem {
  final int id;
  final int rating; // 1..5
  final String? review;
  final String? reviewedAt;

  final String driverName;
  final String plateNumber;

  ApiTechnicianReviewItem({
    required this.id,
    required this.rating,
    this.review,
    this.reviewedAt,
    required this.driverName,
    required this.plateNumber,
  });

  factory ApiTechnicianReviewItem.fromJson(Map<String, dynamic> j) {
    final driver = _toMap(j['driver']);
    final dr = _toMap(j['damage_report'] ?? j['damageReport']);
    final vehicle = _toMap(dr?['vehicle']);

    final plate = _toStr(vehicle?['plate_number'] ?? vehicle?['plate']) ?? '-';
    final dname = _toStr(driver?['name'] ?? driver?['username']) ?? '-';

    return ApiTechnicianReviewItem(
      id: _toInt(j['id']),
      rating: _toInt(j['rating']),
      review: _toStr(j['review'] ?? j['comment']),
      reviewedAt: _toStr(j['reviewed_at'] ?? j['created_at'] ?? j['updated_at']),
      driverName: dname,
      plateNumber: plate,
    );
  }
}

// =====================================================
// PAGE
// =====================================================
class TechnicianHomePage extends StatefulWidget {
  final String token;
  const TechnicianHomePage({super.key, required this.token});

  @override
  State<TechnicianHomePage> createState() => _TechnicianHomePageState();
}

class _TechnicianHomePageState extends State<TechnicianHomePage> {
  late final ApiService api;

  int _tab = 0;

  bool loadingInbox = false;
  bool loadingMyResponses = false;

  // ✅ NEW: jobs loading
  bool loadingJobs = false;
  String? errJobs;

  // ✅ NEW: reviews loading
  bool loadingReviews = false;
  String? errReviews;
  ApiTechnicianReviewSummary reviewSummary =
      ApiTechnicianReviewSummary(avgRating: 0, totalReviews: 0);
  List<ApiTechnicianReviewItem> reviewItems = [];

  // local dio for reviews only (tanpa ubah ApiService)
  late final Dio _dioReviews;

  String? errInbox;
  String? errMyResponses;

  List<ApiDamageReport> inboxReports = [];
  List<dynamic> myResponsesList = [];

  // ✅ NEW: jobs list
  List<ApiServiceJob> jobs = [];
  String jobFilter = 'queue'; // queue|active|all

  // ✅ cache snapshot report terbaru agar "Respon Saya" ikut berubah saat admin update
  // key: report_id (damage_reports.id)
  Map<int, Map<String, dynamic>> _reportCacheById = {};

  String statusFilter = 'menunggu';
  String searchPlate = '';

  // =====================================================
  // ✅ FCM listeners
  // =====================================================
  bool _fcmReady = false;

  Map<String, dynamic> _dataFromRemoteMessage(RemoteMessage m) {
    final d = <String, dynamic>{};
    m.data.forEach((k, v) => d[k.toString()] = v);
    return d;
  }

  int _notifReportId(Map<String, dynamic> data) {
    return _toInt(
      data['report_id'] ??
          data['reportId'] ??
          data['damage_id'] ??
          data['damage_report_id'],
    );
  }

  int _notifBookingId(Map<String, dynamic> data) {
    return _toInt(data['booking_id'] ?? data['bookingId']);
  }

  String _notifRole(Map<String, dynamic> data) =>
      (_toStr(data['role']) ?? '').toLowerCase();

  String _notifType(Map<String, dynamic> data) =>
      (_toStr(data['type']) ?? '').toLowerCase();

  Future<void> _handleOpenFromFcmData(Map<String, dynamic> data) async {
    final role = _notifRole(data);
    if (role.isNotEmpty && role != 'teknisi' && role != 'technician') return;

    final type = _notifType(data);
    final bookingId = _notifBookingId(data);
    final reportId = _notifReportId(data);

    // ✅ jika notif type service_job dan booking_id ada → buka tab jobs
    if (type.contains('service_job') && bookingId > 0) {
      if (mounted) setState(() => _tab = 0);
      await _loadJobs();
      final job = jobs
          .where((x) => x.id == bookingId)
          .cast<ApiServiceJob?>()
          .firstWhere(
            (x) => x != null,
            orElse: () => null,
          );
      if (job != null) {
        await _openJobDetail(job);
      } else if (reportId > 0) {
        await _openReportDetailAndRespond(reportId);
      }
      return;
    }

    // fallback lama: buka report detail
    if (reportId > 0) {
      if (mounted) setState(() => _tab = 1); // Inbox tetap index 1
      await _openReportDetailAndRespond(reportId);
    }
  }

  Future<void> _initFcmListenersOnce() async {
    if (_fcmReady) return;
    _fcmReady = true;

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.notification?.title ?? 'Notifikasi';
      final body = message.notification?.body ?? '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title${body.isNotEmpty ? " — $body" : ""}')),
        );
      }
      await _loadJobs();
      await _loadInbox();
      await _loadMyResponses();
      await _loadReviews(); // ✅ ikut refresh bila ada notif rating
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _handleOpenFromFcmData(_dataFromRemoteMessage(message));
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      await _handleOpenFromFcmData(_dataFromRemoteMessage(initial));
    }
  }

  @override
  void initState() {
    super.initState();
    api = ApiService(mode: ApiMode.dio, token: widget.token);

    _dioReviews = Dio(
      BaseOptions(
        baseUrl: ApiService.baseUrl,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    _loadAll();
    _initFcmListenersOnce();
  }

  Future<void> _loadAll() async => Future.wait([
        _loadJobs(),
        _loadInbox(),
        _loadMyResponses(),
        _loadReviews(),
      ]);

  // =========================
  // LOADERS
  // =========================
  Future<void> _loadInbox() async {
    setState(() {
      loadingInbox = true;
      errInbox = null;
    });

    try {
      final res = await api.getDamageReportsTechnician(
        status: statusFilter == 'all' ? null : statusFilter,
        includeDone: statusFilter == 'all',
      );

      final list = (res is List) ? res : <dynamic>[];
      setState(() {
        inboxReports = list
            .map(_toMap)
            .whereType<Map<String, dynamic>>()
            .map(ApiDamageReport.fromJson)
            .toList();
      });
    } catch (e) {
      setState(() => errInbox = e.toString());
    } finally {
      if (mounted) setState(() => loadingInbox = false);
    }
  }

  // ✅ NEW: load jobs (ServiceBooking for technician)
  Future<void> _loadJobs() async {
    setState(() {
      loadingJobs = true;
      errJobs = null;
    });

    try {
      final res = await api.getTechnicianJobs(status: jobFilter);
      final list = (res is List) ? res : <dynamic>[];
      setState(() {
        jobs = list
            .map(_toMap)
            .whereType<Map<String, dynamic>>()
            .map(ApiServiceJob.fromJson)
            .toList();
      });
    } catch (e) {
      setState(() => errJobs = e.toString());
    } finally {
      if (mounted) setState(() => loadingJobs = false);
    }
  }

  // ✅ NEW: load reviews (GET /technician/reviews)
  Future<void> _loadReviews() async {
    setState(() {
      loadingReviews = true;
      errReviews = null;
    });

    try {
      final res = await _dioReviews.get('/technician/reviews');
      final data = res.data;

      final map = _toMap(data);
      if (map == null) {
        setState(() {
          reviewSummary = ApiTechnicianReviewSummary(avgRating: 0, totalReviews: 0);
          reviewItems = [];
        });
        return;
      }

      final summaryMap = _toMap(map['summary']) ?? <String, dynamic>{};
      final parsedSummary = ApiTechnicianReviewSummary.fromJson(summaryMap);

      // paginate: { data: { data: [items], ... } }
      final dataWrap = _toMap(map['data']);
      final itemsRaw = _toList(dataWrap?['data'] ?? map['data']);

      final parsedItems = itemsRaw
          .map(_toMap)
          .whereType<Map<String, dynamic>>()
          .map(ApiTechnicianReviewItem.fromJson)
          .toList();

      setState(() {
        reviewSummary = parsedSummary;
        reviewItems = parsedItems;
      });
    } on DioException catch (e) {
      String msg = e.message ?? 'Gagal memuat reviews.';
      final m = _toMap(e.response?.data);
      final backendMsg = _toStr(m?['message']);
      if (backendMsg != null) msg = backendMsg;
      setState(() => errReviews = msg);
    } catch (e) {
      setState(() => errReviews = e.toString());
    } finally {
      if (mounted) setState(() => loadingReviews = false);
    }
  }

  // ✅ FIX: selain myResponses(), ambil snapshot report terbaru agar status "Respon Saya" ikut berubah saat admin approve
  Future<void> _loadMyResponses() async {
    setState(() {
      loadingMyResponses = true;
      errMyResponses = null;
    });

    try {
      // 1) ambil riwayat respon teknisi (punya report_id via damage_id)
      final res = await api.myResponses();
      final respList = (res is List) ? res : <dynamic>[];

      // 2) ambil snapshot semua report (includeDone=true) agar latest status selalu terbaru
      final snap = await api.getDamageReportsTechnician(
        status: null,
        includeDone: true,
      );
      final snapList = (snap is List) ? snap : <dynamic>[];

      final cache = <int, Map<String, dynamic>>{};
      for (final x in snapList) {
        final m = _toMap(x);
        if (m == null) continue;
        final id = _toInt(m['id']);
        if (id > 0) cache[id] = m;
      }

      setState(() {
        myResponsesList = respList;
        _reportCacheById = cache;
      });
    } catch (e) {
      setState(() => errMyResponses = e.toString());
    } finally {
      if (mounted) setState(() => loadingMyResponses = false);
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
  // FILTERS
  // =========================
  Future<void> _setStatusAndReload(String v) async {
    if (v == statusFilter) return;
    setState(() => statusFilter = v);
    await _loadInbox();
  }

  Future<void> _setJobFilterAndReload(String v) async {
    if (v == jobFilter) return;
    setState(() => jobFilter = v);
    await _loadJobs();
  }

  List<ApiDamageReport> _filteredByPlateOnly() {
    final q = searchPlate.trim().toLowerCase();
    if (q.isEmpty) return inboxReports;
    return inboxReports.where((r) => r.plate.toLowerCase().contains(q)).toList();
  }

  Widget _statusChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('menunggu', 'Menunggu'),
        _chip('proses', 'Proses'),
        _chip('butuh_followup_admin', 'Follow-up'),
        _chip('approved_followup_admin', 'Approved'),
        _chip('fatal', 'Fatal'),
        _chip('selesai', 'Selesai'),
        _chip('all', 'Semua'),
      ],
    );
  }

  Widget _chip(String value, String label) {
    final selected = statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setStatusAndReload(value),
    );
  }

  Widget _jobChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _jobChip('queue', 'Queue'),
        _jobChip('active', 'Active'),
        _jobChip('all', 'All'),
      ],
    );
  }

  Widget _jobChip(String value, String label) {
    final selected = jobFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setJobFilterAndReload(value),
    );
  }

  // =========================
  // RESPOND FLOW
  // =========================
  Future<void> _openReportDetailAndRespond(int id) async {
    dynamic detail;
    try {
      detail = await api.getDamageReportTechnicianDetail(id);
    } catch (e) {
      if (!mounted) return;
      _toast('❌ ${e.toString()}');
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportRespondSheet(
        reportDetail: detail,
        api: api,
        onAfterAnyChange: () async {
          Navigator.pop(context);
          await _loadJobs();
          await _loadInbox();
          await _loadMyResponses();
          await _loadReviews();
          if (mounted) _toast('✅ Update tersimpan.');
        },
      ),
    );
  }

  Future<void> _openJobDetail(ApiServiceJob job) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _JobDetailSheet(
        job: job,
        api: api,
        onAfterChange: () async {
          Navigator.pop(context);
          await _loadJobs();
          await _loadInbox();
          await _loadMyResponses();
          await _loadReviews();
        },
        onOpenReport: () async {
          final rid = job.damageReportId;
          Navigator.pop(context);
          if (rid > 0) {
            await _openReportDetailAndRespond(rid);
          }
        },
      ),
    );
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), duration: const Duration(seconds: 2)),
    );
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    // ✅ tab order (UPDATED):
    // 0 = Jobs
    // 1 = Inbox
    // 2 = My Responses
    // 3 = Reviews  ✅ NEW
    // 4 = Account
    final tabs = <Widget>[
      _tabJobs(),
      _tabInbox(),
      _tabMyResponses(),
      _tabReviews(), // ✅ NEW
      _tabAccount(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Technician'),
        actions: [
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
          NavigationDestination(icon: Icon(Icons.work), label: 'Jobs'),
          NavigationDestination(icon: Icon(Icons.inbox), label: 'Masuk'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Respon Saya'),
          NavigationDestination(icon: Icon(Icons.star), label: 'Reviews'), // ✅ NEW
          NavigationDestination(icon: Icon(Icons.person), label: 'Akun'),
        ],
      ),
    );
  }

  // =========================
  // TAB: JOBS (NEW)
  // =========================
  Widget _tabJobs() {
    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Service Jobs')),
              IconButton(
                tooltip: 'Reload Jobs',
                onPressed: _loadJobs,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Filter',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _jobChips(),
                  const SizedBox(height: 6),
                  Text(
                    'Queue: approved/rescheduled • Active: +in_progress',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (loadingJobs) const LinearProgressIndicator(),
          if (errJobs != null) _errorBox(errJobs!),
          if (!loadingJobs && errJobs == null && jobs.isEmpty)
            _infoBox('Belum ada job terjadwal dari admin.'),

          const SizedBox(height: 8),

          ...jobs.map((j) {
            final status = j.status;
            final plate = j.plate;
            final sched = j.scheduledAt ?? '-';
            final subtitleLines = <Widget>[
              Text('Status: ${jobStatusLabel(status)}'),
              Text('Jadwal: $sched'),
              Text('Kendaraan: ${j.vehicleName}'),
              if ((j.noteAdmin ?? '').trim().isNotEmpty)
                Text('Catatan admin: ${j.noteAdmin}'),
              if ((j.noteDriver ?? '').trim().isNotEmpty)
                Text('Catatan driver: ${j.noteDriver}'),
            ];

            return Card(
              child: ListTile(
                leading: const Icon(Icons.build_circle),
                title: Text('$plate • ${jobStatusLabel(status)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: subtitleLines,
                ),
                isThreeLine: true,
                onTap: () => _openJobDetail(j),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // =========================
  // TAB: INBOX (LAMA)
  // =========================
  Widget _tabInbox() {
    final filtered = _filteredByPlateOnly();

    return RefreshIndicator(
      onRefresh: _loadInbox,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Laporan Masuk')),
              IconButton(
                tooltip: 'Reload',
                onPressed: _loadInbox,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Status',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _statusChips(),
                  const SizedBox(height: 12),
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
                      onPressed: () => setState(() => searchPlate = ''),
                      child: const Text('Reset Search'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (loadingInbox) const LinearProgressIndicator(),
          if (errInbox != null) _errorBox(errInbox!),
          if (!loadingInbox && errInbox == null && inboxReports.isEmpty)
            _infoBox('Belum ada laporan masuk dari driver.'),
          if (!loadingInbox &&
              errInbox == null &&
              inboxReports.isNotEmpty &&
              filtered.isEmpty)
            _infoBox('Tidak ada laporan sesuai search plat.'),
          const SizedBox(height: 8),
          ...filtered.map((r) {
            final ce = r.costEstimate;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.car_crash),
                title: Text('${r.plate} • ${statusLabel(r.status)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kendaraan: ${r.vehicle?.brand ?? '-'}'),
                    Text(r.description),
                    const SizedBox(height: 6),
                    _historyPreviewTyped(r),
                    if (ce != null)
                      Text(
                        'Cost Estimate: ${ce.status} • Total: ${ce.totalCost}',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                onTap: () => _openReportDetailAndRespond(r.id),
                isThreeLine: true,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _historyPreviewTyped(ApiDamageReport r) {
    final h = r.responses;
    if (h.isEmpty) {
      return Text(
        'History: belum ada respon teknisi.',
        style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
      );
    }

    final last2 = h.reversed.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History:',
            style:
                TextStyle(color: Colors.black.withOpacity(0.65), fontSize: 12)),
        ...last2.map((x) {
          final st = x.status ?? '-';
          final note = x.note ?? '-';
          final at = x.createdAt;
          return Text(
            '• ${statusLabel(st)} — $note ${at != null ? "($at)" : ""}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          );
        }),
      ],
    );
  }

  // =========================
  // TAB: MY RESPONSES (LAMA)
  // =========================
  Widget _tabMyResponses() {
    final grouped = _groupMyResponses(myResponsesList);

    return RefreshIndicator(
      onRefresh: _loadMyResponses,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Riwayat Respon Saya'),
          const SizedBox(height: 8),
          if (loadingMyResponses) const LinearProgressIndicator(),
          if (errMyResponses != null) _errorBox(errMyResponses!),
          if (!loadingMyResponses && errMyResponses == null && grouped.isEmpty)
            _infoBox('Belum ada respon yang kamu kirim.'),
          const SizedBox(height: 8),
          ...grouped.map((g) {
            final plate = (g['plate'] ?? '-') as String;
            final latestStatus = (g['latest_status'] ?? '-') as String;
            final latestNote = (g['latest_note'] ?? '-') as String;
            final timeline = (g['timeline'] as List).cast<Map<String, dynamic>>();

            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.assignment_turned_in),
                title: Text('$plate • ${statusLabel(latestStatus)}'),
                subtitle: Text(
                  latestNote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('History:',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...timeline.reversed.map((m) {
                          final st = _myRespStatus(m);
                          final note = _myRespNote(m);
                          final at = _myRespCreatedAt(m);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '• ${statusLabel(st)} — $note ${at.isNotEmpty ? "($at)" : ""}',
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // =========================
  // ✅ NEW TAB: REVIEWS
  // =========================
  Widget _tabReviews() {
    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Reviews')),
              IconButton(
                tooltip: 'Reload Reviews',
                onPressed: _loadReviews,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ringkasan',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _kvInline('Avg Rating',
                            reviewSummary.avgRating.toStringAsFixed(2)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _kvInline(
                            'Total Reviews', '${reviewSummary.totalReviews}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _starsRow(reviewSummary.avgRating),
                  const SizedBox(height: 6),
                  Text(
                    'Data dari endpoint: GET /technician/reviews',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          if (loadingReviews) const LinearProgressIndicator(),
          if (errReviews != null) _errorBox(errReviews!),

          if (!loadingReviews && errReviews == null && reviewItems.isEmpty)
            _infoBox('Belum ada review dari driver.'),

          const SizedBox(height: 8),

          ...reviewItems.map((it) {
            final reviewText = (it.review ?? '').trim().isEmpty ? '-' : it.review!.trim();
            return Card(
              child: ListTile(
                leading: const Icon(Icons.star),
                title: Text('${it.plateNumber} • ${it.driverName}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _starsRow(it.rating.toDouble(), compact: true),
                    const SizedBox(height: 6),
                    Text(
                      reviewText,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      it.reviewedAt ?? '-',
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                isThreeLine: true,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _starsRow(double rating, {bool compact = false}) {
    // rating bisa 0..5, kita tampilkan 5 bintang (full/empty) sederhana
    final r = rating.clamp(0, 5);
    final full = r.floor();
    final half = (r - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;

    final size = compact ? 18.0 : 22.0;

    final stars = <Widget>[];
    for (var i = 0; i < full; i++) {
      stars.add(Icon(Icons.star, size: size));
    }
    if (half == 1) {
      stars.add(Icon(Icons.star_half, size: size));
    }
    for (var i = 0; i < empty; i++) {
      stars.add(Icon(Icons.star_border, size: size));
    }

    return Row(children: stars);
  }

  Widget _kvInline(String k, String v) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // =========================
  // TAB: ACCOUNT (LAMA)
  // =========================
  Widget _tabAccount() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Akun'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Catatan:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                  '• Status "butuh_followup_admin" akan muncul di menu Admin (Follow-ups).\n'
                  '• Status "selesai" menandakan laporan beres dari sisi teknisi.\n'
                  '• Cost estimate: teknisi buat draft → submit → admin approve/reject.\n'
                  '• Catatan (note) boleh kosong di backend, tapi disarankan diisi biar jelas.\n'
                  '• Service Jobs: job muncul setelah admin approve/reschedule booking.\n'
                  '• Reviews: lihat rating yang diberikan driver.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================
  // UI HELPERS
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

  // =====================================================
  // MY RESPONSES helpers (kompatibel backend myResponses())
  // + ✅ OVERRIDE dari cache report agar latest_status/history ikut berubah saat admin update
  // =====================================================
  Map<String, dynamic>? _pickMap(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      final mm = _toMap(v);
      if (mm != null) return mm;
    }
    return null;
  }

  int _myRespReportId(Map m) {
    final direct = m['damage_id'] ??
        m['damage_report_id'] ??
        m['report_id'] ??
        m['damageReportId'] ??
        m['damageId'];
    final did = _toInt(direct, 0);
    if (did > 0) return did;

    final drm = _pickMap(m, const [
      'damageReport',
      'damage_report',
      'report',
      'damage',
      'damageReportDetail'
    ]);
    return _toInt(drm?['id'], 0);
  }

  String _myRespPlate(Map m) {
    final drm = _pickMap(m, const [
      'damageReport',
      'damage_report',
      'report',
      'damage',
    ]);
    final vm = _pickMap(drm ?? const {}, const ['vehicle', 'car', 'kendaraan']);
    final p = _toStr(vm?['plate_number'] ?? vm?['plate'] ?? vm?['plateNumber']);
    if (p != null) return p;
    return _toStr(m['plate_number'] ?? m['plate'] ?? m['plateNumber']) ?? '-';
  }

  String _myRespCreatedAt(Map m) =>
      _toStr(m['created_at'] ?? m['updated_at'] ?? m['date']) ?? '';
  String _myRespStatus(Map m) => _toStr(m['status']) ?? '-';
  String _myRespNote(Map m) => _toStr(m['note']) ?? '-';

  // ✅ ambil latest status/note dari report cache (lebih update)
  String? _latestStatusFromReportCache(int reportId) {
    final rep = _reportCacheById[reportId];
    if (rep == null) return null;

    final latest = _toMap(
        rep['latest_technician_response'] ?? rep['latestTechnicianResponse']);
    final s = _toStr(latest?['status']);
    if (s != null) return s;

    return 'menunggu';
  }

  String? _latestNoteFromReportCache(int reportId) {
    final rep = _reportCacheById[reportId];
    if (rep == null) return null;

    final latest = _toMap(
        rep['latest_technician_response'] ?? rep['latestTechnicianResponse']);
    final n = _toStr(latest?['note']);
    if (n != null) return n;

    return null;
  }

  // ✅ ambil timeline dari report cache (technician_responses) agar history lebih “nyambung”
  List<Map<String, dynamic>>? _timelineFromReportCache(int reportId) {
    final rep = _reportCacheById[reportId];
    if (rep == null) return null;

    final raw =
        _toList(rep['technician_responses'] ?? rep['technicianResponses']);
    final list = raw.map(_toMap).whereType<Map<String, dynamic>>().toList();

    list.sort((a, b) =>
        (_toStr(a['created_at'] ?? a['updated_at']) ?? '').compareTo(
            _toStr(b['created_at'] ?? b['updated_at']) ?? ''));

    return list;
  }

  List<Map<String, dynamic>> _groupMyResponses(List<dynamic> raw) {
    final Map<int, List<Map<String, dynamic>>> groups = {};

    for (final x in raw) {
      final m = (x is Map)
          ? x.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final rid = _myRespReportId(m);
      if (rid <= 0) continue;
      groups.putIfAbsent(rid, () => []).add(m);
    }

    for (final e in groups.entries) {
      e.value.sort(
          (a, b) => _myRespCreatedAt(a).compareTo(_myRespCreatedAt(b)));
    }

    final result = <Map<String, dynamic>>[];
    for (final e in groups.entries) {
      final reportId = e.key;

      final timelineFromMyResponses = e.value;
      final timeline =
          _timelineFromReportCache(reportId) ?? timelineFromMyResponses;

      String plate = '-';
      final rep = _reportCacheById[reportId];
      if (rep != null) {
        final v = _toMap(rep['vehicle']);
        plate = _toStr(v?['plate_number'] ?? v?['plate']) ?? plate;
      } else {
        final last =
            timelineFromMyResponses.isNotEmpty ? timelineFromMyResponses.last : null;
        if (last != null) plate = _myRespPlate(last);
      }

      final latestStatus = _latestStatusFromReportCache(reportId) ??
          (timeline.isNotEmpty ? _myRespStatus(timeline.last) : '-');

      final latestNote = _latestNoteFromReportCache(reportId) ??
          (timeline.isNotEmpty ? _myRespNote(timeline.last) : '-');

      result.add({
        "report_id": reportId,
        "plate": plate,
        "latest_status": latestStatus,
        "latest_note": latestNote,
        "timeline": timeline,
      });
    }

    result.sort((a, b) {
      final ta = (a['timeline'] as List).cast<Map<String, dynamic>>();
      final tb = (b['timeline'] as List).cast<Map<String, dynamic>>();
      final atA = ta.isNotEmpty ? _myRespCreatedAt(ta.last) : '';
      final atB = tb.isNotEmpty ? _myRespCreatedAt(tb.last) : '';
      return atB.compareTo(atA);
    });

    return result;
  }
}

// ============================================================
// ✅ NEW BottomSheet: Service Job Detail + Start/Complete + Open Report
// ============================================================
class _JobDetailSheet extends StatefulWidget {
  final ApiServiceJob job;
  final ApiService api;
  final Future<void> Function() onAfterChange;
  final Future<void> Function() onOpenReport;

  const _JobDetailSheet({
    required this.job,
    required this.api,
    required this.onAfterChange,
    required this.onOpenReport,
  });

  @override
  State<_JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends State<_JobDetailSheet> {
  bool busy = false;
  String? err;

  bool get canStart =>
      widget.job.status == 'approved' || widget.job.status == 'rescheduled';
  bool get canComplete => widget.job.status == 'in_progress';

  Future<void> _start() async {
    setState(() {
      busy = true;
      err = null;
    });

    try {
      await widget.api.startTechnicianJob(widget.job.id);
      await widget.onAfterChange();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Job dimulai.')),
        );
      }
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _complete() async {
    setState(() {
      busy = true;
      err = null;
    });

    try {
      await widget.api.completeTechnicianJob(widget.job.id);
      await widget.onAfterChange();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Job selesai.')),
        );
      }
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Service Job • ${j.plate}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${jobStatusLabel(j.status)}'),
                    const SizedBox(height: 6),
                    Text('Jadwal: ${j.scheduledAt ?? '-'}'),
                    Text('Estimasi selesai: ${j.estimatedFinishAt ?? '-'}'),
                    Text('Mulai: ${j.startedAt ?? '-'}'),
                    Text('Selesai: ${j.completedAt ?? '-'}'),
                    const SizedBox(height: 10),
                    Text('Kendaraan: ${j.vehicleName} • ${j.plate}'),
                    const SizedBox(height: 10),
                    if ((j.noteAdmin ?? '').trim().isNotEmpty)
                      Text('Catatan admin: ${j.noteAdmin}'),
                    if ((j.noteDriver ?? '').trim().isNotEmpty)
                      Text('Catatan driver: ${j.noteDriver}'),
                  ],
                ),
              ),
            ),

            if (err != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(err!, style: const TextStyle(color: Colors.red)),
              ),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : widget.onOpenReport,
                    icon: const Icon(Icons.description),
                    label: const Text('Buka Laporan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (busy || !canStart) ? null : _start,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Mulai'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            FilledButton.icon(
              onPressed: (busy || !canComplete) ? null : _complete,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle),
              label: const Text('Selesai'),
            ),

            const SizedBox(height: 8),
            Text(
              'Catatan: "Mulai" hanya untuk approved/rescheduled. "Selesai" hanya untuk in_progress.',
              style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BottomSheet: Detail + Respond + Sparepart + Cost Estimate (LAMA - tidak diubah)
// ============================================================
class _ReportRespondSheet extends StatefulWidget {
  final dynamic reportDetail;
  final ApiService api;
  final Future<void> Function() onAfterAnyChange;

  const _ReportRespondSheet({
    required this.reportDetail,
    required this.api,
    required this.onAfterAnyChange,
  });

  @override
  State<_ReportRespondSheet> createState() => _ReportRespondSheetState();
}

class _ReportRespondSheetState extends State<_ReportRespondSheet> {
  bool sendingRespond = false;

  // respond
  String status = 'proses';
  final noteC = TextEditingController(); // backend note nullable

  // sparepart
  bool needSparepart = false;
  bool loadingParts = false;
  List<dynamic> parts = [];
  String partSearch = '';
  final partIdC = TextEditingController();
  final qtyC = TextEditingController(text: '1');
  final spareNoteC = TextEditingController();

  // cost estimate
  bool savingEstimate = false;
  ApiCostEstimate? existingEstimate;

  final laborC = TextEditingController(text: '0');
  final partsCostC = TextEditingController(text: '0');
  final otherC = TextEditingController(text: '0');
  final estNoteC = TextEditingController();

  String? err;

  // =========================
  // DETAIL PARSERS
  // =========================
  int _reportId() {
    final m = _toMap(widget.reportDetail);
    return _toInt(m?['id']);
  }

  Map<String, dynamic>? _detailMap() => _toMap(widget.reportDetail);

  String _plate() {
    final m = _detailMap();
    final v = _toMap(m?['vehicle']);
    return _toStr(v?['plate_number'] ?? v?['plate'] ?? v?['plateNumber']) ?? '-';
  }

  String _brand() {
    final m = _detailMap();
    final v = _toMap(m?['vehicle']);
    return _toStr(v?['brand']) ?? '-';
  }

  String _driver() {
    final m = _detailMap();
    final d = _toMap(m?['driver']);
    return _toStr(d?['username'] ?? d?['name']) ?? '-';
  }

  String _desc() {
    final m = _detailMap();
    return (m?['description'] ?? '').toString();
  }

  List<dynamic> _techResponsesRaw() {
    final m = _detailMap();
    final raw = m?['technician_responses'] ?? m?['technicianResponses'];
    return _toList(raw);
  }

  String _lastStatus() {
    final m = _detailMap();
    final latestRaw =
        m?['latest_technician_response'] ?? m?['latestTechnicianResponse'];
    final latest = _toMap(latestRaw);
    final s1 = _toStr(latest?['status']);
    if (s1 != null) return s1;

    final trs = _techResponsesRaw();
    if (trs.isNotEmpty) {
      final last = _toMap(trs.last);
      final s2 = _toStr(last?['status']);
      if (s2 != null) return s2;
    }

    return 'menunggu';
  }

  String _lastNote() {
    final m = _detailMap();
    final latestRaw =
        m?['latest_technician_response'] ?? m?['latestTechnicianResponse'];
    final latest = _toMap(latestRaw);
    final n1 = _toStr(latest?['note']);
    if (n1 != null) return n1;

    final trs = _techResponsesRaw();
    if (trs.isNotEmpty) {
      final last = _toMap(trs.last);
      final n2 = _toStr(last?['note']);
      if (n2 != null) return n2;
    }

    return '-';
  }

  void _loadExistingEstimateFromDetail() {
    final m = _detailMap();
    final ceMap = _toMap(m?['cost_estimate'] ?? m?['costEstimate']);
    if (ceMap == null) return;

    final ce = ApiCostEstimate.fromJson(ceMap);
    existingEstimate = ce;

    laborC.text = ce.laborCost.toString();
    partsCostC.text = ce.partsCost.toString();
    otherC.text = ce.otherCost.toString();
    estNoteC.text = ce.note ?? '';
  }

  @override
  void initState() {
    super.initState();
    status = normalizeTechnicianRespondStatus(_lastStatus());
    _loadExistingEstimateFromDetail();
  }

  @override
  void dispose() {
    noteC.dispose();
    partIdC.dispose();
    qtyC.dispose();
    spareNoteC.dispose();
    laborC.dispose();
    partsCostC.dispose();
    otherC.dispose();
    estNoteC.dispose();
    super.dispose();
  }

  // =========================
  // SPAREPART helpers
  // =========================
  void _resetSparepart() {
    setState(() {
      needSparepart = false;
      partIdC.text = '';
      qtyC.text = '1';
      spareNoteC.text = '';
      partSearch = '';
      parts = [];
    });
  }

  void _stepQty(int delta) {
    final current = int.tryParse(qtyC.text.trim()) ?? 1;
    final next = (current + delta).clamp(1, 999);
    qtyC.text = next.toString();
    setState(() {});
  }

  Future<void> _loadParts({String search = ''}) async {
    setState(() {
      loadingParts = true;
      err = null;
    });

    try {
      final dynamic res = await widget.api.listPartsTechnician(search: search);
      if (res is List) {
        setState(() => parts = res);
      } else if (res is Map) {
        final data = _toList(res['data']);
        setState(() => parts = data);
      } else {
        setState(() => parts = []);
      }
    } catch (e) {
      setState(() => err = 'Gagal load parts: ${e.toString()}');
    } finally {
      if (mounted) setState(() => loadingParts = false);
    }
  }

  // =========================
  // SUBMIT: RESPOND (+ optional sparepart)
  // =========================
  Future<void> _submitRespond() async {
    final rid = _reportId();
    if (rid <= 0) {
      setState(() => err = 'Report ID tidak valid.');
      return;
    }

    final note = noteC.text.trim(); // backend nullable

    final partId = int.tryParse(partIdC.text.trim()) ?? 0;
    final qty = int.tryParse(qtyC.text.trim()) ?? 0;
    final spareNote = spareNoteC.text.trim();

    if (needSparepart) {
      if (partId <= 0) {
        setState(() => err = 'Part ID wajib diisi.');
        return;
      }
      if (qty <= 0) {
        setState(() => err = 'Qty sparepart wajib angka >= 1.');
        return;
      }
    }

    setState(() {
      sendingRespond = true;
      err = null;
    });

    try {
      final payload = <String, dynamic>{"status": status};
      if (note.isNotEmpty) payload["note"] = note;

      await widget.api.respondDamageReport(rid, payload);

      if (needSparepart) {
        await widget.api.requestPartUsage(
          damageReportId: rid,
          partId: partId,
          qty: qty,
          note: (spareNote.isNotEmpty
              ? spareNote
              : (note.isNotEmpty ? note : null)),
        );
      }

      await widget.onAfterAnyChange();
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => sendingRespond = false);
    }
  }

  // =========================
  // COST ESTIMATE
  // =========================
  int _readMoney(TextEditingController c) {
    final raw = c.text.trim().replaceAll('.', '').replaceAll(',', '');
    return int.tryParse(raw) ?? 0;
  }

  Future<void> _saveEstimateDraftOrUpdate() async {
    final rid = _reportId();
    if (rid <= 0) {
      setState(() => err = 'Report ID tidak valid.');
      return;
    }

    final labor = _readMoney(laborC);
    final partsCst = _readMoney(partsCostC);
    final other = _readMoney(otherC);
    final note = estNoteC.text.trim();

    if (labor < 0 || partsCst < 0 || other < 0) {
      setState(() => err = 'Biaya tidak boleh negatif.');
      return;
    }

    setState(() {
      savingEstimate = true;
      err = null;
    });

    try {
      final res = await widget.api.createOrUpdateCostEstimateForReport(
        damageReportId: rid,
        laborCost: labor,
        partsCost: partsCst,
        otherCost: other,
        note: note.isEmpty ? null : note,
      );

      Map<String, dynamic>? data;
      if (res is Map) {
        data = _toMap(res['data']) ?? _toMap(res);
      } else {
        data = _toMap(res);
      }

      if (data != null) {
        setState(() => existingEstimate = ApiCostEstimate.fromJson(data!));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Estimasi tersimpan (draft).')),
        );
      }
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => savingEstimate = false);
    }
  }

  Future<void> _submitEstimate() async {
    final ce = existingEstimate;
    if (ce == null) {
      setState(() => err = 'Estimasi belum dibuat. Simpan draft dulu.');
      return;
    }

    setState(() {
      savingEstimate = true;
      err = null;
    });

    try {
      await widget.api.submitCostEstimate(costEstimateId: ce.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Estimasi dikirim ke admin.')),
        );
      }

      await widget.onAfterAnyChange();
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => savingEstimate = false);
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final plate = _plate();
    final brand = _brand();
    final driver = _driver();
    final desc = _desc();
    final lastStatus = _lastStatus();
    final lastNote = _lastNote();

    final ce = existingEstimate;
    final ceStatus = ce?.status ?? 'belum ada';

    final cannotEditEstimate =
        (ce?.isApproved ?? false) || (ce?.isRejected ?? false);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Detail Laporan • $plate',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kendaraan: $brand • $plate'),
                    const SizedBox(height: 6),
                    Text('Driver: $driver'),
                    const SizedBox(height: 10),
                    const Text(
                      'Keluhan driver:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(desc),
                    const SizedBox(height: 10),
                    Text('Status terakhir: ${statusLabel(lastStatus)}'),
                    const SizedBox(height: 6),
                    Text('Catatan terakhir: $lastNote'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (err != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(err!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 10),

            _sectionHeader('Respon Teknisi'),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: status,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'proses', child: Text('Proses')),
                DropdownMenuItem(
                    value: 'butuh_followup_admin',
                    child: Text('Butuh Follow-up Admin')),
                DropdownMenuItem(value: 'fatal', child: Text('Fatal')),
                DropdownMenuItem(value: 'selesai', child: Text('Selesai')),
              ],
              onChanged: (v) => setState(() {
                status = normalizeTechnicianRespondStatus(v ?? status);
              }),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Status',
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: noteC,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Catatan teknisi (opsional)',
                hintText:
                    'Backend mengizinkan kosong, tapi disarankan isi tindakan/diagnosa...',
              ),
            ),

            const SizedBox(height: 14),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pengambilan Sparepart (ke Admin)',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(onPressed: _resetSparepart, child: const Text('Reset')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Request sparepart?'),
                      subtitle: const Text('Kirim permintaan sparepart ke admin.'),
                      value: needSparepart,
                      onChanged: (v) => setState(() => needSparepart = v),
                    ),
                    if (needSparepart) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: partIdC,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Part ID',
                          hintText: 'Masukkan ID part (sesuai backend)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => partSearch = v),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Cari Part (opsional)',
                                hintText: 'Nama/SKU…',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: loadingParts ? null : () => _loadParts(search: partSearch),
                            icon: loadingParts
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.search),
                            label: const Text('Cari'),
                          ),
                        ],
                      ),
                      if (parts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black.withOpacity(0.08)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Hasil pencarian:',
                                  style: TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              ...parts.take(5).map((p) {
                                final pm = _toMap(p) ?? {};
                                final pid = _toInt(pm['id']);
                                final name = _toStr(pm['name']) ?? '-';
                                final sku = _toStr(pm['sku']) ?? '-';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(name),
                                  subtitle: Text('ID: $pid • SKU: $sku'),
                                  trailing: TextButton(
                                    onPressed: () {
                                      partIdC.text = pid.toString();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Part dipilih: $name (ID $pid)')),
                                      );
                                    },
                                    child: const Text('Pilih'),
                                  ),
                                );
                              }).toList(),
                              if (parts.length > 5)
                                Text(
                                  'Menampilkan 5 teratas…',
                                  style: TextStyle(
                                      color: Colors.black.withOpacity(0.6), fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Qty:', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          IconButton(
                            onPressed: () => _stepQty(-1),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 64,
                            child: TextField(
                              controller: qtyC,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _stepQty(1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.withOpacity(0.25)),
                            ),
                            child: const Text(
                              'Status: requested',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: spareNoteC,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Catatan sparepart (opsional)',
                          hintText: 'Contoh: butuh segera / alasan pengambilan',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            FilledButton.icon(
              onPressed: sendingRespond ? null : _submitRespond,
              icon: sendingRespond
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(sendingRespond ? 'Mengirim...' : 'Kirim Respon'),
            ),

            const SizedBox(height: 18),

            _sectionHeader('Estimasi Biaya (Cost Estimate)'),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Status Estimasi: $ceStatus',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (ce != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black.withOpacity(0.10)),
                              color: (ce.isApproved
                                  ? Colors.green.withOpacity(0.10)
                                  : (ce.isRejected
                                      ? Colors.red.withOpacity(0.10)
                                      : Colors.blue.withOpacity(0.06))),
                            ),
                            child: Text(
                              ce.isApproved
                                  ? 'APPROVED'
                                  : (ce.isRejected
                                      ? 'REJECTED'
                                      : (ce.isSubmitted ? 'SUBMITTED' : 'DRAFT')),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (cannotEditEstimate)
                      Text(
                        'Estimasi sudah diputuskan admin, tidak bisa diubah.',
                        style: TextStyle(color: Colors.black.withOpacity(0.65)),
                      ),

                    const SizedBox(height: 10),

                    _moneyField(
                      controller: laborC,
                      label: 'Biaya Jasa (labor_cost)',
                      enabled: !cannotEditEstimate,
                    ),
                    const SizedBox(height: 10),
                    _moneyField(
                      controller: partsCostC,
                      label: 'Biaya Sparepart (parts_cost)',
                      enabled: !cannotEditEstimate,
                    ),
                    const SizedBox(height: 10),
                    _moneyField(
                      controller: otherC,
                      label: 'Biaya Lain-lain (other_cost)',
                      enabled: !cannotEditEstimate,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: estNoteC,
                      enabled: !cannotEditEstimate,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Catatan estimasi (opsional)',
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (savingEstimate || cannotEditEstimate)
                                ? null
                                : _saveEstimateDraftOrUpdate,
                            icon: savingEstimate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('Simpan Draft'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                (savingEstimate || cannotEditEstimate) ? null : _submitEstimate,
                            icon: savingEstimate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: const Text('Submit ke Admin'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'Flow backend: draft/submitted boleh diupdate, approved/rejected dikunci.',
                      style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String t) => Text(
        t,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      );

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        hintText: 'contoh: 150000',
      ),
    );
  }
}
