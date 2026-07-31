import 'package:monero_extension/services/wallet_storage_service.dart';
import 'package:monero_extension/services/crypto_backend.dart';

class InMemoryStorageBackend implements StorageBackend {
  final Map<String, String> _data = {};

  @override
  String? get(String key) => _data[key];

  @override
  void set(String key, String value) => _data[key] = value;

  @override
  void remove(String key) => _data.remove(key);

  @override
  bool containsKey(String key) => _data.containsKey(key);

  @override
  List<String> get keys => _data.keys.toList();

  @override
  void atomicSet(String key, String value) {
    _data[WriteAheadKeys.tombstone(key)] = '1';
    _data[WriteAheadKeys.staging(key)] = value;
    _data[key] = value;
    _data.remove(WriteAheadKeys.tombstone(key));
    _data.remove(WriteAheadKeys.staging(key));
  }

  @override
  void maybeRecover(String key) {
    final tombstoneKey = WriteAheadKeys.tombstone(key);
    final stagingKey = WriteAheadKeys.staging(key);
    if (!_data.containsKey(tombstoneKey)) return;
    final staging = _data[stagingKey];
    if (staging != null) {
      _data[key] = staging;
    }
    _data.remove(tombstoneKey);
    _data.remove(stagingKey);
  }
}

class AsyncInMemoryStorageBackend implements AsyncStorageBackend {
  final Map<String, String> _data = {};

  @override
  Future<String?> get(String key) async => _data[key];

  @override
  Future<void> set(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);

  @override
  Future<List<String>> getKeys() async => _data.keys.toList();

  @override
  Future<void> atomicSet(String key, String value) async {
    _data[WriteAheadKeys.tombstone(key)] = '1';
    _data[WriteAheadKeys.staging(key)] = value;
    _data[key] = value;
    _data.remove(WriteAheadKeys.tombstone(key));
    _data.remove(WriteAheadKeys.staging(key));
  }

  @override
  Future<void> maybeRecover(String key) async {
    final tombstoneKey = WriteAheadKeys.tombstone(key);
    final stagingKey = WriteAheadKeys.staging(key);
    if (!_data.containsKey(tombstoneKey)) return;
    final staging = _data[stagingKey];
    if (staging != null) {
      _data[key] = staging;
    }
    _data.remove(tombstoneKey);
    _data.remove(stagingKey);
  }
}

/// No-op crypto backend: returns plaintext unchanged.
/// Simulates encryption/decryption without needing Rust signals.
class IdentityCryptoBackend implements CryptoBackend {
  @override
  Future<String?> encrypt(String password, String plaintext) async => plaintext;

  @override
  Future<String?> decrypt(String password, String ciphertext) async =>
      ciphertext;

  @override
  Future<({String keyHex, String saltHex})?> deriveKey(String password) async =>
      (keyHex: 'deadbeef' * 8, saltHex: 'cafebabe' * 4);

  @override
  Future<String?> encryptWithKey(
    String keyHex,
    String saltHex,
    String plaintext,
  ) async => plaintext;
}

/// Crypto backend that fails all operations.
class FailingCryptoBackend implements CryptoBackend {
  @override
  Future<String?> encrypt(String password, String plaintext) async => null;

  @override
  Future<String?> decrypt(String password, String ciphertext) async => null;

  @override
  Future<({String keyHex, String saltHex})?> deriveKey(String password) async =>
      null;

  @override
  Future<String?> encryptWithKey(
    String keyHex,
    String saltHex,
    String plaintext,
  ) async => null;
}
