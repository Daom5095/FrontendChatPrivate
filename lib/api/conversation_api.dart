

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';

class ConversationApi {
  final String _baseUrl = AppConstants.baseUrl;

  // Método para crear una nueva conversación
  Future<Map<String, dynamic>> createConversation(String token, int userId) async {
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
}