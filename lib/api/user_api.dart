// lib/api/user_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http; // <-- ¡ESTA ES LA LÍNEA CORREGIDA!
import '../config/app_constants.dart';

class UserApi {
  final String _baseUrl = AppConstants.baseUrl;

  Future<Map<String, dynamic>> getMe(String token) async {
    final response = await http.get( // Ahora 'http.get' será reconocido
      Uri.parse('$_baseUrl/api/users/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user data');
    }
  }

  Future<List<dynamic>> getAllUsers(String token) async {
    final response = await http.get( // Y aquí también
      Uri.parse('$_baseUrl/api/users'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load users');
    }
  }
}