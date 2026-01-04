// driver_report_detail.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'API/api_service.dart';

class DriverReportDetailPage extends StatefulWidget {
  final String token;
  final int reportId;

  const DriverReportDetailPage({
    super.key,
    required this.token,
    required this.reportId,
  });

  @override
  State<DriverReportDetailPage> createState() => _DriverReportDetailPageState();
}

class _DriverReportDetailPageState extends State<DriverReportDetailPage> {
  late final ApiService api;

  bool loading = false;
  String? err;
  Map<String, dynamic>? report;

  // ===== booking / estimate / review =====
  bool loadingBooking = false;
  bool loadingEstimate = false;
  bool loadingReview = false;

  Map<String, dynamic>? booking;
  Map<String, dynamic>? costEstimate;
  Map<String, dynamic>? review;

  String? estimateMsg;

  // =========================
  // BOOKING (Driver side)
  // =========================
  DateTime? _preferredAt;
  final bookingNoteC = TextEditingController();

  // review form
  int _rating = 5;
  final reviewC = TextEditingController();

  // =========================
  // SAFE HELPERS
  // =========================
  Map<String, dynamic>? _toMap(dynamic x) {
    if (x is Map<String, dynamic>) return x;
    if (x is Map) return x.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  List<dynamic> _toList(dynamic x) => (x is List) ? x : <dynamic>[];

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

  int? _extractStatusCode(dynamic e) {
    try {
      final resp = (e as dynamic).response;
      final code = resp?.statusCode;
      if (code is int) return code;
    } catch (_) {}
    return null;
  }

  String? _extractBackendMessage(dynamic e) {
    try {
      final resp = (e as dynamic).response;
      final data = resp?.data;
      final m = _toMap(data);
      final msg = m?['message']?.toString();
      if (msg != null && msg.trim().isNotEmpty) return msg;
    } catch (_) {}
    return null;
  }

  // =========================
  // ✅ UNWRAP HELPERS (for {message, data:{...}})
  // =========================
  Map<String, dynamic>? _unwrapDataMap(dynamic res) {
    final m = _toMap(res);
    if (m == null) return null;

    // kalau backend return {message, data:{...}}
    final data = m['data'];
    final dm = _toMap(data);
    if (dm != null) return dm;

    // kalau backend return {...} langsung
    return m;
  }

  // =========================
  // ✅ REVIEW NORMALIZER
  // - supaya response {message, data:null} tidak dianggap review
  // - dan objek aneh tanpa id/rating juga dianggap null
  // =========================
  Map<String, dynamic>? _normalizeReview(dynamic res) {
    final m = _unwrapDataMap(res);
    if (m == null || m.isEmpty) return null;

    final id = _toInt(m['id'], 0);
    final rating = _toInt(m['rating'], 0);

    // kalau tidak punya id & rating <= 0 → ini bukan review valid
    if (id <= 0 && rating <= 0) return null;

    return m;
  }

  // =========================
  // ✅ fallback nama teknisi (biar tidak "-")
  // ambil dari latestTechnicianResponse / berbagai kemungkinan field
  // =========================
  String _fallbackTechnicianName() {
    final latest = _latestResponse();

    // coba berbagai kemungkinan struktur (aman)
    final techMap = _toMap(
      latest?['technician'] ??
          latest?['technician_user'] ??
          latest?['user'] ??
          report?['technician'],
    );

    final direct =
        latest?['technician_name'] ?? latest?['technician_username'];

    final name = _str(
      direct ??
          techMap?['username'] ??
          techMap?['name'] ??
          techMap?['full_name'],
      '-',
    );

    return name;
  }

  @override
  void initState() {
    super.initState();
    api = ApiService(mode: ApiMode.dio, token: widget.token);
    _loadAll();
  }

  @override
  void dispose() {
    bookingNoteC.dispose();
    reviewC.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _load(); // report detail
    await Future.wait([_loadBooking(), _loadCostEstimate(), _loadReview()]);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });

    try {
      final res = await api.getDamageReportDriverDetail(widget.reportId);
      setState(() => report = _toMap(res));
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadBooking() async {
    setState(() => loadingBooking = true);
    try {
      final res = await api.getBookingDriver(widget.reportId);
      final m = _toMap(res);
      setState(() => booking = m);

      // optional: isi form update dari data yang ada (supaya tidak overwrite kosong)
      if (m != null) {
        final nd = _str(m['note_driver'], '');
        if (nd.isNotEmpty && nd != '-') {
          bookingNoteC.text = nd;
        }
      }
    } catch (e) {
      setState(() => booking = null);
    } finally {
      if (mounted) setState(() => loadingBooking = false);
    }
  }

  Future<void> _loadCostEstimate() async {
    setState(() {
      loadingEstimate = true;
      estimateMsg = null;
    });

    try {
      final res = await api.getCostEstimateDriver(widget.reportId);
      setState(() {
        costEstimate = _toMap(res);
        estimateMsg = null;
      });
    } catch (e) {
      final code = _extractStatusCode(e);
      final backendMsg = _extractBackendMessage(e);

      String msg = backendMsg ?? 'Estimasi biaya belum tersedia.';
      if (code == 404) {
        msg = backendMsg ?? 'Estimasi biaya belum tersedia.';
      } else if (code == 403) {
        msg = backendMsg ?? 'Estimasi biaya belum disetujui admin.';
      } else if (code != null) {
        msg = backendMsg ?? 'Gagal memuat estimasi (HTTP $code).';
      }

      setState(() {
        costEstimate = null;
        estimateMsg = msg;
      });
    } finally {
      if (mounted) setState(() => loadingEstimate = false);
    }
  }

  // =========================
  // ✅ REVIEW LOAD (fixed + normalize)
  // =========================
  Future<void> _loadReview() async {
    setState(() => loadingReview = true);
    try {
      final res = await api.getReviewDriver(widget.reportId);
      setState(() => review = _normalizeReview(res));
    } catch (_) {
      setState(() => review = null);
    } finally {
      if (mounted) setState(() => loadingReview = false);
    }
  }

  // =========================
  // PARSERS
  // =========================
  Map<String, dynamic>? _vehicle() => _toMap(report?['vehicle']);

  String _plate() {
    final v = _vehicle();
    return _str(v?['plate_number'] ?? v?['plate'] ?? v?['plateNumber']);
  }

  String _desc() => _str(report?['description'], '-');

  List<dynamic> _responses() {
    final trs =
        report?['technicianResponses'] ?? report?['technician_responses'];
    return _toList(trs);
  }

  Map<String, dynamic>? _latestResponse() {
    final latest =
        report?['latestTechnicianResponse'] ??
        report?['latest_technician_response'];
    return _toMap(latest);
  }

  bool _locked() {
    return _latestResponse() != null || _responses().isNotEmpty;
  }

  String _lastStatus() {
    final latest = _latestResponse();
    final s1 = _str(latest?['status'], '');
    if (s1.isNotEmpty && s1 != '-') return s1;

    final trs = _responses();
    if (trs.isEmpty) return 'menunggu';

    final last = _toMap(trs.last);
    final s2 = _str(last?['status'], '');
    if (s2.isNotEmpty && s2 != '-') return s2;

    return 'menunggu';
  }

  String _lastNote() {
    final latest = _latestResponse();
    final n1 = _str(latest?['note'], '');
    if (n1.isNotEmpty && n1 != '-') return n1;

    final trs = _responses();
    if (trs.isEmpty) return '-';

    final last = _toMap(trs.last);
    final n2 = _str(last?['note'], '');
    if (n2.isNotEmpty && n2 != '-') return n2;

    return '-';
  }

  bool _canReview() {
    final latest = _latestResponse();
    final st = _str(latest?['status'], '').toLowerCase().trim();
    return st == 'selesai';
  }

  // =========================
  // ACTIONS: edit/delete report
  // =========================
  Future<void> _edit() async {
    if (_locked()) {
      _toast('❌ Laporan sudah diproses teknisi, tidak bisa diedit.');
      return;
    }

    final c = TextEditingController(text: _desc());

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Deskripsi'),
        content: TextField(
          controller: c,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await api.updateDamageReportDriver(
        id: widget.reportId,
        description: c.text.trim(),
      );
      _toast('✅ Berhasil diupdate.');
      await _loadAll();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  Future<void> _delete() async {
    if (_locked()) {
      _toast('❌ Laporan sudah diproses teknisi, tidak bisa dihapus.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Laporan?'),
        content: const Text('Aksi ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await api.deleteDamageReportDriver(widget.reportId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  // =========================
  // BOOKING ACTIONS
  // =========================
  Future<void> _pickPreferredAt() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _preferredAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_preferredAt ?? DateTime.now()),
    );
    if (t == null) return;

    setState(() {
      _preferredAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _createOrUpdateBooking() async {
    try {
      await api.createBookingDriver(
        reportId: widget.reportId,
        preferredAt: _preferredAt,
        noteDriver: bookingNoteC.text.trim().isEmpty
            ? null
            : bookingNoteC.text.trim(),
      );
      _toast('✅ Booking berhasil diajukan.');
      await _loadBooking();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  Future<void> _cancelBooking() async {
    final b = booking;
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
      await _loadBooking();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  // =========================
  // ✅ REVIEW ACTION (fixed + normalize)
  // =========================
  Future<void> _submitReview() async {
    if (!_canReview()) {
      _toast('❌ Rating hanya bisa setelah status "selesai".');
      return;
    }

    try {
      final res = await api.submitReviewDriver(
        reportId: widget.reportId,
        rating: _rating,
        review: reviewC.text.trim().isEmpty ? null : reviewC.text.trim(),
      );

      // ✅ normalize supaya tidak salah anggap review ada
      setState(() => review = _normalizeReview(res));

      _toast('✅ Review tersimpan.');
    } catch (e) {
      _toast('❌ ${e.toString()}');
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  // =========================
  // BOOKING UI HELPERS
  // =========================

  // ✅ parse backend datetime (ISO atau "YYYY-MM-DD HH:mm:ss") -> local DateTime
  DateTime? _parseBackendDate(dynamic raw) {
    if (raw == null) return null;

    final s = raw.toString().trim();
    if (s.isEmpty || s == '-') return null;

    // normalize jika backend kadang kirim "YYYY-MM-DD HH:mm:ss"
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');

    try {
      return DateTime.parse(normalized).toLocal();
    } catch (_) {
      return null;
    }
  }

  // ✅ tampilkan datetime sebagai lokal "dd MMM yyyy, HH:mm"
  String _fmtDateTime(dynamic raw) {
    final dt = _parseBackendDate(raw);
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt);
  }

  String _fmtPreferredLocal(DateTime? dt) {
    if (dt == null) return 'Belum dipilih';
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt.toLocal());
  }

  Color _badgeBg(String status) {
    final s = status.toLowerCase();
    if (s == 'requested') return Colors.orange.withOpacity(0.12);
    if (s == 'approved') return Colors.blue.withOpacity(0.12);
    if (s == 'rescheduled') return Colors.purple.withOpacity(0.12);
    if (s == 'canceled') return Colors.red.withOpacity(0.12);
    if (s == 'done' || s == 'finished') return Colors.green.withOpacity(0.12);
    return Colors.grey.withOpacity(0.12);
  }

  Color _badgeBorder(String status) {
    final s = status.toLowerCase();
    if (s == 'requested') return Colors.orange.withOpacity(0.4);
    if (s == 'approved') return Colors.blue.withOpacity(0.4);
    if (s == 'rescheduled') return Colors.purple.withOpacity(0.4);
    if (s == 'canceled') return Colors.red.withOpacity(0.4);
    if (s == 'done' || s == 'finished') return Colors.green.withOpacity(0.4);
    return Colors.grey.withOpacity(0.4);
  }

  Widget _statusBadge(String status) {
    final st = _str(status, '-');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _badgeBg(st),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _badgeBorder(st)),
      ),
      child: Text(st, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final plate = _plate();

    return Scaffold(
      appBar: AppBar(
        title: Text('Detail • $plate'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : err != null
                ? Center(
                    child: Text(err!, style: const TextStyle(color: Colors.red)),
                  )
                : report == null
                    ? const Center(child: Text('Data tidak ditemukan.'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _infoCard(
                            title: 'Ringkasan',
                            children: [
                              _kv('Plat', plate),
                              _kv('Status', _lastStatus()),
                              _kv('Catatan terakhir', _lastNote()),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _infoCard(
                            title: 'Deskripsi Driver',
                            children: [Text(_desc())],
                          ),
                          const SizedBox(height: 12),
                          _bookingCard(),
                          const SizedBox(height: 12),
                          _costEstimateCard(),
                          const SizedBox(height: 12),
                          _reviewCard(),
                          const SizedBox(height: 12),
                          _infoCard(
                            title: 'Timeline Respon Teknisi',
                            children: _responses().isEmpty
                                ? [const Text('Belum ada respon teknisi.')]
                                : _responses().map((x) {
                                    final m = _toMap(x) ?? <String, dynamic>{};
                                    final st = _str(m['status']);
                                    final note = _str(m['note']);

                                    // ✅ tampil lokal rapi
                                    final at = _fmtDateTime(
                                        m['created_at'] ?? m['updated_at']);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.blue.withOpacity(0.25),
                                        ),
                                        color: Colors.blue.withOpacity(0.05),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            st,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(note),
                                          const SizedBox(height: 6),
                                          Text(
                                            at,
                                            style: TextStyle(
                                              color: Colors.black
                                                  .withOpacity(0.55),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _locked() ? null : _edit,
                                  icon: const Icon(Icons.edit),
                                  label: Text(
                                      _locked() ? 'Edit (Terkunci)' : 'Edit'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _locked() ? null : _delete,
                                  icon: const Icon(Icons.delete),
                                  label: Text(_locked()
                                      ? 'Hapus (Terkunci)'
                                      : 'Hapus'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_locked())
                            Text(
                              'Catatan: laporan terkunci karena sudah ada respon teknisi.',
                              style: TextStyle(
                                  color: Colors.black.withOpacity(0.6)),
                            ),
                        ],
                      ),
      ),
    );
  }

  // =========================
  // Booking card
  // =========================
  Widget _bookingCard() {
    final b = booking;

    String bookingStatus = '-';
    String requestedAt = '-';
    String scheduledAt = '-';
    String estFinish = '-';
    String noteAdmin = '-';
    String noteDriver = '-';

    if (b != null) {
      bookingStatus = _str(b['status']);
      requestedAt = _fmtDateTime(b['requested_at']);
      scheduledAt = _fmtDateTime(b['scheduled_at']);
      estFinish = _fmtDateTime(b['estimated_finish_at']);
      noteAdmin = _str(b['note_admin']);
      noteDriver = _str(b['note_driver']);
    }

    final finishedReport = _lastStatus() == 'selesai';

    final canCancel = b != null &&
        !finishedReport &&
        ['requested', 'approved', 'rescheduled']
            .contains(bookingStatus.toLowerCase());

    final canUpdateRequest = b != null &&
        !finishedReport &&
        bookingStatus.toLowerCase() != 'canceled' &&
        bookingStatus.toLowerCase() != 'cancelled';

    return _infoCard(
      title: 'Booking Servis',
      children: [
        if (loadingBooking) const LinearProgressIndicator(),
        if (!loadingBooking && b == null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Belum ada booking untuk laporan ini.',
                  style: TextStyle(color: Colors.black.withOpacity(0.75)),
                ),
              ),
              TextButton.icon(
                onPressed: _loadBooking,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.25)),
            ),
            child: Text(
              'Driver hanya mengajukan. Jadwal final akan ditentukan admin.',
              style: TextStyle(color: Colors.black.withOpacity(0.75)),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Preferensi jadwal (opsional)'),
            subtitle: Text(_fmtPreferredLocal(_preferredAt)),
            trailing: TextButton(
              onPressed: _pickPreferredAt,
              child: const Text('Pilih'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bookingNoteC,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Catatan untuk admin (opsional)',
              hintText: 'Contoh: minta pagi / kendaraan dipakai sore, dll.',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _createOrUpdateBooking,
            icon: const Icon(Icons.send),
            label: const Text('Ajukan Booking'),
          ),
          const SizedBox(height: 6),
          Text(
            'Sesuai backend: field yang dikirim = preferred_at & note_driver.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
        if (!loadingBooking && b != null) ...[
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.event_available, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Status booking',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              _statusBadge(bookingStatus),
            ],
          ),
          const SizedBox(height: 10),
          _kv('Requested at', requestedAt),
          _kv('Jadwal final (admin)', scheduledAt),
          _kv('Estimasi selesai', estFinish),
          const SizedBox(height: 8),
          const Divider(height: 18),
          _kv('Catatan driver', noteDriver),
          _kv('Catatan admin', noteAdmin),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canCancel ? _cancelBooking : null,
                  icon: const Icon(Icons.cancel),
                  label: Text(canCancel ? 'Batalkan' : 'Tidak bisa dibatalkan'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton.icon(
                  onPressed: _loadBooking,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (canUpdateRequest) ...[
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
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Preferensi jadwal'),
                    subtitle: Text(_preferredAt == null
                        ? 'Tidak diisi'
                        : _fmtPreferredLocal(_preferredAt)),
                    trailing: TextButton(
                      onPressed: _pickPreferredAt,
                      child: const Text('Ubah'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: bookingNoteC,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Catatan baru untuk admin',
                      hintText: 'Isi jika ingin memperbarui note_driver',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _createOrUpdateBooking,
                    icon: const Icon(Icons.update),
                    label: const Text('Update Booking Request'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Backend akan update booking untuk report ini (updateOrCreate).',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Admin yang mengisi jadwal final dan estimasi selesai.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  // =========================
  // Cost estimate card
  // =========================
  Widget _costEstimateCard() {
    final e = costEstimate;

    String status = '-';
    int labor = 0, parts = 0, other = 0, total = 0;
    String note = '-';
    String techName = '-';

    if (e != null) {
      status = _str(e['status']);
      labor = _toInt(e['labor_cost']);
      parts = _toInt(e['parts_cost']);
      other = _toInt(e['other_cost']);
      total = _toInt(e['total_cost']);
      note = _str(e['note']);
      final tech = _toMap(e['technician']);
      techName = _str(tech?['username'] ?? tech?['name'], '-');
    }

    return _infoCard(
      title: 'Estimasi Biaya',
      children: [
        if (loadingEstimate) const LinearProgressIndicator(),
        if (!loadingEstimate && e == null)
          Text(
            estimateMsg ?? 'Belum ada estimasi biaya dari teknisi.',
            style: TextStyle(color: Colors.black.withOpacity(0.7)),
          ),
        if (!loadingEstimate && e != null) ...[
          _kv('Status', status),
          _kv('Teknisi', techName),
          _kv('Jasa/Labor', labor.toString()),
          _kv('Sparepart', parts.toString()),
          _kv('Lainnya', other.toString()),
          _kv('Total', total.toString()),
          _kv('Catatan', note),
          const SizedBox(height: 6),
          Text(
            'Driver hanya bisa melihat. Admin harus approve agar estimasi tampil.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  // =========================
  // Review card (FIXED)
  // =========================
  Widget _reviewCard() {
    // ✅ pastikan yang dipakai adalah review valid
    final r = _normalizeReview(review);

    final latest = _latestResponse();
    final lastTechStatus = _str(latest?['status'], 'menunggu');
    final canRate = _canReview();

    String techName = '-';
    int rating = 0;
    String reviewText = '-';

    if (r != null) {
      rating = _toInt(r['rating']);

      // prefer field backend kamu: "review"
      reviewText = _str(r['review'], '-');

      final tech = _toMap(r['technician']);
      techName = _str(tech?['username'] ?? tech?['name'], '-');

      // fallback kalau field technician tidak ikut
      if (techName == '-' || techName.trim().isEmpty) {
        final fb = _fallbackTechnicianName();
        if (fb != '-') techName = fb;
      }
    } else {
      final fb = _fallbackTechnicianName();
      if (fb != '-') techName = fb;
    }

    return _infoCard(
      title: 'Rating & Ulasan Teknisi',
      children: [
        if (loadingReview) const LinearProgressIndicator(),
        Row(
          children: [
            Expanded(
              child: Text(
                'Status teknisi: $lastTechStatus',
                style: TextStyle(color: Colors.black.withOpacity(0.7)),
              ),
            ),
            TextButton.icon(
              onPressed: _loadReview,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reload'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (!canRate) ...[
          Text(
            'Rating hanya bisa setelah respon teknisi terakhir berstatus "selesai".',
            style: TextStyle(color: Colors.black.withOpacity(0.75)),
          ),
          const SizedBox(height: 6),
          Text(
            'Saat ini: "$lastTechStatus".',
            style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
          ),
        ],

        // ✅ hanya tampil "review tersimpan" jika review valid (r != null)
        if (!loadingReview && r != null) ...[
          _kv('Teknisi', techName),
          _kv('Rating', rating.toString()),
          _kv('Ulasan', reviewText),
          const SizedBox(height: 6),
          Text(
            'Terima kasih! Rating sudah tersimpan.',
            style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
          ),
        ],

        // ✅ form hanya muncul jika review belum ada DAN status selesai
        if (!loadingReview && r == null && canRate) ...[
          _kv('Teknisi', techName),
          const SizedBox(height: 8),
          const Text(
            'Berikan rating untuk transparansi:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _rating,
            items: const [
              DropdownMenuItem(value: 5, child: Text('5 - Sangat puas')),
              DropdownMenuItem(value: 4, child: Text('4 - Puas')),
              DropdownMenuItem(value: 3, child: Text('3 - Cukup')),
              DropdownMenuItem(value: 2, child: Text('2 - Kurang')),
              DropdownMenuItem(value: 1, child: Text('1 - Buruk')),
            ],
            onChanged: (v) => setState(() => _rating = v ?? 5),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Rating',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: reviewC,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Ulasan (opsional)',
              hintText: 'Contoh: cepat, jelas, komunikatif...',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _submitReview,
            icon: const Icon(Icons.star),
            label: const Text('Kirim Rating'),
          ),
        ],
        if (loadingReview) const SizedBox(height: 4),
      ],
    );
  }

  // =========================
  // Base widgets
  // =========================
  Widget _infoCard({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

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
