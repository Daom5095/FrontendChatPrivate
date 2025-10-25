// lib/api/auth_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart'; // Asegúrate que la ruta sea correcta

/// Mi clase dedicada a realizar las llamadas HTTP a los endpoints de autenticación del backend.
class AuthApi {
  final String _baseUrl = AppConstants.baseUrl; // URL base de mi backend

  /// **REGISTRO ACTUALIZADO:** Llama al endpoint /api/auth/register del backend.
  /// Ahora acepta todos los campos necesarios, incluyendo los criptográficos.
  /// Devuelve un mapa con `success: true` y el `token` si el registro es exitoso.
  /// Devuelve un mapa con `success: false` y un `message` si falla.
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String publicKey,
    // --- Campos Criptográficos Añadidos ---
    required String kekSalt, // Base64
    required String encryptedPrivateKey, // Base64
    required String kekIv, // Base64
    // ------------------------------------
  }) async {
    try {
      print("AuthApi [Register]: Enviando solicitud a $_baseUrl/api/auth/register");
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        // Construimos el cuerpo JSON con TODOS los campos esperados por el backend
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'publicKey': publicKey,
          'kekSalt': kekSalt,
          'encryptedPrivateKey': encryptedPrivateKey,
          'kekIv': kekIv,
        }),
      );

      print("AuthApi [Register]: Respuesta recibida - Status: ${response.statusCode}");

      // Procesar la respuesta del backend
      if (response.statusCode == 200) {
        // Registro exitoso, el backend devuelve {'token': '...'}
        final responseBody = jsonDecode(response.body);
        return {'success': true, 'token': responseBody['token']};
      } else {
        // Error en el registro (ej: usuario/email ya existe, validación fallida)
        String errorMessage = 'Error desconocido en el registro.';
        try {
           // Intentar extraer el mensaje de error del backend (si lo envía en formato JSON)
           final errorBody = jsonDecode(response.body);
           // Asumimos que el backend envía el error en un campo 'error' o 'message'
           errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
           errorMessage = response.body; // Si no es JSON, usar el cuerpo tal cual
        }
        print("AuthApi [Register] Error: $errorMessage");
        return {'success': false, 'message': errorMessage};
      }
    } catch (e) {
      // Error de red u otro error inesperado
      print("AuthApi [Register] Excepción: $e");
      return {'success': false, 'message': 'No se pudo conectar al servidor: ${e.toString()}'};
    }
  }

  /// **LOGIN ACTUALIZADO:** Llama al endpoint /api/auth/login del backend.
  /// Devuelve un mapa con `success: true` y **todos los datos** devueltos por el backend
  /// (token, kekSalt, encryptedPrivateKey, kekIv) si el login es exitoso.
  /// Devuelve un mapa con `success: false` y un `message` si falla.
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print("AuthApi [Login]: Enviando solicitud a $_baseUrl/api/auth/login");
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      print("AuthApi [Login]: Respuesta recibida - Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Login exitoso, el backend devuelve el objeto AuthResponse completo
        final Map<String, dynamic> responseBody = jsonDecode(response.body);
        // Devolvemos todos los datos junto con la bandera de éxito
        return {'success': true, ...responseBody}; // Usamos spread operator (...)
      } else {
        // Error en el login (usuario no encontrado, contraseña incorrecta)
        String errorMessage = 'Usuario o contraseña incorrectos.'; // Mensaje genérico por defecto
         try {
           final errorBody = jsonDecode(response.body);
           errorMessage = errorBody['error'] ?? errorBody['message'] ?? response.body;
        } catch (_) {
           // Si el error no es JSON, mantenemos el mensaje genérico o usamos response.body
           // errorMessage = response.body;
        }
        print("AuthApi [Login] Error: $errorMessage");
        return {'success': false, 'message': errorMessage};
      }
    } catch (e) {
      // Error de red u otro error inesperado
      print("AuthApi [Login] Excepción: $e");
      return {'success': false, 'message': 'No se pudo conectar al servidor: ${e.toString()}'};
    }
  }
}