// lib/services/crypto_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:fast_rsa/fast_rsa.dart';
import 'package:pointycastle/export.dart' as pointy; // Para PBKDF2

/// Mi servicio de utilidades criptográficas.
///
/// Esta clase es mi "caja de herramientas" para toda la criptografía.
/// Encapsula la generación de claves, cifrado/descifrado AES y RSA,
/// y derivación de claves PBKDF2. No guarda ningún estado.
class CryptoService {
  // --- Constantes para PBKDF2 (Derivación de KEK desde contraseña) ---
  /// Iteraciones para PBKDF2. Más es más seguro pero más lento.
  static const int _pbkdf2Iterations = 10000;
  /// 16 bytes / 128 bits para el salt de PBKDF2.
  static const int _pbkdf2SaltSize = 16;
  /// 32 bytes / 256 bits para la clave de salida (AES-256).
  static const int _pbkdf2KeyLength = 32;

  // --- Constantes para AES GCM (Usado para cifrar/descifrar la clave privada RSA) ---
  /// 12 bytes / 96 bits - Tamaño estándar de IV para GCM.
  static const int _aesGcmIvSize = 12;

  // --- Constantes para AES CBC (Usado para cifrar/descifrar mensajes de chat) ---
  /// 16 bytes / 128 bits - Tamaño estándar de IV para CBC.
  static const int _aesCbcIvSize = 16;
  /// 32 bytes / 256 bits para la clave (AES-256).
  static const int _aesCbcKeySize = 32;

  /// Genera un par de claves RSA (Pública/Privada) de 2048 bits.
  ///
  /// Se usa durante el **registro** de un nuevo usuario.
  /// Devuelve un mapa con las claves en formato PEM.
  Future<Map<String, String>> generateRSAKeyPair() async {
    print("CryptoService: Generando par de claves RSA 2048 bits...");
    // Uso fast_rsa para la generación de claves.
    final keyPair = await RSA.generate(2048);
    print("CryptoService: Claves RSA generadas.");
    return {
      'publicKey': keyPair.publicKey,
      'privateKey': keyPair.privateKey,
    };
  }

  /// Genera un salt aleatorio seguro para usar con PBKDF2.
  ///
  /// Se usa en el **registro** para crear el `kekSalt`.
  Uint8List generateSecureRandomSalt({int byteLength = _pbkdf2SaltSize}) {
    final secureRandom = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
    // print("CryptoService: Salt generado: ${base64Encode(salt)}"); // Log opcional
    return salt;
  }

  /// Genera un IV (Vector de Inicialización) aleatorio seguro para AES GCM.
  ///
  /// Se usa en el **registro** para cifrar la clave privada con la KEK.
  Uint8List generateSecureRandomGcmIV({int byteLength = _aesGcmIvSize}) {
    final secureRandom = Random.secure();
    final iv = Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
    // print("CryptoService: IV GCM generado: ${base64Encode(iv)}"); // Log opcional
    return iv;
  }

  /// Genera un IV (Vector de Inicialización) aleatorio seguro para AES CBC.
  ///
  /// Se usa al **enviar un mensaje de chat** (cada mensaje tiene un IV nuevo).
  Uint8List generateSecureRandomCbcIV({int byteLength = _aesCbcIvSize}) {
    final secureRandom = Random.secure();
    final iv = Uint8List.fromList(
        List<int>.generate(byteLength, (i) => secureRandom.nextInt(256)));
     // print("CryptoService: IV CBC generado: ${base64Encode(iv)}"); // Log opcional
    return iv;
  }


  /// Deriva una clave desde una contraseña y un salt usando PBKDF2-HMAC-SHA256.
  ///
  /// Se usa para generar la KEK (Key Encryption Key) tanto en el
  /// **registro** (para cifrar) como en el **login** (para descifrar).
  ///
  /// Devuelve la clave derivada como `Uint8List` (bytes crudos).
  Uint8List deriveKeyFromPasswordPBKDF2(String password, Uint8List salt) {
    print("CryptoService: Derivando clave con PBKDF2 (SHA256, $_pbkdf2Iterations iteraciones)...");
    
    // Configuro el derivador PBKDF2 usando PointyCastle
    final pbkdf2 = pointy.PBKDF2KeyDerivator(pointy.HMac(pointy.SHA256Digest(), 64))
      ..init(pointy.Pbkdf2Parameters(salt, _pbkdf2Iterations, _pbkdf2KeyLength));

    // Proceso la contraseña (convertida a bytes)
    final derivedKey = pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
    print("CryptoService: Clave PBKDF2 derivada (longitud ${derivedKey.length}).");
    return derivedKey;
  }

  /// **Cifra texto plano usando AES-GCM.**
  ///
  /// Se usa en `AuthService` durante el **registro** para cifrar la
  /// clave privada RSA antes de enviarla al backend.
  ///
  /// GCM es un modo autenticado (AEAD) que es bueno para esto.
  ///
  /// Necesita la KEK (bytes) y devuelve un mapa con 'ciphertext' (Base64) e 'iv' (Base64).
  Map<String, String> encryptAES_GCM(String plainText, Uint8List keyBytes) {
    print("CryptoService: Cifrando con AES-GCM...");
    final ivBytes = generateSecureRandomGcmIV(); // IV nuevo para cada cifrado GCM
    final key = encrypt.Key(keyBytes); // Clave AES (KEK)
    
    // Uso el modo GCM
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    // Cifrar
    final encrypted = encrypter.encrypt(plainText, iv: encrypt.IV(ivBytes));

    print("CryptoService: Cifrado AES-GCM completado.");
    // Devolver texto cifrado y el IV usado, ambos en Base64
    return {
      'ciphertext': encrypted.base64, // El texto cifrado
      'iv': base64Encode(ivBytes), // El IV que se usó
    };
  }

  /// **Descifra texto cifrado (Base64) usando AES-GCM.**
  ///
  /// Usado en `AuthService` durante el **login** para descifrar la clave privada RSA
  /// (que recibimos del backend) usando la KEK que re-derivamos de la contraseña.
  ///
  /// Necesita la KEK (bytes) y el IV (Base64) que se usó para cifrar.
  /// Devuelve el texto plano (la clave privada RSA).
  String decryptAES_GCM(String encryptedBase64, Uint8List keyBytes, String base64IV) {
    print("CryptoService: Descifrando con AES-GCM...");
    final key = encrypt.Key(keyBytes); // Clave AES (KEK)
    final iv = encrypt.IV(base64Decode(base64IV)); // Decodificamos el IV
    
    // Uso el modo GCM
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    // Crear objeto Encrypted desde Base64
    final encryptedData = encrypt.Encrypted.fromBase64(encryptedBase64);
    
    // Descifrar
    final decrypted = encrypter.decrypt(encryptedData, iv: iv);
    print("CryptoService: Descifrado AES-GCM completado.");
    return decrypted;
  }

  /// **Genera una nueva clave AES y un IV para usar con CBC.**
  ///
  /// Usado en `SocketService` cada vez que se **envía un mensaje de chat**.
  /// Cada mensaje usa una clave simétrica única.
  ///
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
   ///
   /// Usado en `SocketService` para cifrar el **mensaje de chat** antes de enviarlo.
   /// Uso CBC aquí por simplicidad y compatibilidad.
   ///
   /// Necesita la clave (Base64) y el IV (Base64). Devuelve el cifrado en Base64.
   String encryptAES_CBC(String plainText, String base64Key, String base64IV) {
    // print("CryptoService: Cifrando con AES-CBC..."); // Log opcional (muy verboso)
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
  ///
  /// Usado en `ChatScreen` para descifrar los **mensajes de chat recibidos**
  /// (tanto del historial como del WebSocket).
  ///
  /// Necesita la clave (Base64) y el IV (Base64) usados para cifrar ese mensaje.
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

  /// **Cifra datos (la clave AES+IV combinada) usando una clave pública RSA (PKCS1v15).**
  ///
  /// Usado en `SocketService` para cifrar la clave AES para cada destinatario del mensaje.
  /// `publicKeyPem` es la clave pública del *destinatario*.
  ///
  /// Devuelve el resultado cifrado en Base64.
  Future<String> encryptRSA(String dataToEncrypt, String publicKeyPem) async {
    // print("CryptoService: Cifrando con RSA PKCS1v15..."); // Log opcional
    // Uso fast_rsa para el cifrado asimétrico.
    final result = await RSA.encryptPKCS1v15(dataToEncrypt, publicKeyPem);
    // print("CryptoService: Cifrado RSA completado.");
    return result;
  }

  /// **Descifra datos (Base64) usando una clave privada RSA (PKCS1v15).**
  ///
  /// Usado en `ChatScreen` para descifrar la clave AES+IV combinada que
  /// viene en cada mensaje (del historial o WebSocket).
  /// `privateKeyPem` es **NUESTRA** clave privada de la sesión.
  ///
  /// Devuelve los datos originales (el string 'claveAES:IV' combinado).
  Future<String> decryptRSA(String encryptedBase64, String privateKeyPem) async {
    // print("CryptoService: Descifrando con RSA PKCS1v15..."); // Log opcional
    // Uso fast_rsa para el descifrado asimétrico.
    final result = await RSA.decryptPKCS1v15(encryptedBase64, privateKeyPem);
    // print("CryptoService: Descifrado RSA completado.");
    return result;
  }

  /// Combina una clave AES (Base64) y un IV (Base64) en un solo string,
  /// separados por ':'.
  ///
  /// Esto es lo que se cifra con RSA, ya que RSA solo puede cifrar
  /// un bloque de datos, y necesito enviar tanto la clave como el IV.
  String combineKeyIV(String base64Key, String base64IV) {
    return '$base64Key:$base64IV';
  }

  /// Separa el string combinado ('clave:IV') de nuevo en un mapa.
  ///
  /// Lanza FormatException si el formato no es el esperado,
  /// lo cual me ayuda a detectar fallos en el descifrado RSA
  /// (ej. si usé la clave privada incorrecta).
  Map<String, String> splitKeyIV(String combined) {
    final parts = combined.split(':');
    if (parts.length == 2) {
      return {'key': parts[0], 'iv': parts[1]};
    } else {
      print("CryptoService Error: El string combinado '$combined' no tiene el formato esperado 'key:iv'.");
      throw const FormatException("El string combinado de clave/IV no tiene el formato esperado.");
    }
  }
} 