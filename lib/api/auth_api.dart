import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';

class AuthApi {
  final String _baseUrl = AppConstants.baseUrl;

  Future<Map<String, dynamic>> registerAndUploadKey(
      String username, String email, String password, String publicKey) async {
    final registerResponse = await http.post(
      Uri.parse('$_baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );

    if (registerResponse.statusCode != 200) {
      return {'success': false, 'message': 'Error en el registro: ${registerResponse.body}'};
    }

    final token = jsonDecode(registerResponse.body)['token'];

    final keyUploadResponse = await http.post(
      Uri.parse('$_baseUrl/api/messaging/public-key'),
      headers: {
        'Content-Type': 'text/plain',
        'Authorization': 'Bearer $token',
      },
      body: publicKey,
    );

    if (keyUploadResponse.statusCode == 200) {
      return {'success': true, 'token': token};
    } else {
      return {'success': false, 'message': 'Registro exitoso, pero falló la subida de la clave pública.'};
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      return {'success': true, 'token': jsonDecode(response.body)['token']};
    } else {
      return {'success': false, 'message': 'Error en el login: ${response.body}'};
    }
  }
}