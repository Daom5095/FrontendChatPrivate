import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = kIsWeb ? null : const FlutterSecureStorage();
  final Map<String, String> _webStorage = {};

  static const _tokenKey = 'jwt_token';
  static const _privateKey = 'private_key';

  Future<void> saveToken(String token) async {
    if (kIsWeb) {
      _webStorage[_tokenKey] = token;
    } else {
      await _storage?.write(key: _tokenKey, value: token);
    }
  }

  Future<String?> getToken() async {
    if (kIsWeb) {
      return _webStorage[_tokenKey];
    } else {
      return await _storage?.read(key: _tokenKey);
    }
  }

  Future<void> savePrivateKey(String privateKey) async {
    if (kIsWeb) {
      _webStorage[_privateKey] = privateKey;
    } else {
      await _storage?.write(key: _privateKey, value: privateKey);
    }
  }

  Future<String?> getPrivateKey() async {
    if (kIsWeb) {
      return _webStorage[_privateKey];
    } else {
      return await _storage?.read(key: _privateKey);
    }
  }

  Future<void> deleteAll() async {
    if (kIsWeb) {
      _webStorage.clear();
    } else {
      await _storage?.deleteAll();
    }
  }
}