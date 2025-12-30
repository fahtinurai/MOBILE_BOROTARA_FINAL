// models.dart
// Gabungan semua model yang dipakai di aplikasi (Driver/Technician/Admin mobile)
// - Aman untuk snake_case & camelCase
// - Siap untuk fitur baru: booking, cost estimate, review/rating, service reminder vehicle
//
// ✅ PATCH FINAL (compatible dengan technician_home.dart terakhir):
// - Tambah ApiServiceJob (untuk tab Jobs teknisi)
// - Tambah Reviews response models (summary + items)
// - Normalisasi status job agar "done/finished" => "completed" (non-breaking)


// =============================
// SAFE PARSERS
// =============================
int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? fallback;
}

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

String? _toStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.trim().isEmpty ? null : s;
}

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString().toLowerCase().trim();
  if (s == '1' || s == 'true' || s == 'yes') return true;
  if (s == '0' || s == 'false' || s == 'no') return false;
  return fallback;
}

Map<String, dynamic>? _toMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

List<dynamic> _toList(dynamic v) => (v is List) ? v : <dynamic>[];

// =============================
// USER (MINIMAL)
// =============================
class ApiUser {
  final int id;
  final String? name;
  final String? username;
  final String? role;

  ApiUser({
    required this.id,
    this.name,
    this.username,
    this.role,
  });

  factory ApiUser.fromJson(Map<String, dynamic> j) {
    return ApiUser(
      id: _toInt(j['id']),
      name: _toStr(j['name']),
      username: _toStr(j['username']),
      role: _toStr(j['role']),
    );
  }

  String get displayName =>
      (name ?? username ?? '').trim().isEmpty ? '-' : (name ?? username ?? '-');
}

// =============================
// VEHICLE
// + fitur reminder servis (baru)
// =============================
class ApiVehicle {
  final int id;
  final String? brand;
  final String? model;
  final String? plateNumber;
  final int? year;

  // fitur baru (optional)
  final String? nextServiceAt; // ISO string (backend datetime)
  final bool reminderEnabled;
  final int reminderDaysBefore;

  ApiVehicle({
    required this.id,
    this.brand,
    this.model,
    this.plateNumber,
    this.year,
    this.nextServiceAt,
    this.reminderEnabled = false,
    this.reminderDaysBefore = 3,
  });

  factory ApiVehicle.fromJson(Map<String, dynamic> j) {
    return ApiVehicle(
      id: _toInt(j['id']),
      brand: _toStr(j['brand']),
      model: _toStr(j['model']),
      plateNumber: _toStr(j['plate_number'] ?? j['plate'] ?? j['plateNumber']),
      year: j['year'] is int ? j['year'] as int : int.tryParse('${j['year']}'),
      nextServiceAt: _toStr(j['next_service_at'] ?? j['nextServiceAt']),
      reminderEnabled:
          _toBool(j['reminder_enabled'] ?? j['reminderEnabled'], false),
      reminderDaysBefore:
          _toInt(j['reminder_days_before'] ?? j['reminderDaysBefore'], 3),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "brand": brand,
        "model": model,
        "plate_number": plateNumber,
        "year": year,
        "next_service_at": nextServiceAt,
        "reminder_enabled": reminderEnabled,
        "reminder_days_before": reminderDaysBefore,
      };

  String get displayName {
    final name = '${brand ?? ''} ${model ?? ''}'.trim();
    return name.isEmpty ? 'Kendaraan' : name;
  }
}

// =============================
// TECHNICIAN RESPONSE (LATEST / TIMELINE)
// =============================
class ApiTechnicianResponse {
  final int id;
  final String? status;
  final String? note;
  final String? createdAt;

  // optional: info teknisi kalau backend include
  final ApiUser? technician;

  ApiTechnicianResponse({
    required this.id,
    this.status,
    this.note,
    this.createdAt,
    this.technician,
  });

  factory ApiTechnicianResponse.fromJson(Map<String, dynamic> j) {
    final techMap = _toMap(j['technician']);
    return ApiTechnicianResponse(
      id: _toInt(j['id']),
      status: _toStr(j['status']),
      note: _toStr(j['note']),
      createdAt: _toStr(j['created_at'] ?? j['updated_at']),
      technician: techMap != null ? ApiUser.fromJson(techMap) : null,
    );
  }
}

// =============================
// BOOKING SERVIS (baru) - tetap dipertahankan (non-breaking)
// =============================
class ApiServiceBooking {
  final int id;
  final int damageReportId;
  final int driverId;
  final int vehicleId;

  final String scheduledAt; // required (existing behavior)
  final String status; // requested|approved|rescheduled|canceled|done

  final String? estimatedStartAt;
  final String? estimatedFinishAt;
  final int? queueNumber;

  final String? noteDriver;
  final String? noteAdmin;

  ApiServiceBooking({
    required this.id,
    required this.damageReportId,
    required this.driverId,
    required this.vehicleId,
    required this.scheduledAt,
    required this.status,
    this.estimatedStartAt,
    this.estimatedFinishAt,
    this.queueNumber,
    this.noteDriver,
    this.noteAdmin,
  });

  factory ApiServiceBooking.fromJson(Map<String, dynamic> j) {
    return ApiServiceBooking(
      id: _toInt(j['id']),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId']),
      driverId: _toInt(j['driver_id'] ?? j['driverId']),
      vehicleId: _toInt(j['vehicle_id'] ?? j['vehicleId']),
      scheduledAt: _toStr(j['scheduled_at'] ?? j['scheduledAt']) ?? '',
      status: _toStr(j['status']) ?? 'requested',
      estimatedStartAt: _toStr(j['estimated_start_at'] ?? j['estimatedStartAt']),
      estimatedFinishAt:
          _toStr(j['estimated_finish_at'] ?? j['estimatedFinishAt']),
      queueNumber: (j['queue_number'] ?? j['queueNumber']) == null
          ? null
          : _toInt(j['queue_number'] ?? j['queueNumber']),
      noteDriver: _toStr(j['note_driver'] ?? j['noteDriver']),
      noteAdmin: _toStr(j['note_admin'] ?? j['noteAdmin']),
    );
  }

  bool get isApproved => status == 'approved';
  bool get isCanceled => status == 'canceled';
  bool get isDone => status == 'done';
}

// =============================
// COST ESTIMATE (baru)
// =============================
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
  final int? approvedBy;
  final String? approvedAt;

  final ApiUser? technician;
  final ApiUser? approver;

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
    this.approvedBy,
    this.approvedAt,
    this.technician,
    this.approver,
  });

  factory ApiCostEstimate.fromJson(Map<String, dynamic> j) {
    final techMap = _toMap(j['technician']);
    final approverMap = _toMap(
      j['approver'] ?? j['approved_by_user'] ?? j['approvedByUser'],
    );

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
      approvedBy: (j['approved_by'] ?? j['approvedBy']) == null
          ? null
          : _toInt(j['approved_by'] ?? j['approvedBy']),
      approvedAt: _toStr(j['approved_at'] ?? j['approvedAt']),
      technician: techMap != null ? ApiUser.fromJson(techMap) : null,
      approver: approverMap != null ? ApiUser.fromJson(approverMap) : null,
    );
  }

  bool get isSubmitted => status == 'submitted';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isDraft => status == 'draft';
}

// =============================
// TECHNICIAN REVIEW (baru) - tetap dipertahankan (non-breaking)
// (dipakai di driver side / report detail / dll)
// =============================
class ApiTechnicianReview {
  final int id;
  final int damageReportId;
  final int driverId;
  final int technicianId;

  final int rating; // 1..5
  final String? review;

  final String? createdAt;

  final ApiUser? technician;
  final ApiUser? driver;

  ApiTechnicianReview({
    required this.id,
    required this.damageReportId,
    required this.driverId,
    required this.technicianId,
    required this.rating,
    this.review,
    this.createdAt,
    this.technician,
    this.driver,
  });

  factory ApiTechnicianReview.fromJson(Map<String, dynamic> j) {
    final techMap = _toMap(j['technician']);
    final driverMap = _toMap(j['driver']);

    return ApiTechnicianReview(
      id: _toInt(j['id']),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId']),
      driverId: _toInt(j['driver_id'] ?? j['driverId']),
      technicianId: _toInt(j['technician_id'] ?? j['technicianId']),
      rating: _toInt(j['rating']),
      review: _toStr(j['review']),
      createdAt: _toStr(j['created_at']),
      technician: techMap != null ? ApiUser.fromJson(techMap) : null,
      driver: driverMap != null ? ApiUser.fromJson(driverMap) : null,
    );
  }
}

// =============================
// DAMAGE REPORT (utama)
// - terintegrasi: vehicle, responses, booking, cost estimate, review
// =============================
class ApiDamageReport {
  final int id;
  final String description;

  /// ✅ selalu ada (fallback menunggu)
  final String status;

  /// ✅ note terakhir (optional)
  final String? note;

  final String? createdAt;

  final ApiVehicle? vehicle;
  final ApiTechnicianResponse? latestResponse;
  final List<ApiTechnicianResponse> responses;

  // fitur baru (optional, bisa null kalau backend belum include)
  final ApiServiceBooking? booking;
  final ApiCostEstimate? costEstimate;
  final ApiTechnicianReview? reviewData;

  ApiDamageReport({
    required this.id,
    required this.description,
    required this.status,
    this.note,
    this.createdAt,
    this.vehicle,
    this.latestResponse,
    this.responses = const [],
    this.booking,
    this.costEstimate,
    this.reviewData,
  });

  factory ApiDamageReport.fromJson(Map<String, dynamic> j) {
    // ===== vehicle =====
    ApiVehicle? v;
    final vMap = _toMap(j['vehicle']);
    if (vMap != null) v = ApiVehicle.fromJson(vMap);

    // ===== responses list (snake & camel) =====
    final respRaw = j['technician_responses'] ?? j['technicianResponses'];
    final respList = _toList(respRaw)
        .map(_toMap)
        .whereType<Map<String, dynamic>>()
        .map(ApiTechnicianResponse.fromJson)
        .toList();

    // ===== latest response (snake & camel) =====
    ApiTechnicianResponse? latest;
    final latestMap = _toMap(
      j['latest_technician_response'] ?? j['latestTechnicianResponse'],
    );
    if (latestMap != null) {
      latest = ApiTechnicianResponse.fromJson(latestMap);
    }

    // ===== status resolution =====
    final computedStatus = _toStr(latest?.status) ??
        (respList.isNotEmpty ? _toStr(respList.last.status) : null) ??
        _toStr(j['status']) ??
        'menunggu';

    // ===== note resolution =====
    final computedNote = _toStr(latest?.note) ??
        (respList.isNotEmpty ? _toStr(respList.last.note) : null) ??
        _toStr(j['note']);

    // ===== booking / cost estimate / review (optional) =====
    ApiServiceBooking? booking;
    final bookingMap =
        _toMap(j['booking'] ?? j['service_booking'] ?? j['serviceBooking']);
    if (bookingMap != null) booking = ApiServiceBooking.fromJson(bookingMap);

    ApiCostEstimate? estimate;
    final estMap = _toMap(j['cost_estimate'] ?? j['costEstimate']);
    if (estMap != null) estimate = ApiCostEstimate.fromJson(estMap);

    ApiTechnicianReview? rev;
    final revMap =
        _toMap(j['review'] ?? j['technician_review'] ?? j['technicianReview']);
    if (revMap != null) rev = ApiTechnicianReview.fromJson(revMap);

    return ApiDamageReport(
      id: _toInt(j['id']),
      description: (j['description'] ?? '').toString(),
      status: computedStatus,
      note: computedNote,
      createdAt: _toStr(j['created_at'] ?? j['createdAt']),
      vehicle: v,
      latestResponse: latest,
      responses: respList,
      booking: booking,
      costEstimate: estimate,
      reviewData: rev,
    );
  }

  /// OPTIONAL: object cepat dari payload FCM `data`
  factory ApiDamageReport.fromFcmData(Map<String, dynamic> data) {
    final reportId = _toInt(data['report_id'] ?? data['reportId']);
    final status = _toStr(data['status']) ?? 'menunggu';

    ApiVehicle? v;
    final plate = _toStr(data['plate_number'] ?? data['plateNumber']);
    if (plate != null) {
      v = ApiVehicle(id: 0, plateNumber: plate);
    }

    return ApiDamageReport(
      id: reportId,
      description: _toStr(data['description']) ?? '',
      status: status,
      note: _toStr(data['note']),
      vehicle: v,
      createdAt: _toStr(data['created_at'] ?? data['createdAt']),
      responses: const [],
      latestResponse: null,
    );
  }

  // =============================
  // UI Helpers
  // =============================
  String get plate => vehicle?.plateNumber ?? '-';

  /// sesuai aturan kamu: kalau sudah ada respon teknisi berarti terkunci
  bool get isLocked =>
      (latestResponse != null) || responses.isNotEmpty || status != 'menunggu';

  bool get isFinished => status == 'selesai';

  bool get canBook => !isFinished;

  bool get canReview => isFinished;

  bool get hasBooking => booking != null;

  bool get hasCostEstimate => costEstimate != null;

  bool get hasReview => reviewData != null;
}


// =====================================================
// ✅ ADDITIONS FOR technician_home.dart (FINAL COMPAT)
// =====================================================

// =============================
// ✅ JOBS (ServiceJobController)
// Backend biasanya return: ServiceBooking + nested damageReport
// GET  /technician/jobs?status=queue|active|all
// POST /technician/jobs/{booking}/start
// POST /technician/jobs/{booking}/complete
// =============================

/// Normalisasi status job supaya UI technician_home.dart stabil.
/// - done/finished -> completed
/// - cancel/cancelled -> canceled
String normalizeJobStatus(String raw) {
  final s = (raw).trim().toLowerCase();
  if (s == 'done' || s == 'finished') return 'completed';
  if (s == 'cancelled') return 'canceled';
  return s;
}

class ApiServiceJob {
  final int id; // booking id
  final String status; // approved/rescheduled/in_progress/completed/canceled/...
  final String? scheduledAt;
  final String? estimatedFinishAt;
  final String? startedAt;
  final String? completedAt;
  final String? noteAdmin;
  final String? noteDriver;

  final int damageReportId;
  final ApiDamageReport? damageReport; // nested untuk plate & vehicleName

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

    final rawStatus = _toStr(j['status']) ?? '-';
    final normalized = normalizeJobStatus(rawStatus);

    return ApiServiceJob(
      id: _toInt(j['id']),
      status: normalized,
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
}

// =============================
// ✅ REVIEWS (TechnicianReviewController@index)
// GET /technician/reviews
// return:
// {
//   "summary": { "avg_rating": 4.5, "total_reviews": 10 },
//   "data": { "data": [ ...paginate items... ], ... }
// }
// =============================

class ApiTechnicianReviewSummary {
  final double avgRating;
  final int totalReviews;

  ApiTechnicianReviewSummary({
    required this.avgRating,
    required this.totalReviews,
  });

  factory ApiTechnicianReviewSummary.fromJson(Map<String, dynamic> j) {
    return ApiTechnicianReviewSummary(
      avgRating: _toDouble(j['avg_rating'] ?? j['avgRating'], 0),
      totalReviews: _toInt(j['total_reviews'] ?? j['totalReviews'], 0),
    );
  }
}

class ApiTechnicianReviewItem {
  final int id;
  final int damageReportId;
  final int driverId;
  final int technicianId;

  final int rating; // 1..5
  final String? review;

  /// backend pakai reviewed_at (index controller)
  final String? reviewedAt;

  final ApiUser? driver;

  /// opsional nested damageReport->vehicle->plate_number (kalau backend include)
  final String? plateNumber;

  ApiTechnicianReviewItem({
    required this.id,
    required this.damageReportId,
    required this.driverId,
    required this.technicianId,
    required this.rating,
    this.review,
    this.reviewedAt,
    this.driver,
    this.plateNumber,
  });

  factory ApiTechnicianReviewItem.fromJson(Map<String, dynamic> j) {
    final driverMap = _toMap(j['driver']);
    final drMap = _toMap(j['damageReport'] ?? j['damage_report']);
    final vehicleMap = drMap == null ? null : _toMap(drMap['vehicle']);
    final plate = _toStr(vehicleMap?['plate_number'] ??
        vehicleMap?['plate'] ??
        vehicleMap?['plateNumber']);

    return ApiTechnicianReviewItem(
      id: _toInt(j['id']),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId']),
      driverId: _toInt(j['driver_id'] ?? j['driverId']),
      technicianId: _toInt(j['technician_id'] ?? j['technicianId']),
      rating: _toInt(j['rating']),
      review: _toStr(j['review'] ?? j['comment'] ?? j['note'] ?? j['message']),
      reviewedAt: _toStr(j['reviewed_at'] ?? j['reviewedAt'] ?? j['created_at']),
      driver: driverMap != null ? ApiUser.fromJson(driverMap) : null,
      plateNumber: plate,
    );
  }

  String get driverName => driver?.displayName ?? '-';
  String get plate => plateNumber ?? '-';
}

class ApiTechnicianReviewsResponse {
  final ApiTechnicianReviewSummary summary;
  final List<ApiTechnicianReviewItem> items;

  ApiTechnicianReviewsResponse({
    required this.summary,
    required this.items,
  });

  factory ApiTechnicianReviewsResponse.fromJson(Map<String, dynamic> j) {
    final sumMap = _toMap(j['summary']) ?? const <String, dynamic>{};
    final dataRaw = j['data'];

    // paginate: data.data = list
    List<dynamic> rawItems = [];
    if (dataRaw is Map) {
      final inner = dataRaw['data'];
      rawItems = _toList(inner);
    } else if (dataRaw is List) {
      rawItems = dataRaw;
    } else if (j['items'] is List) {
      rawItems = _toList(j['items']);
    }

    final items = rawItems
        .map(_toMap)
        .whereType<Map<String, dynamic>>()
        .map(ApiTechnicianReviewItem.fromJson)
        .toList();

    return ApiTechnicianReviewsResponse(
      summary: ApiTechnicianReviewSummary.fromJson(sumMap),
      items: items,
    );
  }
}
