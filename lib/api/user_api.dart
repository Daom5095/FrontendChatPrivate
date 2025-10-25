// lib/api/user_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

/// Mi clase para interactuar con los endpoints /api/users del backend.
class UserApi {
  final String _baseUrl = AppConstants.baseUrl; // URL base del backend

  /// Obtiene los datos (ID, username) del usuario actualmente autenticado.
  /// Llama a GET /api/users/me.
  /// Devuelve un Map<String, dynamic> con los datos del usuario.
  /// Lanza una excepción si la llamada falla (error de red, token inválido, etc.).
  Future<Map<String, dynamic>> getMe(String token) async {
    print("UserApi [getMe]: Solicitando datos del usuario actual...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/users/me'), // Endpoint del backend
        headers: {
          'Authorization': 'Bearer $token', // Autenticación necesaria
        },
      );

      print("UserApi [getMe]: Respuesta recibida - Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Éxito, el backend devuelve el UserDto como JSON
        final Map<String, dynamic> userData = jsonDecode(response.body);
        print("UserApi [getMe]: Datos recibidos: $userData");
        return userData;
      } else {
        // Manejar errores de la API (ej: 401 Unauthorized, 403 Forbidden, 500 Internal Server Error)
        String errorMessage = 'Error desconocido al obtener datos del usuario.';
        try {
           // Intentar decodificar el cuerpo de error JSON del backend
           final errorBody = jsonDecode(response.body);
           errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
           errorMessage = response.body; // Si no es JSON, usar el cuerpo tal cual
        }
        print("UserApi [getMe] Error: $errorMessage (Status: ${response.statusCode})");
        // Lanzar excepción con el mensaje de error
        throw Exception('Error al obtener datos del usuario: $errorMessage');
      }
    } catch (e) {
      // Manejar errores de red u otros errores inesperados
      print("UserApi [getMe] Excepción: $e");
      // Re-lanzar para que el llamador (AuthService) lo maneje
      throw Exception('No se pudo conectar al servidor para obtener datos del usuario: ${e.toString()}');
    }
  }

  /// Obtiene una lista de todos los usuarios registrados, excluyendo al usuario actual.
  /// Llama a GET /api/users.
  /// Devuelve una List<dynamic> donde cada elemento es un Map<String, dynamic> (UserDto).
  /// Lanza una excepción si la llamada falla.
  Future<List<dynamic>> getAllUsers(String token) async {
    print("UserApi [getAllUsers]: Solicitando lista de usuarios...");
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/users'), // Endpoint del backend
        headers: {
          'Authorization': 'Bearer $token', // Autenticación necesaria
        },
      );

      print("UserApi [getAllUsers]: Respuesta recibida - Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Éxito, el backend devuelve una lista JSON de UserDto
        final List<dynamic> userList = jsonDecode(response.body);
        print("UserApi [getAllUsers]: ${userList.length} usuarios recibidos.");
        return userList;
      } else {
        // Manejar errores de la API
        String errorMessage = 'Error desconocido al obtener la lista de usuarios.';
        try {
           final errorBody = jsonDecode(response.body);
           errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
           errorMessage = response.body;
        }
        print("UserApi [getAllUsers] Error: $errorMessage (Status: ${response.statusCode})");
        throw Exception('Error al cargar usuarios: $errorMessage');
      }
    } catch (e) {
      // Manejar errores de red u otros
      print("UserApi [getAllUsers] Excepción: $e");
      throw Exception('No se pudo conectar al servidor para obtener usuarios: ${e.toString()}');
    }
  }
}