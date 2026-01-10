/// App-wide constants
class AppConstants {
  AppConstants._();
  
  // Network
  static const int discoveryPort = 47842;  // STOA on phone keypad
  static const int transferPort = 47843;
  static const String serviceType = '_stoa._tcp';
  
  // Timeouts
  static const Duration peerTimeout = Duration(seconds: 15);
  static const Duration broadcastInterval = Duration(seconds: 3);
  
  // Limits
  static const int maxUsernameLength = 32;
  static const int minUsernameLength = 2;
  static const int maxGroupNameLength = 50;
  static const int maxMessageLength = 4000;
  
  // File transfer
  static const int chunkSize = 64 * 1024; // 64KB chunks
  static const int maxFileSize = 2 * 1024 * 1024 * 1024; // 2GB
}
