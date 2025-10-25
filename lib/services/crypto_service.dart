// lib/services/crypto_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
// import 'package:crypto/crypto.dart'; // No se usa directamente aquí si PBKDF2 está en pointycastle
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:fast_rsa/fast_rsa.dart';
import 'package:pointycastle/export.dart' as pointy; // Para PBKDF2

/// Mi servicio de utilidades criptográficas.
/// Encapsula la generación de claves, cifrado/descifrado AES y RSA,
/// y derivación de claves PBKDF2.
class CryptoService {
  // --- Constantes para PBKDF2 (Derivación de KEK desde contraseña) ---
  static const int _pbkdf2Iterations = 10000; // Iteraciones (más es más seguro pero más lento)
  static const int _pbkdf2SaltSize = 16; // 16 bytes / 128 bits para el salt
  static const int _pbkdf2KeyLength = 32; // 32 bytes / 256 bits para la clave AES-256

  // --- Constantes para AES GCM (Usado para cifrar/descifrar la clave privada RSA) ---
  static const int _aesGcmIvSize = 12; // 12 bytes / 96 bits - Tamaño estándar para GCM

  // --- Constantes para AES CBC (Usado para cifrar/descifrar mensajes de chat) ---
  static const int _aesCbcIvSize = 16; // 16 bytes / 128 bits - Tamaño estándar para CBC
  static const int _aesCbcKeySize = 32; // 32 bytes / 256 bits para AES-256

  /// Genera un par de claves RSA (Pública/Privada) de 2048 bits.
  /// Devuelve un mapa con las claves en formato PEM.
  Future<Map<String, String>> generateRSAKeyPair() async {
    print("CryptoService: Generando par de claves RSA 2048 bits...");
    final keyPair = await RSA.generate(2048);
    print("CryptoService: Claves RSA generadas.");
    return {
      'publicKey': keyPair.publicKey,
      'privateKey': keyPair.privateKey,
    };
  }

  /// Genera un salt aleatorio seguro para usar con PBKDF2.
  Uint8List generateSecureRandomSalt({int byteLength = _pbkdf2SaltSize}) {
    final secureRandom = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
    // print("CryptoService: Salt generado: ${base64Encode(salt)}"); // Log opcional
    return salt;
  }

  /// Genera un IV (Vector de Inicialización) aleatorio seguro para AES GCM.
  Uint8List generateSecureRandomGcmIV({int byteLength = _aesGcmIvSize}) {
    final secureRandom = Random.secure();
    final iv = Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
    // print("CryptoService: IV GCM generado: ${base64Encode(iv)}"); // Log opcional
    return iv;
  }

  /// Genera un IV (Vector de Inicialización) aleatorio seguro para AES CBC.
  Uint8List generateSecureRandomCbcIV({int byteLength = _aesCbcIvSize}) {
    final secureRandom = Random.secure();
    final iv = Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
     // print("CryptoService: IV CBC generado: ${base64Encode(iv)}"); // Log opcional
    return iv;
  }


  /// Deriva una clave desde una contraseña y un salt usando PBKDF2-HMAC-SHA256.
  /// Usado para generar la KEK (Key Encryption Key).
  /// Devuelve la clave derivada como Uint8List (bytes crudos).
  Uint8List deriveKeyFromPasswordPBKDF2(String password, Uint8List salt) {
    print("CryptoService: Derivando clave con PBKDF2 (SHA256, $_pbkdf2Iterations iteraciones)...");
    final pbkdf2 = pointy.PBKDF2KeyDerivator(pointy.HMac(pointy.SHA256Digest(), 64))
      ..init(pointy.Pbkdf2Parameters(salt, _pbkdf2Iterations, _pbkdf2KeyLength));

    final derivedKey = pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
    print("CryptoService: Clave PBKDF2 derivada (longitud ${derivedKey.length}).");
    return derivedKey;
  }

  /// **Cifra texto plano usando AES-GCM.**
  /// Usado en `AuthService` para cifrar la clave privada RSA antes de enviarla al backend.
  /// Necesita la KEK (bytes) y devuelve un mapa con 'ciphertext' (Base64) e 'iv' (Base64).
  Map<String, String> encryptAES_GCM(String plainText, Uint8List keyBytes) {
    print("CryptoService: Cifrando con AES-GCM...");
    final ivBytes = generateSecureRandomGcmIV(); // IV nuevo para cada cifrado GCM
    final key = encrypt.Key(keyBytes); // Clave AES (KEK)
    // Usamos el modo GCM
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    // Cifrar
    final encrypted = encrypter.encrypt(plainText, iv: encrypt.IV(ivBytes));

    print("CryptoService: Cifrado AES-GCM completado.");
    // Devolver texto cifrado y el IV usado, ambos en Base64
    return {
      'ciphertext': encrypted.base64,
      'iv': base64Encode(ivBytes),
    };
  }

  /// **Descifra texto cifrado (Base64) usando AES-GCM.**
  /// Usado en `AuthService` para descifrar la clave privada RSA recibida del backend al hacer login.
  /// Necesita la KEK (bytes) y el IV (Base64) que se usó para cifrar.
  /// Devuelve el texto plano (la clave privada RSA).
  String decryptAES_GCM(String encryptedBase64, Uint8List keyBytes, String base64IV) {
    print("CryptoService: Descifrando con AES-GCM...");
    final key = encrypt.Key(keyBytes); // Clave AES (KEK)
    final iv = encrypt.IV(base64Decode(base64IV)); // Decodificamos el IV
    // Usamos el modo GCM
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    // Crear objeto Encrypted desde Base64
    final encryptedData = encrypt.Encrypted.fromBase64(encryptedBase64);
    // Descifrar
    final decrypted = encrypter.decrypt(encryptedData, iv: iv);
    print("CryptoService: Descifrado AES-GCM completado.");
    return decrypted;
  }

  /// **Genera una nueva clave AES y un IV para usar con CBC.**
  /// Usado en `SocketService` para cifrar cada mensaje de chat.
  /// Devuelve un mapa con 'key' (Base64) e 'iv' (Base64).
  Map<String, String> generateAESKeyAndIV_CBC() {
    print("CryptoService: Generando nueva clave AES-256 e IV para CBC...");
    final key = encrypt.Key.fromSecureRandom(_aesCbcKeySize); // Clave de 32 bytes (256 bits)
    final iv = encrypt.IV.fromSecureRandom(_aesCbcIvSize);   // IV de 16 bytes (128 bits) para CBC
    print("CryptoService: Clave e IV para CBC generados.");
    return {
      'key': key.base64, // Devuelve en Base64 para fácil manejo
      'iv': iv.base64,
    };
  }

   /// **Cifra texto plano usando AES-CBC.**
   /// Usado en `SocketService` para cifrar el mensaje de chat antes de enviarlo.
   /// Necesita la clave (Base64) y el IV (Base64). Devuelve el cifrado en Base64.
   String encryptAES_CBC(String plainText, String base64Key, String base64IV) {
    // print("CryptoService: Cifrando con AES-CBC..."); // Log opcional (puede ser muy verboso)
    final key = encrypt.Key.fromBase64(base64Key);
    final iv = encrypt.IV.fromBase64(base64IV);
    // Usamos el modo CBC (Cipher Block Chaining)
    // PKCS7 padding es el default y está bien.
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    // print("CryptoService: Cifrado AES-CBC completado.");
    return encrypted.base64;
  }

  /// **Descifra texto cifrado (Base64) usando AES-CBC.**
  /// Usado en `ChatScreen` para descifrar los mensajes recibidos (del historial o WebSocket).
  /// Necesita la clave (Base64) y el IV (Base64) usados para cifrar.
  /// Devuelve el texto plano.
  String decryptAES_CBC(String encryptedBase64, String base64Key, String base64IV) {
     // print("CryptoService: Descifrando con AES-CBC..."); // Log opcional
    final key = encrypt.Key.fromBase64(base64Key);
    final iv = encrypt.IV.fromBase64(base64IV);
    // Usamos el modo CBC
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encryptedData = encrypt.Encrypted.fromBase64(encryptedBase64);
    final decrypted = encrypter.decrypt(encryptedData, iv: iv);
     // print("CryptoService: Descifrado AES-CBC completado.");
    return decrypted;
  }

  /// **Cifra datos (normalmente la clave AES+IV combinada) usando una clave pública RSA (PKCS1v15).**
  /// Usado en `SocketService` para cifrar la clave AES para cada destinatario.
  /// `publicKeyPem` es la clave pública del destinatario.
  /// Devuelve el resultado cifrado en Base64.
  Future<String> encryptRSA(String dataToEncrypt, String publicKeyPem) async {
    // print("CryptoService: Cifrando con RSA PKCS1v15..."); // Log opcional
    final result = await RSA.encryptPKCS1v15(dataToEncrypt, publicKeyPem);
    // print("CryptoService: Cifrado RSA completado.");
    return result;
  }

  /// **Descifra datos (Base64) usando una clave privada RSA (PKCS1v15).**
  /// Usado en `ChatScreen` para descifrar la clave AES+IV combinada que viene en los mensajes.
  /// `privateKeyPem` es NUESTRA clave privada.
  /// Devuelve los datos originales (la clave AES+IV combinada).
  Future<String> decryptRSA(String encryptedBase64, String privateKeyPem) async {
    // print("CryptoService: Descifrando con RSA PKCS1v15..."); // Log opcional
    final result = await RSA.decryptPKCS1v15(encryptedBase64, privateKeyPem);
    // print("CryptoService: Descifrado RSA completado.");
    return result;
  }

  /// Combina una clave AES (Base64) y un IV (Base64) en un solo string,
  /// separados por ':'. Esto es lo que se cifra con RSA.
  String combineKeyIV(String base64Key, String base64IV) {
    return '$base64Key:$base64IV';
  }

  /// Separa el string combinado (clave:IV) de nuevo en un mapa.
  /// Lanza FormatException si el formato no es el esperado.
  Map<String, String> splitKeyIV(String combined) {
    final parts = combined.split(':');
    if (parts.length == 2) {
      return {'key': parts[0], 'iv': parts[1]};
    } else {
      print("CryptoService Error: El string combinado '$combined' no tiene el formato esperado 'key:iv'.");
      throw const FormatException("El string combinado de clave/IV no tiene el formato esperado.");
    }
  }
} // Fin CryptoService