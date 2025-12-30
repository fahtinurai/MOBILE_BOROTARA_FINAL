// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart'; // ✅ sesuai push_fcm.dart (FlutterFire CLI)

import 'API/api_service.dart';
import 'utils/auth_storage.dart';
import 'utils/push_fcm.dart';

import 'driver_home.dart';
import 'driver_report_detail.dart';
import 'technician_home.dart';

// ✅ JANGAN BUAT navKey BARU.
// Pakai navKey dari push_fcm.dart supaya 1 sumber untuk navigasi notif.
// final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>(); // ❌ HAPUS / JANGAN DIPAKAI

/// =====================================================
/// MAIN
/// =====================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ WAJIB pakai options biar konsisten dengan push_fcm.dart (background handler juga pakai ini)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Handler notif saat app di background / terminated
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const BengkelApp());
}

/// =====================================================
/// ROOT APP
/// =====================================================
class BengkelApp extends StatelessWidget {
  const BengkelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bengkel Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),

      // ✅ penting supaya FCM bisa navigasi dari mana saja
      // ✅ ambil navKey dari push_fcm.dart (bukan bikin lagi)
      navigatorKey: navKey,

      home: const BootstrapPage(),
    );
  }
}

/// =====================================================
/// BOOTSTRAP PAGE
/// - cek token
/// - hit /me
/// - init FCM (sekali saja)
/// - redirect driver / teknisi
/// =====================================================
class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final token = await AuthStorage.getToken();
    if (!mounted) return;

    if (token == null) {
      _goLogin();
      return;
    }

    try {
      final api = ApiService(mode: ApiMode.dio, token: token);
      final me = await api.me();

      final role = _extractRole(me);
      if (role == null) throw Exception('Role tidak valid');

      // ✅ INIT FCM (idempotent)
      await _setupFcm(token);

      if (!mounted) return;

      if (role == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DriverHomePage(token: token)),
        );
      } else if (role == 'teknisi') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TechnicianHomePage(token: token)),
        );
      } else {
        throw Exception('Role tidak dikenali');
      }
    } catch (_) {
      await AuthStorage.clear();
      if (!mounted) return;
      _goLogin();
    }
  }

  void _goLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  String? _extractRole(dynamic meRes) {
    if (meRes is Map) {
      return (meRes['role'] ??
              (meRes['data'] is Map ? meRes['data']['role'] : null) ??
              (meRes['user'] is Map ? meRes['user']['role'] : null))
          ?.toString()
          .toLowerCase();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// =====================================================
/// LOGIN PAGE
/// =====================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameC = TextEditingController();
  final passC = TextEditingController();

  bool loading = false;
  String? err;

  Future<void> _doLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      err = null;
    });

    try {
      final authApi = ApiService(mode: ApiMode.http);
      final loginRes = await authApi.login(usernameC.text.trim(), passC.text);

      final token = (loginRes is Map)
          ? (loginRes['token'] ??
                  loginRes['access_token'] ??
                  (loginRes['data'] is Map ? loginRes['data']['token'] : null))
              ?.toString()
          : null;

      if (token == null || token.isEmpty) {
        throw Exception('Token tidak ditemukan');
      }

      await AuthStorage.saveToken(token);

      final api = ApiService(mode: ApiMode.dio, token: token);
      final me = await api.me();
      final role = _extractRole(me);

      if (role == null) throw Exception('Role tidak valid');

      // ✅ INIT FCM (idempotent)
      await _setupFcm(token);

      if (!mounted) return;

      if (role == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DriverHomePage(token: token)),
        );
      } else if (role == 'teknisi') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TechnicianHomePage(token: token)),
        );
      } else {
        throw Exception('Role tidak dikenali');
      }
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _extractRole(dynamic meRes) {
    if (meRes is Map) {
      return (meRes['role'] ??
              (meRes['data'] is Map ? meRes['data']['role'] : null) ??
              (meRes['user'] is Map ? meRes['user']['role'] : null))
          ?.toString()
          .toLowerCase();
    }
    return null;
  }

  @override
  void dispose() {
    usernameC.dispose();
    passC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Bengkel')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.car_repair, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'Masuk untuk Driver / Teknisi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: usernameC,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passC,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (err != null) ...[
                  Text(
                    err!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : _doLogin,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(loading ? 'Masuk...' : 'Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =====================================================
/// SETUP FCM (HYBRID CORE) - idempotent
/// =====================================================
bool _fcmReady = false;

Future<void> _setupFcm(String token) async {
  if (_fcmReady) return; // ✅ cegah double init
  _fcmReady = true;

  setAuthTokenForPush(token);

  final api = ApiService(mode: ApiMode.dio, token: token);

  await initFcm(
    onNewToken: (fcmToken) async {
      try {
        // ✅ sesuaikan dengan backend kamu
        await api.registerFcmToken(fcmToken);
      } catch (_) {}
    },

    // ✅ tap notif (background/terminated)
    onOpenFromNotification: (data) {
      _handleNotificationTap(data: data, token: token);
    },

    // ✅ notif masuk saat foreground
    onForegroundMessage: (msg) {
      final ctx = navKey.currentContext;
      if (ctx == null) return;

      final title = msg.notification?.title ?? 'Notifikasi';
      final body = msg.notification?.body ?? '';

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$title${body.isNotEmpty ? " — $body" : ""}')),
      );
    },
  );
}

/// =====================================================
/// ROUTING NOTIF (sesuai fitur baru)
/// =====================================================
void _handleNotificationTap({
  required Map<String, dynamic> data,
  required String token,
}) {
  final type = (data['type'] ?? '').toString();
  final role = (data['role'] ?? '').toString().toLowerCase();

  // report_id fallback (biar support booking/cost_estimate juga)
  final reportId = int.tryParse(
        (data['report_id'] ?? data['damage_report_id'] ?? data['id'] ?? '')
            .toString(),
      ) ??
      0;

  final ctx = navKey.currentContext;
  if (ctx == null) return;

  // ✅ DRIVER flows
  if (role == 'driver') {
    if (reportId > 0 &&
        (type == 'damage_report' ||
            type == 'booking' ||
            type == 'cost_estimate' ||
            type == 'review')) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => DriverReportDetailPage(token: token, reportId: reportId),
        ),
      );
      return;
    }

    if (type == 'service_reminder') {
      Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => DriverHomePage(token: token)),
      );
      return;
    }
  }

  // ✅ TEKNISI flows
  if (role == 'teknisi') {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => TechnicianHomePage(token: token)),
    );
    return;
  }

  // fallback aman
  if (reportId > 0) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => DriverReportDetailPage(token: token, reportId: reportId),
      ),
    );
  }
}
