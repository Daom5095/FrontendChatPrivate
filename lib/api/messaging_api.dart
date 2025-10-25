// lib/api/messaging_api.dart

import 'dart:convert';
// --- ¡ESTA ES LA LÍNEA A CORREGIR/ASEGURAR! ---
import 'package:http/http.dart' as http;
// ------------------------------------------
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

/// Mi clase para interactuar con los endpoints /api/messaging del backend.
class MessagingApi {
  final String _baseUrl = AppConstants.baseUrl;

  /// Obtiene la clave pública RSA (en formato PEM) de un usuario específico.
  Future<String> getPublicKey(String token, int userId) async {
    print("MessagingApi [getPublicKey]: Solicitando clave pública para usuario ID $userId...");
    try {
      // Ahora http.get será reconocido
      final response = await http.get(
        Uri.parse('$_baseUrl/api/messaging/public-key/$userId'),
        headers: { 'Authorization': 'Bearer $token' },
      );
      // ... (resto del método sin cambios) ...
      print("MessagingApi [getPublicKey]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final publicKeyPem = response.body;
        if (publicKeyPem.isEmpty) {
           print("MessagingApi [getPublicKey] Warning: Clave pública recibida está vacía para usuario $userId.");
           throw Exception('Clave pública recibida vacía para el usuario $userId');
        }
        print("MessagingApi [getPublicKey]: Clave pública obtenida para usuario $userId (longitud ${publicKeyPem.length}).");
        return publicKeyPem;
      } else if (response.statusCode == 404) {
        print("MessagingApi [getPublicKey] Error: Clave pública no encontrada para usuario $userId (404).");
        throw Exception('Clave pública no encontrada para el usuario $userId');
      } else {
        String errorMessage = 'Error desconocido al obtener la clave pública.';
        try { errorMessage = response.body.isNotEmpty ? response.body : 'Error ${response.statusCode} sin cuerpo.'; } catch (_) { errorMessage = 'Error ${response.statusCode} al obtener clave pública.'; }
        print("MessagingApi [getPublicKey] Error: $errorMessage");
        throw Exception('Error al obtener la clave pública: $errorMessage');
      }
    } catch (e) {
      print("MessagingApi [getPublicKey] Excepción: $e");
      if (e is Exception) rethrow;
      throw Exception('No se pudo conectar al servidor para obtener la clave pública: ${e.toString()}');
    }
  }

  /*
  // --- Método Potencial Futuro ---
  Future<bool> uploadPublicKey(String token, String publicKeyPem) async {
    // ... (código sin cambios) ...
  }
  */

} // Fin MessagingApi