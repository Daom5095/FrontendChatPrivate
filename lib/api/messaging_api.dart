// lib/api/messaging_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart'; 

/// Mi clase para interactuar con los endpoints /api/messaging del backend.
///
/// Esta API se encarga de operaciones criptográficas auxiliares,
/// como obtener las claves públicas de otros usuarios.
class MessagingApi {
  /// URL base de mi backend, tomada de mis constantes.
  final String _baseUrl = AppConstants.baseUrl;

  /// Obtiene la clave pública RSA (en formato PEM) de un usuario específico.
  /// Llama a GET /api/messaging/public-key/{userId}.
  ///
  /// Esto es fundamental para el E2EE: necesito la clave pública del
  /// destinatario para cifrar la clave AES del mensaje que le voy a enviar.
  Future<String> getPublicKey(String token, int userId) async {
    print("MessagingApi [getPublicKey]: Solicitando clave pública para usuario ID $userId...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/messaging/public-key/$userId'),
        headers: { 'Authorization': 'Bearer $token' },
      );

      print("MessagingApi [getPublicKey]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        // El backend devuelve la clave PEM como texto plano en el body
        final publicKeyPem = response.body;
        if (publicKeyPem.isEmpty) {
           print("MessagingApi [getPublicKey] Warning: Clave pública recibida está vacía para usuario $userId.");
           throw Exception('Clave pública recibida vacía para el usuario $userId');
        }
        print("MessagingApi [getPublicKey]: Clave pública obtenida para usuario $userId (longitud ${publicKeyPem.length}).");
        return publicKeyPem;
      } else if (response.statusCode == 404) {
        // Esto pasa si el usuario no existe o no tiene clave
        print("MessagingApi [getPublicKey] Error: Clave pública no encontrada para usuario $userId (404).");
        throw Exception('Clave pública no encontrada para el usuario $userId');
      } else {
        // Otro error
        String errorMessage = 'Error desconocido al obtener la clave pública.';
        try { errorMessage = response.body.isNotEmpty ? response.body : 'Error ${response.statusCode} sin cuerpo.'; } catch (_) { errorMessage = 'Error ${response.statusCode} al obtener clave pública.'; }
        print("MessagingApi [getPublicKey] Error: $errorMessage");
        throw Exception('Error al obtener la clave pública: $errorMessage');
      }
    } catch (e) {
      // Error de red
      print("MessagingApi [getPublicKey] Excepción: $e");
      if (e is Exception) rethrow; // Re-lanzar si ya es una excepción
      throw Exception('No se pudo conectar al servidor para obtener la clave pública: ${e.toString()}');
    }
  }

  /*
  // --- Método Potencial Futuro ---
  /// Podría usar esto si permitiera a los usuarios rotar sus claves.
  Future<bool> uploadPublicKey(String token, String publicKeyPem) async {
    // ... (lógica para POST /api/messaging/public-key) ...
    return true;
  }
  */

} 