// lib/services/crypto_service.dart

import 'package:fast_rsa/fast_rsa.dart';
import 'package:encrypt/encrypt.dart' as encrypt; // Usamos un alias
import 'dart:convert'; // Para base64 y utf8
import 'dart:math';    // Para generar IV aleatorio
import 'dart:typed_data'; // Para Uint8List

class CryptoService {
  /// Genera un par de claves RSA de 2048 bits.
  Future<Map<String, String>> generateRSAKeyPair() async {
    final keyPair = await RSA.generate(2048);
    return {
      'publicKey': keyPair.publicKey,
      'privateKey': keyPair.privateKey,
    };
  }

  // --- NUEVAS FUNCIONES AES ---

  /// Genera una clave AES segura (32 bytes = 256 bits) y un IV (16 bytes).
  /// Devuelve un mapa con 'key' (Base64) e 'iv' (Base64).
  Map<String, String> generateAESKeyAndIV() {
    final key = encrypt.Key.fromSecureRandom(32); // AES-256
    final iv = encrypt.IV.fromSecureRandom(16); // IV siempre es 16 bytes para AES
    return {
      'key': key.base64,
      'iv': iv.base64,
    };
  }

  /// Cifra un texto plano usando AES/CBC/PKCS7.
  /// Necesita la clave AES y el IV (ambos en Base64).
  /// Devuelve el texto cifrado en Base64.
  String encryptAES(String plainText, String base64Key, String base64IV) {
    final key = encrypt.Key.fromBase64(base64Key);
    final iv = encrypt.IV.fromBase64(base64IV);
    // Usamos AES modo CBC con padding PKCS7 (el default en el paquete encrypt)
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64; // Devolvemos como Base64
  }

  /// Descifra un texto cifrado (Base64) usando AES/CBC/PKCS7.
  /// Necesita la clave AES y el IV (ambos en Base64).
  /// Devuelve el texto plano.
  String decryptAES(String encryptedBase64, String base64Key, String base64IV) {
    final key = encrypt.Key.fromBase64(base64Key);
    final iv = encrypt.IV.fromBase64(base64IV);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encryptedData = encrypt.Encrypted.fromBase64(encryptedBase64);
    final decrypted = encrypter.decrypt(encryptedData, iv: iv);
    return decrypted;
  }

  // --- FUNCIONES RSA (YA PROPORCIONADAS POR fast_rsa, PERO CON WRAPPERS PARA CLARIDAD) ---

  /// Cifra datos (generalmente la clave AES + IV) usando una clave pública RSA (formato PEM).
  /// fast_rsa usa OAEP padding por defecto, que es seguro.
  /// Devuelve el resultado cifrado en Base64.
  Future<String> encryptRSA(String dataToEncrypt, String publicKeyPem) async {
    // fast_rsa espera los datos como String
    return await RSA.encryptPKCS1v15(dataToEncrypt, publicKeyPem);
     // OJO: Podrías necesitar usar RSA.encryptOAEP si el backend lo espera,
     // pero PKCS1v15 es más común y simple de implementar en ambos lados inicialmente.
     // Si usas OAEP, asegúrate que el backend use el mismo hash (ej. SHA-256)
     // return await RSA.encryptOAEP(dataToEncrypt, '', Hash.SHA256, publicKeyPem);
  }

  /// Descifra datos (Base64, generalmente la clave AES + IV) usando la clave privada RSA (formato PEM).
  Future<String> decryptRSA(String encryptedBase64, String privateKeyPem) async {
    // fast_rsa devuelve el resultado como String
    return await RSA.decryptPKCS1v15(encryptedBase64, privateKeyPem);
    // return await RSA.decryptOAEP(encryptedBase64, '', Hash.SHA256, privateKeyPem); // Si usaste OAEP
  }


  /// Combina la clave AES y el IV en un solo string (ej: "claveBase64:ivBase64")
  /// para cifrarlo con RSA.
  String combineKeyIV(String base64Key, String base64IV) {
    return '$base64Key:$base64IV';
  }

  /// Separa el string combinado "claveBase64:ivBase64" en un mapa.
  Map<String, String> splitKeyIV(String combined) {
    final parts = combined.split(':');
    if (parts.length == 2) {
      return {'key': parts[0], 'iv': parts[1]};
    } else {
      throw const FormatException("El string combinado de clave/IV no tiene el formato esperado.");
    }
  }
}