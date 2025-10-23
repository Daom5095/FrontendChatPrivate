// lib/services/auth_service.dart

import 'dart:convert';
// --- IMPORTACIONES CORREGIDAS ---
import 'package:flutter/material.dart';       // Correcto: package:flutter/material.dart
import 'package:http/http.dart' as http;      // Correcto: package:http/http.dart
import 'package:jwt_decoder/jwt_decoder.dart'; // Correcto: package:jwt_decoder/jwt_decoder.dart
// ---------------------------------
import '../config/app_constants.dart';
import 'secure_storage.dart';
import 'crypto_service.dart';
import '../api/user_api.dart';

class AuthService with ChangeNotifier { // Ahora ChangeNotifier debería ser reconocido
  final SecureStorageService _storageService = SecureStorageService();
  final CryptoService _cryptoService = CryptoService();
  final UserApi _userApi = UserApi();

  String? _token;
  int? _userId;
  String? _username;

  // --- GETTERS ---
  String? get token => _token;
  int? get userId => _userId;
  String? get username => _username;

  bool get isAuthenticated {
     try {
       // JwtDecoder debería ser reconocido ahora
       return _token != null && !JwtDecoder.isExpired(_token!);
     } catch (e) {
       print("Error al decodificar token en isAuthenticated: $e");
       return false;
     }
  }

  Future<void> init() async {
    _token = await _storageService.getToken();
    if (_token != null) {
      bool isTokenExpired = false;
      try {
        isTokenExpired = JwtDecoder.isExpired(_token!); // JwtDecoder reconocido
      } catch(e) {
        print("AuthService: Error al decodificar token almacenado: $e. Eliminando token.");
        isTokenExpired = true;
      }

      if (!isTokenExpired) {
        try {
          await _fetchAndSetUserData(_token!);
          print("AuthService: Token cargado y válido para usuario $_username (ID: $_userId)");
        } catch (e) {
           print("AuthService: Error al obtener datos de usuario con token almacenado: $e");
           _token = null;
           _userId = null;
           _username = null;
           await _storageService.deleteToken();
        }
      } else {
        print("AuthService: Token expirado o inválido, eliminando.");
        _token = null;
        _userId = null;
        _username = null;
        await _storageService.deleteToken();
        await _storageService.deletePrivateKey();
      }
    } else {
      print("AuthService: No se encontró token.");
    }
     notifyListeners(); // notifyListeners reconocido
  }

  Future<void> _fetchAndSetUserData(String token) async {
      final userData = await _userApi.getMe(token);
      _userId = userData['id'];
      _username = userData['username'];
  }

  Future<bool> register(String username, String email, String password) async {
    try {
      print("AuthService: Generando par de claves RSA...");
      final keyPair = await _cryptoService.generateRSAKeyPair();
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;

      if (publicKey.isEmpty || privateKey.isEmpty) {
        print("AuthService ERROR: Claves RSA generadas vacías.");
        return false;
      }
      print("AuthService: Claves RSA generadas con éxito.");
      print("AuthService: Longitud de Clave Privada generada: ${privateKey.length}");

      // http.post debería ser reconocido ahora
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
          'publicKey': publicKey,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _token = data['token'];
        if (_token == null) {
           print("AuthService ERROR: Backend no devolvió token en registro exitoso.");
           return false;
        }
        await _fetchAndSetUserData(_token!);
        await _storageService.saveToken(_token!);
        print("AuthService: Token guardado con éxito.");
        await _storageService.savePrivateKey(privateKey);
        print("AuthService: Clave privada guardada con éxito.");
        notifyListeners(); // reconocido
        return true;
      } else {
        print("AuthService ERROR al registrar (Backend): ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("AuthService ERROR al registrar (General): $e");
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      // http.post reconocido
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        _token = data['token'];
        if (_token == null) {
           print("AuthService ERROR: Backend no devolvió token en login exitoso.");
           return false;
        }
        await _fetchAndSetUserData(_token!);
        await _storageService.saveToken(_token!);
        print("AuthService: Login exitoso. Token guardado.");
        notifyListeners(); // reconocido
        return true;
      } else {
        print("AuthService ERROR al iniciar sesión (Backend): ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("AuthService ERROR al iniciar sesión (General): $e");
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _username = null;
    await _storageService.deleteToken();
    await _storageService.deletePrivateKey();
    notifyListeners(); // reconocido
    print("AuthService: Sesión cerrada y token/clave eliminados.");
  }
} 