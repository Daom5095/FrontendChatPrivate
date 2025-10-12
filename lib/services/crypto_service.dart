// lib/services/crypto_service.dart

import 'package:basic_utils/basic_utils.dart';
// Importamos la clase específica que necesitamos para la conversión
import 'package:pointycastle/asymmetric/api.dart';

class CryptoService {
  Future<Map<String, String>> generateRSAKeyPair() async {
    final keyPair = CryptoUtils.generateRSAKeyPair();

    
    // Le decimos a Dart que trate estas claves como claves RSA específicas
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    // ------------------------------------

 
    final publicKeyPem = CryptoUtils.encodeRSAPublicKeyToPem(publicKey);
    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

    return {
      'publicKey': publicKeyPem,
      'privateKey': privateKeyPem,
    };
  }
}