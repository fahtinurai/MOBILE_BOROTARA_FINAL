class ApiVehicle {
  final int id;
  final String? brand;
  final String? model;
  final String? plateNumber;
  final int? year;

  // ✅ fitur pengingat servis berikutnya
  final DateTime? nextServiceAt;
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

  // =========================
  // SAFE HELPERS
  // =========================
  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static bool _toBool(dynamic v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase().trim();
    if (s == '1' || s == 'true' || s == 'yes') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return fallback;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  factory ApiVehicle.fromJson(Map<String, dynamic> j) {
    return ApiVehicle(
      id: _toInt(j['id'], 0),
      brand: j['brand']?.toString(),
      model: j['model']?.toString(),
      plateNumber: (j['plate_number'] ?? j['plate'] ?? j['plateNumber'])?.toString(),
      year: (j['year'] is int) ? j['year'] as int : int.tryParse('${j['year']}'),

      // ✅ service reminder
      nextServiceAt: _toDate(j['next_service_at'] ?? j['nextServiceAt']),
      reminderEnabled: _toBool(j['reminder_enabled'] ?? j['reminderEnabled'], false),
      reminderDaysBefore: _toInt(j['reminder_days_before'] ?? j['reminderDaysBefore'], 3),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "brand": brand,
        "model": model,
        "plate_number": plateNumber,
        "year": year,

        // ✅ service reminder
        "next_service_at": nextServiceAt?.toIso8601String(),
        "reminder_enabled": reminderEnabled,
        "reminder_days_before": reminderDaysBefore,
      };
}

// =====================================================
// ✅ NEW MODELS: Booking, CostEstimate, Review
// =====================================================

class ApiServiceBooking {
  final int id;
  final int damageReportId;
  final int driverId;
  final int vehicleId;

  final DateTime? scheduledAt;
  final String status;

  // estimasi antrian/waktu
  final DateTime? estimatedStartAt;
  final DateTime? estimatedFinishAt;
  final int? queueNumber;

  final String? noteDriver;
  final String? noteAdmin;

  ApiServiceBooking({
    required this.id,
    required this.damageReportId,
    required this.driverId,
    required this.vehicleId,
    this.scheduledAt,
    required this.status,
    this.estimatedStartAt,
    this.estimatedFinishAt,
    this.queueNumber,
    this.noteDriver,
    this.noteAdmin,
  });

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static String _toStr(dynamic v, [String fallback = '']) {
    final s = v?.toString();
    if (s == null || s.trim().isEmpty) return fallback;
    return s;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  factory ApiServiceBooking.fromJson(Map<String, dynamic> j) {
    return ApiServiceBooking(
      id: _toInt(j['id'], 0),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId'], 0),
      driverId: _toInt(j['driver_id'] ?? j['driverId'], 0),
      vehicleId: _toInt(j['vehicle_id'] ?? j['vehicleId'], 0),
      scheduledAt: _toDate(j['scheduled_at'] ?? j['scheduledAt']),
      status: _toStr(j['status'], 'requested'),
      estimatedStartAt: _toDate(j['estimated_start_at'] ?? j['estimatedStartAt']),
      estimatedFinishAt: _toDate(j['estimated_finish_at'] ?? j['estimatedFinishAt']),
      queueNumber: (j['queue_number'] == null && j['queueNumber'] == null)
          ? null
          : _toInt(j['queue_number'] ?? j['queueNumber']),
      noteDriver: (j['note_driver'] ?? j['noteDriver'])?.toString(),
      noteAdmin: (j['note_admin'] ?? j['noteAdmin'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "damage_report_id": damageReportId,
        "driver_id": driverId,
        "vehicle_id": vehicleId,
        "scheduled_at": scheduledAt?.toIso8601String(),
        "status": status,
        "estimated_start_at": estimatedStartAt?.toIso8601String(),
        "estimated_finish_at": estimatedFinishAt?.toIso8601String(),
        "queue_number": queueNumber,
        "note_driver": noteDriver,
        "note_admin": noteAdmin,
      };
}

class ApiCostEstimate {
  final int id;
  final int damageReportId;
  final int technicianId;

  final int laborCost;
  final int partsCost;
  final int otherCost;
  final int totalCost;

  final String status; // draft|submitted|approved|rejected
  final String? note;

  final int? approvedBy;
  final DateTime? approvedAt;

  ApiCostEstimate({
    required this.id,
    required this.damageReportId,
    required this.technicianId,
    required this.laborCost,
    required this.partsCost,
    required this.otherCost,
    required this.totalCost,
    required this.status,
    this.note,
    this.approvedBy,
    this.approvedAt,
  });

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  factory ApiCostEstimate.fromJson(Map<String, dynamic> j) {
    final labor = _toInt(j['labor_cost'] ?? j['laborCost'], 0);
    final parts = _toInt(j['parts_cost'] ?? j['partsCost'], 0);
    final other = _toInt(j['other_cost'] ?? j['otherCost'], 0);

    // total_cost bisa dari backend, tapi kalau belum ada, kita hitung fallback
    final total = (j['total_cost'] ?? j['totalCost']) == null
        ? (labor + parts + other)
        : _toInt(j['total_cost'] ?? j['totalCost'], (labor + parts + other));

    return ApiCostEstimate(
      id: _toInt(j['id'], 0),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId'], 0),
      technicianId: _toInt(j['technician_id'] ?? j['technicianId'], 0),
      laborCost: labor,
      partsCost: parts,
      otherCost: other,
      totalCost: total,
      status: (j['status'] ?? 'draft').toString(),
      note: j['note']?.toString(),
      approvedBy: (j['approved_by'] ?? j['approvedBy']) == null
          ? null
          : _toInt(j['approved_by'] ?? j['approvedBy']),
      approvedAt: _toDate(j['approved_at'] ?? j['approvedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "damage_report_id": damageReportId,
        "technician_id": technicianId,
        "labor_cost": laborCost,
        "parts_cost": partsCost,
        "other_cost": otherCost,
        "total_cost": totalCost,
        "status": status,
        "note": note,
        "approved_by": approvedBy,
        "approved_at": approvedAt?.toIso8601String(),
      };
}

class ApiTechnicianReview {
  final int id;
  final int damageReportId;
  final int driverId;
  final int technicianId;

  final int rating; // 1..5
  final String? review;
  final DateTime? createdAt;

  ApiTechnicianReview({
    required this.id,
    required this.damageReportId,
    required this.driverId,
    required this.technicianId,
    required this.rating,
    this.review,
    this.createdAt,
  });

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  factory ApiTechnicianReview.fromJson(Map<String, dynamic> j) {
    return ApiTechnicianReview(
      id: _toInt(j['id'], 0),
      damageReportId: _toInt(j['damage_report_id'] ?? j['damageReportId'], 0),
      driverId: _toInt(j['driver_id'] ?? j['driverId'], 0),
      technicianId: _toInt(j['technician_id'] ?? j['technicianId'], 0),
      rating: _toInt(j['rating'], 0),
      review: j['review']?.toString(),
      createdAt: _toDate(j['created_at'] ?? j['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "damage_report_id": damageReportId,
        "driver_id": driverId,
        "technician_id": technicianId,
        "rating": rating,
        "review": review,
        "created_at": createdAt?.toIso8601String(),
      };
}

// =====================================================
// ✅ ApiDamageReport (updated)
// =====================================================

class ApiDamageReport {
  final int id;
  final String description;
  final String status;
  final String? note;
  final ApiVehicle? vehicle;

  // ✅ fitur baru (optional)
  final ApiServiceBooking? booking;
  final ApiCostEstimate? costEstimate;
  final ApiTechnicianReview? review;

  ApiDamageReport({
    required this.id,
    required this.description,
    required this.status,
    this.note,
    this.vehicle,
    this.booking,
    this.costEstimate,
    this.review,
  });

  // =========================
  // SAFE HELPERS
  // =========================
  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static String? _toStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.trim().isEmpty ? null : s;
  }

  static Map<String, dynamic>? _asMap(dynamic x) {
    if (x is Map<String, dynamic>) return x;
    if (x is Map) return x.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  // =========================
  // JSON (API BACKEND)
  // =========================
  factory ApiDamageReport.fromJson(Map<String, dynamic> j) {
    final latest = _asMap(j['latestTechnicianResponse'] ?? j['latest_technician_response']);

    final trs = j['technicianResponses'] ?? j['technician_responses'];
    Map<String, dynamic>? last;
    if (trs is List && trs.isNotEmpty) last = _asMap(trs.last);

    final computedStatus =
        _toStr(latest?['status']) ??
        _toStr(last?['status']) ??
        _toStr(j['computed_status']) ?? // kalau backend kamu pakai accessor computed_status
        _toStr(j['status']) ??
        'menunggu';

    final computedNote =
        _toStr(latest?['note']) ??
        _toStr(last?['note']) ??
        _toStr(j['note']);

    final v = _asMap(j['vehicle']);

    // ✅ fitur baru: booking / cost_estimate / review
    final b = _asMap(j['booking'] ?? j['service_booking']);
    final c = _asMap(j['costEstimate'] ?? j['cost_estimate']);
    final r = _asMap(j['review'] ?? j['technician_review']);

    return ApiDamageReport(
      id: _toInt(j['id'], 0),
      description: (j['description'] ?? '').toString(),
      status: computedStatus,
      note: computedNote,
      vehicle: v != null ? ApiVehicle.fromJson(v) : null,
      booking: b != null ? ApiServiceBooking.fromJson(b) : null,
      costEstimate: c != null ? ApiCostEstimate.fromJson(c) : null,
      review: r != null ? ApiTechnicianReview.fromJson(r) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "description": description,
        "status": status,
        "note": note,
        "vehicle": vehicle?.toJson(),
        "booking": booking?.toJson(),
        "cost_estimate": costEstimate?.toJson(),
        "review": review?.toJson(),
      };

  // =========================
  // ✅ FIREBASE / FCM HELPERS
  // =========================

  static bool isDamageReportPayload(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    return type == 'damage_report';
  }

  static int payloadReportId(Map<String, dynamic> data) {
    return _toInt(data['report_id'] ?? data['damage_report_id'] ?? data['id'], 0);
  }

  static String payloadRole(Map<String, dynamic> data) {
    return (data['role'] ?? '').toString().toLowerCase();
  }

  Map<String, dynamic> toFcmDataPayload({
    required String role, // 'driver' / 'teknisi' / 'admin'
  }) {
    return {
      "type": "damage_report",
      "role": role,
      "report_id": id.toString(),
      "status": status,
      if (vehicle?.plateNumber != null) "plate_number": vehicle!.plateNumber!,
    };
  }
}
