import 'package:flutter/material.dart';
import '../api/auth_api.dart';
import 'crypto_service.dart';
import 'secure_storage.dart';

class AuthService with ChangeNotifier {
  final _authApi = AuthApi();
  final _cryptoService = CryptoService();
  final _storageService = SecureStorageService();

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  String? _token;
  String? get token => _token;

  Future<void> tryAutoLogin() async {
    _token = await _storageService.getToken();
    if (_token != null) {
      _isAuthenticated = true;
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
      
          final response = await _authApi.register(
          username, email, password, publicKey);

      if (response['success']) {
        _token = response['token'];
        await _storageService.saveToken(_token!);
        await _storageService.savePrivateKey(privateKey);
        _isAuthenticated = true;
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
      if (response['success']) {
        _token = response['token'];
        await _storageService.saveToken(_token!);
        _isAuthenticated = true;
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
    _isAuthenticated = false;
    await _storageService.deleteAll();
    notifyListeners();
  }
}