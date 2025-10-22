// lib/services/crypto_service.dart

import 'package:fast_rsa/fast_rsa.dart';

class CryptoService {
  Future<Map<String, String>> generateRSAKeyPair() async {
    // Esta llamada utiliza código nativo optimizado. Es extremadamente rápida.
    final keyPair = await RSA.generate(2048);

    // El plugin ya nos devuelve las claves en el formato PEM que necesitamos.
    return {
      'publicKey': keyPair.publicKey,
      'privateKey': keyPair.privateKey,
    };
  }
}