import 'package:stoa/core/utils/logger.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
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
  
  /// Get the base Stoa documents path (uses external storage on Android)
  static Future<String> getStoaDocumentsPath() async {
    if (Platform.isAndroid) {
      // Use external storage Documents folder on Android
      return '/storage/emulated/0/Documents/Stoa';
    } else {
      // Use app documents on other platforms
      final docsDir = await getApplicationDocumentsDirectory();
      return '${docsDir.path}/Stoa';
    }
  }
  
  /// Get the downloads path (unified for all downloads)
  /// Structure: <StoaBase>/Downloads/<category>/<files>
  /// Categories: DMs, Groups, SharedSpaces
  static Future<String> getStoaDownloadsPath([String? category]) async {
    final basePath = await getStoaDocumentsPath();
    if (category != null) {
      return '$basePath/Downloads/$category';
    }
    return '$basePath/Downloads';
  }
  /// Open the Stoa downloads folder
  Future<void> openDownloadsFolder() async {
    String? path;
    if (Platform.isAndroid) {
      path = '/storage/emulated/0/Download/Stoa';
    } else {
      final downloadDir = await getDownloadsDirectory();
      path = '${downloadDir?.path}/Stoa';
    }
    
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    
    if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else {
      // Android/iOS: Try open_filex or fallback
      // open_filex might not support directories, but we'll try
      try {
        await OpenFilex.open(path);
      } catch (e) {
        appLogger.i('Could not open directory: $e');
      }
    }
  }
}

/// Provider for StorageService
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

