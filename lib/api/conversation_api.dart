// lib/api/conversation_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';

class ConversationApi {
  final String _baseUrl = AppConstants.baseUrl;

  // Método para crear una nueva conversación (existente)
  Future<Map<String, dynamic>> createConversation(String token, int userId) async {
    // ... (código existente sin cambios)
     final response = await http.post(
      Uri.parse('$_baseUrl/api/conversations'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'direct', // Para chats de 1 a 1
        'participantIds': [userId], // El ID del usuario con el que quieres chatear
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create conversation');
    }
  }


  /// Obtiene el historial de mensajes para una conversación específica.
  /// Devuelve una lista de mapas, donde cada mapa representa un MessageHistoryDto.
  Future<List<dynamic>> getMessages(String token, int conversationId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/conversations/$conversationId/messages'), // Endpoint del backend
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      // El backend devuelve una lista de objetos JSON
      return jsonDecode(response.body);
    } else {
      throw Exception('Error al cargar el historial de mensajes: ${response.statusCode} ${response.body}');
    }
  }
}