// lib/services/auth_service.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import '../config/app_constants.dart';
import 'secure_storage.dart';
import 'crypto_service.dart';
import '../api/user_api.dart';

class AuthService with ChangeNotifier {
  final SecureStorageService _storageService = SecureStorageService();
  final CryptoService _cryptoService = CryptoService();
  final UserApi _userApi = UserApi();

  String? _token;
  int? _userId;
  String? _username;

  String? get token => _token;
  int? get userId => _userId;
  String? get username => _username;

  bool get isAuthenticated {
     try {
       return _token != null && !JwtDecoder.isExpired(_token!);
     } catch (e) {
       print("Error al decodificar token en isAuthenticated: $e");
       return false;
     }
  }

  Future<void> init() async {
    // ... (El método init permanece igual que la versión anterior) ...
    _token = await _storageService.getToken();
    if (_token != null) {
      bool isTokenExpired = false;
      try {
        isTokenExpired = JwtDecoder.isExpired(_token!);
      } catch(e) {
        print("AuthService: Error al decodificar token almacenado: $e. Eliminando token.");
        isTokenExpired = true; // Tratar como expirado si no se puede decodificar
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
     notifyListeners();
  }

  Future<void> _fetchAndSetUserData(String token) async {
      final userData = await _userApi.getMe(token);
      // Asegurarse de convertir a int si viene como num
      _userId = (userData['id'] as num?)?.toInt();
      _username = userData['username'];
       if (_userId == null || _username == null) {
         throw Exception("Datos de usuario (/me) inválidos recibidos del backend.");
       }
  }


  // --- MÉTODO REGISTER CORREGIDO ---
  // (Quitamos prints excesivos, corregimos acceso a privateKey)
  Future<bool> register(String username, String email, String password) async {
    String? localPrivateKey; // Variable local para la clave privada
    try {
      print("AuthService: Generando par de claves RSA...");
      final keyPair = await _cryptoService.generateRSAKeyPair();
      final publicKey = keyPair['publicKey']!;
      localPrivateKey = keyPair['privateKey']!; // Asignar a variable local

      if (publicKey.isEmpty || localPrivateKey == null || localPrivateKey!.isEmpty) {
        print("AuthService ERROR: Claves RSA generadas vacías o nulas.");
        return false;
      }
      print("AuthService: Claves RSA generadas con éxito.");

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
        print("AuthService: Backend respondió OK (200).");
        final Map<String, dynamic> data = json.decode(response.body);
        _token = data['token'];
        if (_token == null) {
           print("AuthService ERROR: Backend no devolvió token en registro exitoso.");
           return false;
        }
        print("AuthService: Token obtenido.");

        await _fetchAndSetUserData(_token!);
        print("AuthService: Datos del usuario (/me) obtenidos.");

        await _storageService.saveToken(_token!);
        print("AuthService: Token guardado en storage.");

        // Usar la variable local 'localPrivateKey'
        await _storageService.savePrivateKey(localPrivateKey!);
        print("AuthService: Clave privada guardada en storage.");

        print("AuthService: Notificando listeners...");
        notifyListeners();
        print("AuthService: Listeners notificados. Retornando true.");
        return true;
      } else {
        print("AuthService ERROR al registrar (Backend): ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("AuthService ERROR al registrar (General): $e");
      return false;
    }
  } // Fin register

  // --- LOGIN ---
  Future<bool> login(String username, String password) async {
    // ... (El método login permanece igual que la versión anterior) ...
     try {
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
        notifyListeners();
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

  // --- LOGOUT ---
  Future<void> logout() async {
    // ... (El método logout permanece igual que la versión anterior) ...
    _token = null;
    _userId = null;
    _username = null;
    await _storageService.deleteToken();
    await _storageService.deletePrivateKey();
    notifyListeners();
    print("AuthService: Sesión cerrada y token/clave eliminados.");
  }
} // Fin clase