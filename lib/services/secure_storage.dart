// lib/services/secure_storage.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const _keyToken = 'token';
  static const _keyUserId = 'userId'; // Esto parece que no se usa, pero es inocuo
  static const _keyPrivateKey = 'privateKey'; // Clave para la clave privada

  

  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _keyToken);
  }

  // --- MÉTODOS PARA CLAVE PRIVADA ---
  Future<void> savePrivateKey(String privateKey) async {
    print("SecureStorageService: Intentando guardar clave privada de longitud ${privateKey.length}");
    await _storage.write(key: _keyPrivateKey, value: privateKey);
    print("SecureStorageService: Clave privada guardada.");
  }

  Future<String?> getPrivateKey() async {
    final key = await _storage.read(key: _keyPrivateKey);
    if (key == null) {
      print("SecureStorageService: No se encontró clave privada.");
    } else {
      print("SecureStorageService: Clave privada cargada (longitud ${key.length}).");
    }
    return key;
  }

  Future<void> deletePrivateKey() async {
    print("SecureStorageService: Eliminando clave privada.");
    await _storage.delete(key: _keyPrivateKey);
  }
}