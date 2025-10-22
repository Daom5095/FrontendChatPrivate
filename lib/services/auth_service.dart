// lib/services/auth_service.dart

import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import '../api/user_api.dart'; // <-- IMPORTANTE
import 'crypto_service.dart';
import 'secure_storage.dart';

class AuthService with ChangeNotifier {
  final _authApi = AuthApi();
  final _userApi = UserApi(); // <-- AÑADIR
  final _cryptoService = CryptoService();
  final _storageService = SecureStorageService();

  bool _isAuthenticated = false;
  String? _token;
  int? _userId; // <-- VARIABLE PARA GUARDAR EL ID
  String? _username;

  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;
  int? get userId => _userId; // <-- GETTER PARA ACCEDER AL ID
  String? get username => _username;

  Future<void> _processLogin(String token) async {
    _token = token;
    await _storageService.saveToken(token);

    // Llamamos a /api/users/me para obtener los datos del usuario
    final userData = await _userApi.getMe(token);
    _userId = userData['id'];
    _username = userData['username'];
    
    _isAuthenticated = true;
  }

  Future<void> tryAutoLogin() async {
    final storedToken = await _storageService.getToken();
    if (storedToken != null) {
      try {
        await _processLogin(storedToken);
      } catch (e) {
        _isAuthenticated = false;
      }
    } else {
      _isAuthenticated = false;
    }
    notifyListeners();
  }

  Future<bool> register(String username, String email, String password) async {
    try {
      final keys = await _cryptoService.generateRSAKeyPair();
      final publicKey = keys['publicKey']!;
      final privateKey = keys['privateKey']!;
      
      final response = await _authApi.register(username, email, password, publicKey);

      if (response['success'] == true && response['token'] != null) {
        await _processLogin(response['token']);
        await _storageService.savePrivateKey(privateKey);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print("Error en el registro: $e");
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final response = await _authApi.login(username, password);
      if (response['success'] == true && response['token'] != null) {
        await _processLogin(response['token']);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print("Error en el login: $e");
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _username = null;
    _isAuthenticated = false;
    await _storageService.deleteAll();
    notifyListeners();
  }
}