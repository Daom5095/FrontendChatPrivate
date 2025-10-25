// lib/services/crypto_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart'; // Para sha256
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:fast_rsa/fast_rsa.dart';
import 'package:pointycastle/export.dart' as pointy; // Para PBKDF2

class CryptoService {
  // --- Constantes para PBKDF2 ---
  // ¡Estos valores deben ser iguales en el backend si valida la KEK!
  // En producción, usa un número mayor de iteraciones (ej. 100000 o más)
  static const int _pbkdf2Iterations = 10000;
  static const int _pbkdf2SaltSize = 16; // 16 bytes / 128 bits
  static const int _pbkdf2KeyLength = 32; // 32 bytes / 256 bits para AES-256

  // --- Constantes para AES GCM ---
  // GCM es generalmente preferido a CBC si está disponible. Requiere IV de 12 bytes.
  static const int _aesGcmIvSize = 12; // 12 bytes / 96 bits para GCM

  /// Genera un par de claves RSA de 2048 bits.
  Future<Map<String, String>> generateRSAKeyPair() async {
    final keyPair = await RSA.generate(2048);
    return {
      'publicKey': keyPair.publicKey,
      'privateKey': keyPair.privateKey,
    };
  }

  /// Genera un salt aleatorio seguro.
  Uint8List generateSecureRandomSalt({int byteLength = _pbkdf2SaltSize}) {
    final secureRandom = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
  }

    /// Genera un IV aleatorio seguro para AES GCM.
  Uint8List generateSecureRandomIV({int byteLength = _aesGcmIvSize}) {
    final secureRandom = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
  }

  /// Deriva una clave desde una contraseña y un salt usando PBKDF2-HMAC-SHA256.
  /// Devuelve la clave derivada como Uint8List.
  Uint8List deriveKeyFromPasswordPBKDF2(String password, Uint8List salt) {
    final pbkdf2 = pointy.PBKDF2KeyDerivator(pointy.HMac(pointy.SHA256Digest(), 64))
      ..init(pointy.Pbkdf2Parameters(salt, _pbkdf2Iterations, _pbkdf2KeyLength));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Cifra texto plano usando AES-GCM.
  /// Necesita la clave (Uint8List) y devuelve un mapa con 'ciphertext' (Base64) e 'iv' (Base64).
  /// GCM incluye autenticación, lo que lo hace más seguro que CBC.
  Map<String, String> encryptAES_GCM(String plainText, Uint8List keyBytes) {
    final iv = generateSecureRandomIV(); // IV nuevo para cada cifrado GCM
    final key = encrypt.Key(keyBytes);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    final encrypted = encrypter.encrypt(plainText, iv: encrypt.IV(iv));

    return {
      'ciphertext': encrypted.base64,
      'iv': base64Encode(iv), // Codificamos el IV usado
    };
  }

  /// Descifra texto cifrado (Base64) usando AES-GCM.
  /// Necesita la clave (Uint8List) y el IV (Base64) usado para cifrar.
  /// Devuelve el texto plano.
  String decryptAES_GCM(String encryptedBase64, Uint8List keyBytes, String base64IV) {
    final key = encrypt.Key(keyBytes);
    final iv = encrypt.IV(base64Decode(base64IV)); // Decodificamos el IV
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    final encryptedData = encrypt.Encrypted.fromBase64(encryptedBase64);
    final decrypted = encrypter.decrypt(encryptedData, iv: iv);
    return decrypted;
  }

  // --- Cifrado/Descifrado AES simple para mensajes (como antes, pero usando GCM es opcional) ---
   Map<String, String> generateAESKeyAndIV_CBC() {
    final key = encrypt.Key.fromSecureRandom(32);
    final iv = encrypt.IV.fromSecureRandom(16); // CBC usa 16 bytes
    return {
      'key': key.base64,
      'iv': iv.base64,
    };
  }
   String encryptAES_CBC(String plainText, String base64Key, String base64IV) {
    final key = encrypt.Key.fromBase64(base64Key);
    final iv = encrypt.IV.fromBase64(base64IV);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc)); // CBC
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  String decryptAES_CBC(String encryptedBase64, String base64Key, String base64IV) {
    final key = encrypt.Key.fromBase64(base64Key);
    final iv = encrypt.IV.fromBase64(base64IV);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc)); // CBC
    final encryptedData = encrypt.Encrypted.fromBase64(encryptedBase64);
    final decrypted = encrypter.decrypt(encryptedData, iv: iv);
    return decrypted;
  }

  // --- Funciones RSA (sin cambios) ---
  Future<String> encryptRSA(String dataToEncrypt, String publicKeyPem) async {
    return await RSA.encryptPKCS1v15(dataToEncrypt, publicKeyPem);
  }

  Future<String> decryptRSA(String encryptedBase64, String privateKeyPem) async {
    return await RSA.decryptPKCS1v15(encryptedBase64, privateKeyPem);
  }

  String combineKeyIV(String base64Key, String base64IV) {
    return '$base64Key:$base64IV';
  }

  Map<String, String> splitKeyIV(String combined) {
    final parts = combined.split(':');
    if (parts.length == 2) {
      return {'key': parts[0], 'iv': parts[1]};
    } else {
      throw const FormatException("El string combinado de clave/IV no tiene el formato esperado.");
    }
  }
}