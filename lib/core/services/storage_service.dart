import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

/// Storage service for persisting user data locally
class StorageService {
  static const String _userKey = 'stoa_user';
  
  SharedPreferences? _prefs;
  
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  SharedPreferences get _preferences {
    if (_prefs == null) {
      throw StateError('StorageService not initialized. Call init() first.');
    }
    return _prefs!;
  }
  
  /// Check if a user exists
  Future<bool> hasUser() async {
    if (_prefs == null) await init();
    return _preferences.containsKey(_userKey);
  }
  
  /// Save user to local storage
  Future<void> saveUser(User user) async {
    if (_prefs == null) await init();
    final json = jsonEncode(user.toJson());
    await _preferences.setString(_userKey, json);
  }
  
  /// Load user from local storage
  Future<User?> loadUser() async {
    if (_prefs == null) await init();
    final json = _preferences.getString(_userKey);
    if (json == null) return null;
    
    try {
      return User.fromJson(jsonDecode(json));
    } catch (e) {
      return null;
    }
  }
  
  /// Clear user data (logout)
  Future<void> clearUser() async {
    if (_prefs == null) await init();
    await _preferences.remove(_userKey);
  }
  
  /// Clear all data
  Future<void> clearAll() async {
    if (_prefs == null) await init();
    await _preferences.clear();
  }
}

/// Provider for StorageService
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});
