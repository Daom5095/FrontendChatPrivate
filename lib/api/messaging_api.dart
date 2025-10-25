// lib/api/messaging_api.dart

import 'dart:convert'; // Para jsonDecode en errores
import 'package.http/http.dart' as http;
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

/// Mi clase para interactuar con los endpoints /api/messaging del backend,
/// principalmente para obtener claves públicas.
class MessagingApi {
  final String _baseUrl = AppConstants.baseUrl;

  /// Obtiene la clave pública RSA (en formato PEM) de un usuario específico.
  /// Llama a GET /api/messaging/public-key/{userId}.
  /// Devuelve el string PEM de la clave pública.
  /// Lanza una excepción si la clave no se encuentra (404) o si ocurre otro error.
  Future<String> getPublicKey(String token, int userId) async {
    print("MessagingApi [getPublicKey]: Solicitando clave pública para usuario ID $userId...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/messaging/public-key/$userId'), // Endpoint del backend
        headers: {
          'Authorization': 'Bearer $token', // Autenticación necesaria
        },
      );

      print("MessagingApi [getPublicKey]: Respuesta recibida - Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Éxito, el backend devuelve el string PEM directamente en el cuerpo
        final String publicKeyPem = response.body;
        if (publicKeyPem.isEmpty) {
           print("MessagingApi [getPublicKey] Warning: Clave pública recibida está vacía para usuario $userId.");
           // Podríamos lanzar una excepción aquí si consideramos una clave vacía como error
           // throw Exception('Clave pública recibida vacía para el usuario $userId');
        } else {
           print("MessagingApi [getPublicKey]: Clave pública obtenida para usuario $userId.");
        }
        return publicKeyPem;
      } else if (response.statusCode == 404) {
        // Error específico: Usuario o clave no encontrada
        print("MessagingApi [getPublicKey] Error: No se encontró clave pública para usuario $userId (404).");
        throw Exception('Clave pública no encontrada para el usuario $userId');
      } else {
        // Otros errores de la API (ej: 401, 500)
        String errorMessage = 'Error desconocido al obtener clave pública.';
        try {
           final errorBody = jsonDecode(response.body);
           errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
           errorMessage = response.body;
        }
        print("MessagingApi [getPublicKey] Error API: $errorMessage (Status: ${response.statusCode})");
        throw Exception('Error al obtener la clave pública ($userId): $errorMessage');
      }
    } catch (e) {
      // Errores de red u otros inesperados (incluye las excepciones lanzadas arriba)
      print("MessagingApi [getPublicKey] Excepción: $e");
      // Si la excepción ya fue formateada por nosotros, la re-lanzamos tal cual.
      // Si es un error de red, formateamos un mensaje nuevo.
      if (e is Exception && e.toString().contains('Error al')) {
         rethrow; // Re-lanzar la excepción ya formateada
      } else {
         throw Exception('No se pudo conectar al servidor (clave pública): ${e.toString()}');
      }
    }
  }

  // Aquí podrían ir métodos futuros como:
  // - uploadPublicKey(String token, String publicKeyPem) -> POST /api/messaging/public-key
  //   (Aunque actualmente el registro ya sube la clave inicial)
}