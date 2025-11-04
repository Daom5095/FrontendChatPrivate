// lib/services/secure_storage.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Mi servicio de almacenamiento seguro.
///
/// Es una clase wrapper simple alrededor de `FlutterSecureStorage` para
/// centralizar las claves (keys) que uso en la app y facilitar
/// el guardado, lectura y borrado de datos sensibles.
class SecureStorageService {
  /// Instancia del plugin de almacenamiento seguro.
  final _storage = const FlutterSecureStorage();

  // Defino las claves (keys) que usaré en el storage para evitar errores de tipeo.
  static const _keyToken = 'token';
  // static const _keyUserId = 'userId'; // No lo estoy usando, pero podría ser útil
  static const _keyPrivateKey = 'privateKey'; // Clave para la clave privada RSA

  
  /// Guarda el token JWT en el almacenamiento seguro.
  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  /// Lee el token JWT del almacenamiento seguro.
  /// Devuelve `null` si no se encuentra.
  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  /// Elimina el token JWT del almacenamiento seguro.
  Future<void> deleteToken() async {
    await _storage.delete(key: _keyToken);
  }

  // --- MÉTODOS PARA CLAVE PRIVADA ---

  /// Guarda la clave privada RSA (en formato PEM) en el almacenamiento seguro.
  Future<void> savePrivateKey(String privateKey) async {
    print("SecureStorageService: Intentando guardar clave privada de longitud ${privateKey.length}");
    await _storage.write(key: _keyPrivateKey, value: privateKey);
    print("SecureStorageService: Clave privada guardada.");
  }

  /// Lee la clave privada RSA (en formato PEM) del almacenamiento seguro.
  /// Devuelve `null` si no se encuentra.
  Future<String?> getPrivateKey() async {
    final key = await _storage.read(key: _keyPrivateKey);
    if (key == null) {
      print("SecureStorageService: No se encontró clave privada.");
    } else {
      print("SecureStorageService: Clave privada cargada (longitud ${key.length}).");
    }
    return key;
  }

  /// Elimina la clave privada RSA del almacenamiento seguro.
  Future<void> deletePrivateKey() async {
    print("SecureStorageService: Eliminando clave privada.");
    await _storage.delete(key: _keyPrivateKey);
  }
}