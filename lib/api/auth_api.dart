

import 'dart:convert'; 
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';

class AuthApi {
  final String _baseUrl = AppConstants.baseUrl;

  Future<Map<String, dynamic>> register(
      String username, String email, String password, String publicKey) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({ // Ahora esto funcionará
        'username': username,
        'email': email,
        'password': password,
        'publicKey': publicKey,
      }),
    );

    if (response.statusCode == 200) {
      return {'success': true, 'token': jsonDecode(response.body)['token']}; // Y esto también
    } else {
      return {'success': false, 'message': 'Error en el registro: ${response.body}'};
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