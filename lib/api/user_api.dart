import 'dart.convert';
import 'package:http/http.dart' as http;
import '../config/app_constants.dart';

class UserApi {
  final String _baseUrl = AppConstants.baseUrl;

  Future<List<dynamic>> getAllUsers(String token) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/users'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load users');
    }
  }
}