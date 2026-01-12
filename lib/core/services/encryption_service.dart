import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service for handling secure P2P encryption
class EncryptionService {
  final _algorithm = X25519();
  final _cipher = AesGcm.with256bits();
  final _hash = Sha256();
  
  /// Generate a new ephemeral key pair for this session
  Future<SimpleKeyPair> generateKeyPair() async {
    return await _algorithm.newKeyPair();
  }
  
  /// Extract public key bytes from a key pair
  Future<List<int>> getPublicKeyBytes(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return publicKey.bytes;
  }
  
  /// Derive a shared secret key using our private key and peer's public key
  /// Returns a 32-byte shared secret suitable for AES-256
  Future<SecretKey> deriveSharedSecret({
    required SimpleKeyPair ownKeyPair,
    required List<int> peerPublicKeyBytes,
  }) async {
    final peerPublicKey = SimplePublicKey(
      peerPublicKeyBytes,
      type: KeyPairType.x25519,
    );
    
    // Perform ECDH to get raw shared secret
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: ownKeyPair,
      remotePublicKey: peerPublicKey,
    );
    
    // Derive a session key using HKDF-SHA256 (or just simple hashing for now)
    // For simplicity in this phase, we'll hash the raw ECDH output to get exactly 32 bytes
    final rawSecretBytes = await sharedSecret.extractBytes();
    final hashedBytes = await _hash.hash(rawSecretBytes);
    
    return SecretKey(hashedBytes.bytes);
  }
  
  /// Encrypt data using the shared secret
  /// Returns a map with 'iv' and 'cipherText'
  Future<Map<String, dynamic>> encrypt(
    dynamic data, 
    SecretKey secretKey,
  ) async {
    // Determine input bytes
    List<int> plainText;
    if (data is String) {
      plainText = utf8.encode(data);
    } else if (data is List<int>) {
      plainText = data;
    } else {
      plainText = utf8.encode(jsonEncode(data));
    }
    
    // Encrypt
    final secretBox = await _cipher.encrypt(
      plainText,
      secretKey: secretKey,
    );
    
    return {
      'iv': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }
  
  /// Decrypt data using the shared secret
  /// Returns the raw decrypted bytes
  Future<List<int>> decrypt(
    Map<String, dynamic> encryptedData, 
    SecretKey secretKey,
  ) async {
    final iv = base64Decode(encryptedData['iv']);
    final cipherText = base64Decode(encryptedData['cipherText']);
    final mac = base64Decode(encryptedData['mac']);
    
    final secretBox = SecretBox(
      cipherText,
      nonce: iv,
      mac: Mac(mac),
    );
    
    return await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );
  }
  
  /// Encrypt raw bytes - Turbo Mode (returns combined nonce+ciphertext+mac)
  Future<List<int>> encryptBytes(List<int> plainBytes, SecretKey secretKey) async {
    final secretBox = await _cipher.encrypt(
      plainBytes,
      secretKey: secretKey,
    );
    
    // Return: [12-byte nonce][ciphertext][16-byte mac]
    return [...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
  }
  
  /// Decrypt raw bytes - Turbo Mode (expects combined nonce+ciphertext+mac)
  Future<List<int>> decryptBytes(List<int> encryptedBytes, SecretKey secretKey) async {
    // Parse: [12-byte nonce][ciphertext][16-byte mac]
    final nonce = encryptedBytes.sublist(0, 12);
    final mac = encryptedBytes.sublist(encryptedBytes.length - 16);
    final cipherText = encryptedBytes.sublist(12, encryptedBytes.length - 16);
    
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(mac),
    );
    
    return await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );
  }
}

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});
