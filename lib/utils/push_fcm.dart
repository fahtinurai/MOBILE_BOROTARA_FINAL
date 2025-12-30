// utils/push_fcm.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart'; 

/// NavigatorKey biar notif bisa navigate tanpa context halaman
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// Simpan token auth Laravel aktif (di-set saat login/boot)
String? _authToken;

/// Set token auth Laravel supaya notif bisa buka halaman detail pakai token itu
void setAuthTokenForPush(String? token) {
  _authToken = token;
}

// =====================================================
// LOCAL CACHE: supaya register token ke Laravel gak diulang-ulang
// =====================================================
const _kLastFcmToken = 'LAST_FCM_TOKEN';

Future<String?> _getLastFcmToken() async {
  final pref = await SharedPreferences.getInstance();
  final t = pref.getString(_kLastFcmToken);
  if (t == null || t.trim().isEmpty) return null;
  return t.trim();
}

Future<void> _setLastFcmToken(String token) async {
  final pref = await SharedPreferences.getInstance();
  await pref.setString(_kLastFcmToken, token.trim());
}

// =====================================================
// Background handler (WAJIB top-level)
// =====================================================
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ✅ wajib init dengan options agar stabil di background/terminated
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Di background cukup init.
  // Jangan akses UI / Navigator di sini.
}

// =====================================================
// Init FCM: permission + token + listeners
// =====================================================
Future<void> initFcm({
  required Future<void> Function(String fcmToken) onNewToken,
  required void Function(Map<String, dynamic> data) onOpenFromNotification,
  void Function(RemoteMessage msg)? onForegroundMessage,
}) async {
  // ✅ Web biasanya berbeda (FCM web perlu setup VAPID dll)
  if (kIsWeb) {
    debugPrint('⚠️ initFcm: Web detected. (FCM web butuh setup khusus).');
    return;
  }

  final fm = FirebaseMessaging.instance;

  // ✅ iOS: agar notif tampil saat foreground
  await fm.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // =============================
  // 1) Permission
  // =============================
  final perm = await fm.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  debugPrint('🔐 FCM Permission: ${perm.authorizationStatus}');

  // Android: (optional) channel ditangani oleh plugin/OS,
  // untuk custom channel biasanya pakai flutter_local_notifications.
  if (!Platform.isIOS) {
    // nothing (aman)
  }

  // =============================
  // 2) Token pertama (initial)
  // =============================
  String? t;
  try {
    t = await fm.getToken();
  } catch (e) {
    debugPrint('❌ getToken error: $e');
  }

  debugPrint('🔥 FCM TOKEN (initial): $t');

  if (t != null && t.trim().isNotEmpty) {
    final token = t.trim();
    final last = await _getLastFcmToken();

    // Kirim ke Laravel hanya kalau token baru / berubah
    if (last != token) {
      debugPrint('✅ FCM token changed/new -> send to Laravel');
      try {
        await onNewToken(token);
        await _setLastFcmToken(token);
        debugPrint('✅ FCM token saved to cache');
      } catch (e) {
        debugPrint('❌ failed sending initial token: $e');
      }
    } else {
      debugPrint('⏭️ FCM token same as cached -> skip sending');
    }
  } else {
    debugPrint(
      '⚠️ FCM token null/empty. Pastikan:\n'
      '- google-services.json benar\n'
      '- Firebase.initializeApp(options: DefaultFirebaseOptions...) dipakai\n'
      '- device ada internet\n'
      '- bukan emulator yang dibatasi\n',
    );
  }

  // =============================
  // 3) Token refresh
  // =============================
  fm.onTokenRefresh.listen((t2) async {
    final token2 = t2.trim();
    debugPrint('♻️ FCM TOKEN (refresh): $token2');

    if (token2.isEmpty) return;

    final last = await _getLastFcmToken();
    if (last == token2) {
      debugPrint('⏭️ refresh token sama -> skip');
      return;
    }

    try {
      await onNewToken(token2);
      await _setLastFcmToken(token2);
      debugPrint('✅ refresh token sent & saved');
    } catch (e) {
      debugPrint('❌ failed sending refresh token: $e');
    }
  });

  // =============================
  // 4) Foreground message
  // =============================
  FirebaseMessaging.onMessage.listen((msg) {
    onForegroundMessage?.call(msg);
  });

  // =============================
  // 5) App dibuka dari notif (background -> tap)
  // =============================
  FirebaseMessaging.onMessageOpenedApp.listen((msg) {
    final data = msg.data;
    if (data.isNotEmpty) onOpenFromNotification(_normalizeData(data));
  });

  // =============================
  // 6) App start dari terminated via tap notif
  // =============================
  final initial = await fm.getInitialMessage();
  if (initial != null && initial.data.isNotEmpty) {
    onOpenFromNotification(_normalizeData(initial.data));
  }
}

// =====================================================
// Helper: normalize Map<String, dynamic> dari FCM
// (kadang value bukan string, amankan)
// =====================================================
Map<String, dynamic> _normalizeData(Map<String, dynamic> raw) {
  final out = <String, dynamic>{};
  raw.forEach((k, v) => out[k.toString()] = v);
  return out;
}
