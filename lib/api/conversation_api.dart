// lib/api/conversation_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';

class ConversationApi {
  final String _baseUrl = AppConstants.baseUrl;

  Future<List<dynamic>> getConversations(String token) async {

    print(
        "ConversationApi [getConversations]: Solicitando lista de conversaciones...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/conversations'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print(
          "ConversationApi [getConversations]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final List<dynamic> conversations = jsonDecode(response.body);
        print(
            "ConversationApi [getConversations]: ${conversations.length} conversaciones recibidas.");
        return conversations;
      } else {
        String errorMessage = 'Error desconocido al obtener conversaciones.';
        try {
          final errorBody = jsonDecode(response.body);
          errorMessage =
              errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
          errorMessage = response.body;
        }
        print("ConversationApi [getConversations] Error: $errorMessage");
        throw Exception('Error al cargar conversaciones: $errorMessage');
      }
    } catch (e) {
      print("ConversationApi [getConversations] Excepción: $e");
      throw Exception(
          'No se pudo conectar al servidor para obtener conversaciones: ${e.toString()}');
    }
  }


  Future<Map<String, dynamic>> createConversation(
      String token, int userId) async {
    print(
        "ConversationApi [createConversation]: Creando conversación 1-a-1 con usuario ID $userId...");
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/conversations'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': 'direct',
          'participantIds': [userId],
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> conversationData = jsonDecode(response.body);
        print(
            "ConversationApi [createConversation]: Conversación 1-a-1 creada/obtenida con ID ${conversationData['id']}.");
        return conversationData;
      } else {
        String errorMessage = 'Error desconocido al crear conversación 1-a-1.';
        try {
          final errorBody = jsonDecode(response.body);
          errorMessage =
              errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
          errorMessage = response.body;
        }
        print("ConversationApi [createConversation] Error: $errorMessage");
        throw Exception('Error al crear conversación 1-a-1: $errorMessage');
      }
    } catch (e) {
      print("ConversationApi [createConversation] Excepción: $e");
      throw Exception(
          'No se pudo conectar al servidor para crear conversación 1-a-1: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> createGroupConversation(
      String token, String title, List<int> participantIds) async {

    print(
        "ConversationApi [createGroupConversation]: Creando grupo '$title' con ${participantIds.length} miembros...");
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/conversations'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': 'group',
          'title': title,
          'participantIds': participantIds,
        }),
      );

      print(
          "ConversationApi [createGroupConversation]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> conversationData = jsonDecode(response.body);
        print(
            "ConversationApi [createGroupConversation]: Grupo creado con ID ${conversationData['id']}.");
        return conversationData;
      } else {
        String errorMessage = 'Error desconocido al crear grupo.';
        try {
          final errorBody = jsonDecode(response.body);
          errorMessage =
              errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
          errorMessage = response.body;
        }
        print("ConversationApi [createGroupConversation] Error: $errorMessage");
        throw Exception('Error al crear grupo: $errorMessage');
      }
    } catch (e) {
      print("ConversationApi [createGroupConversation] Excepción: $e");
      throw Exception(
          'No se pudo conectar al servidor para crear grupo: ${e.toString()}');
    }
  }


  Future<Map<String, dynamic>> getMessagesPaged(
      String token, int conversationId, int page, int size) async {
   
    print(
        "ConversationApi [getMessagesPaged]: Solicitando página $page (tamaño $size) para conv $conversationId...");
    try {
      final response = await http.get(
        Uri.parse(
            '$_baseUrl/api/conversations/$conversationId/messages/paged?page=$page&size=$size'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print(
          "ConversationApi [getMessagesPaged]: Respuesta recibida - Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final Map<String, dynamic> pagedData = jsonDecode(response.body);
        print(
            "ConversationApi [getMessagesPaged]: Recibidos ${pagedData['numberOfElements']} mensajes.");
        return pagedData;
      } else {
        String errorMessage = 'Error desconocido al obtener mensajes paginados.';
        try {
          final errorBody = jsonDecode(response.body);
          errorMessage =
              errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
          errorMessage = response.body;
        }
        print("ConversationApi [getMessagesPaged] Error: $errorMessage");
        throw Exception('Error al cargar historial paginado: $errorMessage');
      }
    } catch (e) {
      print("ConversationApi [getMessagesPaged] Excepción: $e");
      throw Exception(
          'No se pudo conectar al servidor para historial paginado: ${e.toString()}');
    }
  }


  /// Obtiene la lista actualizada de participantes de un chat.
  /// Llama a GET /api/conversations/{id}/participants
  Future<List<dynamic>> getParticipants(String token, int conversationId) async {
    print("ConversationApi [getParticipants]: Solicitando participantes para conv $conversationId...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/conversations/$conversationId/participants'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error al obtener participantes: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión al obtener participantes: $e');
    }
  }

  /// Añade un nuevo participante a una conversación.
  /// Llama a POST /api/conversations/{id}/participants
  Future<void> addParticipant(String token, int conversationId, int userIdToAdd) async {
    print("ConversationApi [addParticipant]: Añadiendo usuario $userIdToAdd a conv $conversationId...");
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/conversations/$conversationId/participants'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userIdToAdd, // El DTO AddParticipantRequest del backend
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Error al añadir participante: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión al añadir participante: $e');
    }
  }

  /// Elimina un participante de una conversación.
  /// Llama a DELETE /api/conversations/{id}/participants/{userId}
  Future<void> removeParticipant(String token, int conversationId, int userIdToRemove) async {
    print("ConversationApi [removeParticipant]: Eliminando usuario $userIdToRemove de conv $conversationId...");
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/conversations/$conversationId/participants/$userIdToRemove'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception('Error al eliminar participante: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión al eliminar participante: $e');
    }
  }
}