// lib/api/messaging_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

class MessagingApi {
  final String _baseUrl = AppConstants.baseUrl;

  /// Obtiene la clave pública PEM de un usuario específico.
  ///
  /// Lanza una excepción si la clave no se encuentra o hay un error.
  Future<String> getPublicKey(String token, int userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/messaging/public-key/$userId'), // Endpoint del backend
      headers: {
        'Authorization': 'Bearer $token',
        // No necesitamos 'Content-Type' para un GET sin cuerpo
      },
    );

    if (response.statusCode == 200) {
      // El backend devuelve directamente el string PEM en el cuerpo
      return response.body;
    } else if (response.statusCode == 404) {
      throw Exception('Clave pública no encontrada para el usuario $userId');
    } else {
      throw Exception('Error al obtener la clave pública: ${response.statusCode} ${response.body}');
    }
  }

  // Aquí podrías añadir más métodos relacionados con /api/messaging si los necesitas en el futuro
  // Por ejemplo, si implementas un endpoint para subir/actualizar la clave pública después del registro.
}