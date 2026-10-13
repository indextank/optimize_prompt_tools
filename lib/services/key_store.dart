/// 密钥安全存储抽象。
///
/// 生产实现走平台安全存储：Windows DPAPI / Linux libsecret /
/// Android Keystore / Web WebCrypto（flutter_secure_storage 插件统一封装）。
/// 测试使用 [MemoryKeyStore]。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class KeyStore {
  Future<void> write(String keyRef, String apiKey);
  Future<String?> read(String keyRef);
  Future<void> delete(String keyRef);
}

/// 平台安全存储实现
class SecureKeyStore implements KeyStore {
  const SecureKeyStore([this._storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  )]);

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String keyRef, String apiKey) =>
      _storage.write(key: 'key_$keyRef', value: apiKey);

  @override
  Future<String?> read(String keyRef) => _storage.read(key: 'key_$keyRef');

  @override
  Future<void> delete(String keyRef) => _storage.delete(key: 'key_$keyRef');
}

/// 内存实现（测试与开发用）
class MemoryKeyStore implements KeyStore {
  final Map<String, String> _data = {};

  @override
  Future<void> write(String keyRef, String apiKey) async => _data[keyRef] = apiKey;

  @override
  Future<String?> read(String keyRef) async => _data[keyRef];

  @override
  Future<void> delete(String keyRef) async => _data.remove(keyRef);

  /// 测试辅助：当前存储条目数
  int get length => _data.length;
}
