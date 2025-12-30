import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _kToken = 'AUTH_TOKEN';
  static const _kUserId = 'AUTH_USER_ID';

  // ================= TOKEN =================
  static Future<void> saveToken(String token) async {
    final pref = await SharedPreferences.getInstance();
    await pref.setString(_kToken, token);
  }

  static Future<String?> getToken() async {
    final pref = await SharedPreferences.getInstance();
    final t = pref.getString(_kToken);
    if (t == null || t.trim().isEmpty) return null;
    return t.trim();
  }

  // ================= USER ID =================
  static Future<void> saveUserId(int userId) async {
    final pref = await SharedPreferences.getInstance();
    await pref.setInt(_kUserId, userId);
  }

  static Future<int?> getUserId() async {
    final pref = await SharedPreferences.getInstance();
    return pref.getInt(_kUserId);
  }

  // ================= CLEAR =================
  static Future<void> clear() async {
    final pref = await SharedPreferences.getInstance();
    await pref.remove(_kToken);
    await pref.remove(_kUserId);
  }

  static Future<void> clearAll() async {
    final pref = await SharedPreferences.getInstance();
    await pref.clear();
  }

  static Future<bool> hasToken() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  static Future<String> requireToken() async {
    final t = await getToken();
    if (t == null || t.isEmpty) {
      throw Exception('Token tidak ditemukan. Silakan login ulang.');
    }
    return t;
  }
}
