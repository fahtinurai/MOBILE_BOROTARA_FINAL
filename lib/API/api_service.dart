import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

// =============================
// MODE REQUEST
// =============================
enum ApiMode { dio, http }

class ApiService {
  // =============================
  // CONFIG
  // =============================
  static const String baseUrl = "http://10.0.2.2:8000/api";
  static const String loginUrl = "$baseUrl/login";

  // =============================
  //  FCM ENDPOINTS
  // =============================
  static const String fcmRegisterEndpoint = "/mobile/fcm-token";
  static const String fcmUnregisterEndpoint = "/mobile/fcm-token/delete";

  final String? token;
  final ApiMode mode;

  late final Dio _dio;

  ApiService({required this.mode, this.token}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: _headers(),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
  }

  Map<String, String> _headers() {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // =============================
  // JSON helpers
  // =============================
  dynamic _decodeBody(String body) {
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  dynamic _unwrapDio(Response res) => res.data;

  dynamic _unwrapHttp(http.Response res) {
    final data = _decodeBody(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    if (data is Map) {
      final msg = data['message']?.toString();
      if (msg != null && msg.isNotEmpty) throw Exception(msg);

      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final firstKey = errors.keys.first.toString();
        final firstVal = errors[firstKey];
        if (firstVal is List && firstVal.isNotEmpty) {
          throw Exception(firstVal.first.toString());
        }
      }
    }

    throw Exception('HTTP ${res.statusCode}');
  }

  Exception _dioToException(DioException e) {
    final data = e.response?.data;

    if (data is Map) {
      final msg = data['message']?.toString();
      if (msg != null && msg.isNotEmpty) return Exception(msg);

      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final firstKey = errors.keys.first.toString();
        final firstVal = errors[firstKey];
        if (firstVal is List && firstVal.isNotEmpty) {
          return Exception(firstVal.first.toString());
        }
      }
    }

    if (data is String && data.trim().isNotEmpty) {
      return Exception(data);
    }

    // timeout / no internet
    return Exception(e.message ?? 'Network error');
  }

  /// =============================
  /// ✅ NEW: unwrap payload Map {message, data} biar kompatibel
  /// - kalau response = {data: ...} -> return data
  /// - kalau response = {message, data} -> return data
  /// - kalau response = list/map biasa -> return as-is
  /// =============================
  dynamic _unwrapData(dynamic res) {
    if (res is Map) {
      final m = res.map((k, v) => MapEntry(k.toString(), v));
      if (m.containsKey('data')) return m['data'];
    }
    return res;
  }

  Map<String, dynamic>? _unwrapDataMap(dynamic res) {
    final u = _unwrapData(res);
    if (u is Map<String, dynamic>) return u;
    if (u is Map) return u.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  // =============================
  // ✅ UTC-safe helpers
  // - selalu kirim datetime sebagai ISO UTC (Z)
  // =============================
  String _toUtcIso(DateTime dt) => dt.toUtc().toIso8601String();
  String? _toUtcIsoOrNull(DateTime? dt) => dt == null ? null : _toUtcIso(dt);

  // =============================
  // QueryString builder
  // =============================
  String _qs(Map<String, dynamic?> params) {
    final q = <String, String>{};

    params.forEach((k, v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      q[k] = s;
    });

    if (q.isEmpty) return '';
    return '?' +
        q.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
  }

  // =============================
  // CORE REQUEST HANDLER
  // =============================
  Future<dynamic> _get(String endpoint) async {
    if (mode == ApiMode.dio) {
      try {
        final res = await _dio.get(endpoint);
        return _unwrapDio(res);
      } on DioException catch (e) {
        throw _dioToException(e);
      }
    } else {
      final res = await http.get(
        Uri.parse(baseUrl + endpoint),
        headers: _headers(),
      );
      return _unwrapHttp(res);
    }
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> body) async {
    if (mode == ApiMode.dio) {
      try {
        final res = await _dio.post(endpoint, data: body);
        return _unwrapDio(res);
      } on DioException catch (e) {
        throw _dioToException(e);
      }
    } else {
      final res = await http.post(
        Uri.parse(baseUrl + endpoint),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return _unwrapHttp(res);
    }
  }

  Future<dynamic> _put(String endpoint, Map<String, dynamic> body) async {
    if (mode == ApiMode.dio) {
      try {
        final res = await _dio.put(endpoint, data: body);
        return _unwrapDio(res);
      } on DioException catch (e) {
        throw _dioToException(e);
      }
    } else {
      final res = await http.put(
        Uri.parse(baseUrl + endpoint),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return _unwrapHttp(res);
    }
  }

  Future<dynamic> _delete(String endpoint) async {
    if (mode == ApiMode.dio) {
      try {
        final res = await _dio.delete(endpoint);
        return _unwrapDio(res);
      } on DioException catch (e) {
        throw _dioToException(e);
      }
    } else {
      final res = await http.delete(
        Uri.parse(baseUrl + endpoint),
        headers: _headers(),
      );
      return _unwrapHttp(res);
    }
  }

  // =============================
  // AUTH
  // =============================
  Future<dynamic> login(String username, String password) async {
    final res = await http.post(
      Uri.parse(loginUrl),
      headers: _headers(),
      body: jsonEncode({"username": username, "password": password}),
    );
    return _unwrapHttp(res);
  }

  Future<dynamic> me() => _get('/me');

  /// logout (kadang backend return {message,data} / {message} -> ok)
  Future<dynamic> logout() => _post('/logout', {});

  // =============================
  // ✅ FCM
  // =============================
  Future<dynamic> registerFcmToken(String fcmToken) {
    final t = fcmToken.trim();
    if (t.isEmpty) throw Exception('FCM token kosong.');
    return _post(fcmRegisterEndpoint, {"token": t});
  }

  Future<dynamic> unregisterFcmToken(String fcmToken) {
    final t = fcmToken.trim();
    if (t.isEmpty) throw Exception('FCM token kosong.');
    return _post(fcmUnregisterEndpoint, {"token": t});
  }

  // =============================
  // DRIVER: VEHICLES / ASSIGNMENTS
  // =============================
  Future<List<dynamic>> driverAssignments() async {
    final res = await _get('/driver/vehicles');
    final u = _unwrapData(res);
    return (u is List) ? u : <dynamic>[];
  }

  Future<List<dynamic>> driverVehicles() async {
    final a = await driverAssignments();
    final out = <dynamic>[];

    for (final item in a) {
      if (item is Map) {
        final v = item['vehicle'];
        if (v != null) out.add(v);
      }
    }
    return out;
  }

  // =============================
  // DRIVER: DAMAGE REPORT
  // =============================
  Future<dynamic> verifyVehicle(String plate) =>
      _post('/driver/vehicles/verify', {"plate_number": plate});

  Future<dynamic> createDamageReportDriver({
    required String plateNumber,
    required String description,
  }) {
    return _post('/driver/damage-reports', {
      "plate_number": plateNumber,
      "description": description,
    });
  }

  Future<dynamic> getDamageReportsDriver({String? status}) {
    final qs = _qs({
      "status": (status == null || status == 'all') ? null : status,
    });
    return _get('/driver/damage-reports$qs');
  }

  Future<dynamic> getDamageReportDriverDetail(int id) =>
      _get('/driver/damage-reports/$id');

  Future<dynamic> updateDamageReportDriver({
    required int id,
    required String description,
  }) =>
      _put('/driver/damage-reports/$id', {"description": description});

  Future<dynamic> deleteDamageReportDriver(int id) =>
      _delete('/driver/damage-reports/$id');

  // =============================
  // ✅ DRIVER: BOOKING
  // POST /driver/damage-reports/{damageReport}/booking
  // Body: preferred_at (nullable date), note_driver (nullable string)
  // =============================
  Future<dynamic> createBookingDriver({
    required int reportId,
    DateTime? preferredAt,
    String? noteDriver,
  }) async {
    final res = await _post('/driver/damage-reports/$reportId/booking', {
      if (preferredAt != null) "preferred_at": _toUtcIso(preferredAt),
      if (noteDriver != null && noteDriver.trim().isNotEmpty)
        "note_driver": noteDriver.trim(),
    });

    // supaya kompatibel walau backend return {message,data}
    return _unwrapData(res);
  }

  /// GET /driver/damage-reports/{damageReport}/booking (can be null)
  Future<dynamic> getBookingDriver(int reportId) async {
    final res = await _get('/driver/damage-reports/$reportId/booking');
    return _unwrapData(res);
  }

  /// POST /driver/bookings/{booking}/cancel
  Future<dynamic> cancelBookingDriver({required int bookingId}) =>
      _post('/driver/bookings/$bookingId/cancel', {});

  // =============================
  // DRIVER: COST ESTIMATE (view only)
  // =============================
  Future<dynamic> getCostEstimateDriver(int reportId) =>
      _get('/driver/damage-reports/$reportId/cost-estimate');

  // =============================
  // DRIVER: REVIEW / RATING
  // =============================
  Future<dynamic> getReviewDriver(int reportId) =>
      _get('/driver/damage-reports/$reportId/review');

  Future<dynamic> submitReviewDriver({
    required int reportId,
    required int rating,
    String? review,
  }) {
    return _post('/driver/damage-reports/$reportId/review', {
      "rating": rating,
      if (review != null && review.trim().isNotEmpty) "review": review.trim(),
    });
  }

  // =============================
  // DRIVER: SERVICE REMINDER
  // =============================
  Future<dynamic> updateVehicleServiceReminder({
    required int vehicleId,
    required DateTime? nextServiceAt,
    required bool reminderEnabled,
    required int reminderDaysBefore,
  }) {
    return _put('/driver/vehicles/$vehicleId/service-reminder', {
      "next_service_at": _toUtcIsoOrNull(nextServiceAt),
      "reminder_enabled": reminderEnabled,
      "reminder_days_before": reminderDaysBefore,
    });
  }

  Future<dynamic> updateServiceReminderDriver({
    required int vehicleId,
    required DateTime? nextServiceAt,
    required bool reminderEnabled,
    required int reminderDaysBefore,
  }) =>
      updateVehicleServiceReminder(
        vehicleId: vehicleId,
        nextServiceAt: nextServiceAt,
        reminderEnabled: reminderEnabled,
        reminderDaysBefore: reminderDaysBefore,
      );

  // =============================
  // TECHNICIAN: DAMAGE REPORTS
  // =============================
  Future<dynamic> getDamageReportsTechnician({
    String? status,
    bool? includeDone,
  }) {
    final qs = _qs({
      "status": (status == null || status == 'all') ? null : status,
      "include_done": includeDone == null ? null : (includeDone ? '1' : '0'),
    });

    return _get('/technician/damage-reports$qs');
  }

  Future<dynamic> getDamageReportTechnicianDetail(int id) =>
      _get('/technician/damage-reports/$id');

  Future<dynamic> respondDamageReport(int id, Map<String, dynamic> data) =>
      _post('/technician/damage-reports/$id/respond', data);

  Future<dynamic> updateTechnicianResponse({
    required int technicianResponseId,
    required String status,
    required String note,
  }) =>
      _put('/technician/technician-responses/$technicianResponseId', {
        "status": status,
        "note": note,
      });

  Future<dynamic> myResponses() => _get('/technician/my-responses');

  // =============================
  // ✅ TECHNICIAN: SERVICE JOBS
  // Routes:
  // GET  /technician/jobs
  // GET  /technician/jobs/{booking}
  // POST /technician/jobs/{booking}/start
  // POST /technician/jobs/{booking}/complete
  // =============================
  Future<dynamic> getTechnicianJobs({String? status}) {
    final qs = _qs({
      "status": (status == null || status == 'all') ? null : status,
    });
    return _get('/technician/jobs$qs');
  }

  Future<dynamic> getTechnicianJobDetail(int bookingId) {
    if (bookingId <= 0) throw Exception('bookingId tidak valid.');
    return _get('/technician/jobs/$bookingId');
  }

  Future<dynamic> startTechnicianJob(int bookingId) {
    if (bookingId <= 0) throw Exception('bookingId tidak valid.');
    return _post('/technician/jobs/$bookingId/start', {});
  }

  Future<dynamic> completeTechnicianJob(int bookingId) {
    if (bookingId <= 0) throw Exception('bookingId tidak valid.');
    return _post('/technician/jobs/$bookingId/complete', {});
  }

  // =============================
  // ✅ TECHNICIAN: REVIEWS (NEW)
  // GET /technician/reviews
  // =============================
  Future<dynamic> getTechnicianReviews({int? page}) {
    final qs = _qs({
      if (page != null && page > 0) "page": page,
    });
    return _get('/technician/reviews$qs');
  }

  // =========================
  // TECHNICIAN – SPAREPART
  // =========================
  Future<List<dynamic>> listPartsTechnician({String search = ''}) async {
    final s = search.trim();
    final endpoint = s.isEmpty
        ? '/technician/parts'
        : '/technician/parts?search=${Uri.encodeQueryComponent(s)}';

    try {
      final res = await _get(endpoint);
      final u = _unwrapData(res);
      return (u is List) ? u : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<dynamic> requestPartUsage({
    required int damageReportId,
    required int partId,
    required int qty,
    String? note,
  }) {
    return _post('/technician/part-usages', {
      "damage_report_id": damageReportId,
      "part_id": partId,
      "qty": qty,
      if (note != null) "note": note,
    });
  }

  Future<List<dynamic>> myPartUsages() async {
    final res = await _get('/technician/my-part-usages');
    final u = _unwrapData(res);
    return (u is List) ? u : <dynamic>[];
  }

  // =============================
  // TECHNICIAN: COST ESTIMATE
  // =============================
  Future<dynamic> createOrUpdateCostEstimateForReport({
    int? reportId,
    int? damageReportId,
    required int laborCost,
    required int partsCost,
    int otherCost = 0,
    String? note,
  }) {
    final rid = reportId ?? damageReportId ?? 0;
    if (rid <= 0) throw Exception('reportId/damageReportId wajib diisi.');

    return _post('/technician/damage-reports/$rid/cost-estimate', {
      "labor_cost": laborCost,
      "parts_cost": partsCost,
      "other_cost": otherCost,
      if (note != null && note.trim().isNotEmpty) "note": note.trim(),
    });
  }

  Future<dynamic> updateCostEstimateTechnician({
    required int costEstimateId,
    int? laborCost,
    int? partsCost,
    int? otherCost,
    String? note,
    String? status,
  }) {
    return _put('/technician/cost-estimates/$costEstimateId', {
      if (laborCost != null) "labor_cost": laborCost,
      if (partsCost != null) "parts_cost": partsCost,
      if (otherCost != null) "other_cost": otherCost,
      if (note != null) "note": note,
      if (status != null) "status": status,
    });
  }

  Future<dynamic> submitCostEstimate({required int costEstimateId}) =>
      _post('/technician/cost-estimates/$costEstimateId/submit', {});

  Future<dynamic> submitCostEstimateTechnician({required int costEstimateId}) =>
      submitCostEstimate(costEstimateId: costEstimateId);

  // =============================
  // ADMIN: BOOKING
  // =============================
  Future<dynamic> adminBookings({String status = 'requested'}) {
    final qs = _qs({"status": status});
    return _get('/admin/bookings$qs');
  }

  /// - scheduled_at (admin set jadwal final)
  /// - estimated_finish_at (opsional)
  /// - note_admin (opsional)
  Future<dynamic> adminApproveBooking({
    required int bookingId,
    required DateTime scheduledAt,
    DateTime? estimatedFinishAt,
    String? noteAdmin,
  }) {
    return _post('/admin/bookings/$bookingId/approve', {
      "scheduled_at": _toUtcIso(scheduledAt),
      if (estimatedFinishAt != null)
        "estimated_finish_at": _toUtcIso(estimatedFinishAt),
      if (noteAdmin != null && noteAdmin.trim().isNotEmpty)
        "note_admin": noteAdmin.trim(),
    });
  }

  Future<dynamic> adminCancelBooking({
    required int bookingId,
    String? noteAdmin,
  }) {
    return _post('/admin/bookings/$bookingId/cancel', {
      if (noteAdmin != null && noteAdmin.trim().isNotEmpty)
        "note_admin": noteAdmin.trim(),
    });
  }

  // =============================
  // ADMIN: COST ESTIMATES
  // =============================
  Future<dynamic> adminCostEstimates({String status = 'submitted'}) {
    final qs = _qs({"status": status});
    return _get('/admin/cost-estimates$qs');
  }

  Future<dynamic> adminApproveCostEstimate({required int costEstimateId}) =>
      _post('/admin/cost-estimates/$costEstimateId/approve', {});

  Future<dynamic> adminRejectCostEstimate({
    required int costEstimateId,
    String? note,
  }) {
    return _post('/admin/cost-estimates/$costEstimateId/reject', {
      if (note != null && note.trim().isNotEmpty) "note": note.trim(),
    });
  }
}
