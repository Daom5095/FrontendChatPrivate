// lib/services/auth_service.dart

import 'dart:convert'; 
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'secure_storage.dart';
import 'crypto_service.dart';
import '../api/user_api.dart';
import '../api/auth_api.dart';
import 'socket_service.dart'; 

/// Mi servicio central para manejar todo lo relacionado con la autenticación.
///
class AuthService with ChangeNotifier {
 
  final AuthApi _authApi = AuthApi();
  final SecureStorageService _storageService = SecureStorageService();
  final CryptoService _cryptoService = CryptoService();
  final UserApi _userApi = UserApi();

  
  String? _token;
  int? _userId;
  String? _username;
  String? _sessionPrivateKey;

  String? get token => _token;
  int? get userId => _userId;
  String? get username => _username;
  bool get isAuthenticated {
     try {
       return _token != null && !JwtDecoder.isExpired(_token!);
     } catch (e) {
       print("AuthService: Error al decodificar token en isAuthenticated: $e");
       return false;
     }
  }

  // ... (init, _clearLocalSession, _fetchAndSetUserData, register, login, getPrivateKeyForSession no cambian) ...
  Future<void> init() async {
    print("AuthService: Iniciando... Intentando cargar token.");
    _token = await _storageService.getToken(); 

    if (_token != null) {
      print("AuthService: Token encontrado.");
      bool isTokenExpired = false;
      try {
        isTokenExpired = JwtDecoder.isExpired(_token!);
      } catch(e) {
        print("AuthService: Error al decodificar token almacenado: $e. Limpiando.");
        isTokenExpired = true; 
      }

      if (!isTokenExpired) {
        print("AuthService: Token no expirado. Obteniendo datos /me...");
        try {
          await _fetchAndSetUserData(_token!);
          print("AuthService: Sesión potencialmente válida para usuario $_username (ID: $_userId). Clave privada NO cargada aún.");
        } catch (e) {
           print("AuthService: Error al obtener datos /me con token: $e. Limpiando token local.");
           await _clearLocalSession(clearPrivateKey: false);
        }
      } else {
        print("AuthService: Token expirado. Limpiando sesión local.");
        await _clearLocalSession(clearPrivateKey: true);
      }
    } else {
      print("AuthService: No se encontró token almacenado.");
    }
     notifyListeners();
  }

  Future<void> _clearLocalSession({required bool clearPrivateKey}) async {
      _token = null;
      _userId = null;
      _username = null;
      _sessionPrivateKey = null;
      await _storageService.deleteToken(); 

      if (clearPrivateKey) {
        print("AuthService: Borrando también la clave privada del storage.");
        await _storageService.deletePrivateKey();
      } else {
        print("AuthService: Manteniendo la clave privada en el storage.");
      }
  }

  Future<void> _fetchAndSetUserData(String token) async {
      final userData = await _userApi.getMe(token);
      
      _userId = (userData['id'] as num?)?.toInt();
      _username = userData['username'];
      
       if (_userId == null || _username == null) {
         throw Exception("Datos de usuario (/me) inválidos o incompletos recibidos del backend.");
       }
  }

  Future<bool> register(String username, String email, String password) async {
    String? generatedPrivateKey;
    try {
      print("AuthService [Register]: Iniciando proceso criptográfico...");
      final keyPair = await _cryptoService.generateRSAKeyPair();
      final publicKey = keyPair['publicKey']!;
      generatedPrivateKey = keyPair['privateKey']!;
      if (publicKey.isEmpty || generatedPrivateKey == null || generatedPrivateKey!.isEmpty) {
        throw Exception("Error crítico: Fallo al generar claves RSA.");
      }
      print("AuthService [Register]: Claves RSA generadas.");

      final saltKek = _cryptoService.generateSecureRandomSalt();
      final kekBytes = _cryptoService.deriveKeyFromPasswordPBKDF2(password, saltKek);
      print("AuthService [Register]: KEK derivada de la contraseña.");

      final encryptedKeyData = _cryptoService.encryptAES_GCM(generatedPrivateKey!, kekBytes);
      final encryptedPrivateKeyB64 = encryptedKeyData['ciphertext']!;
      final kekIvB64 = encryptedKeyData['iv']!;
      print("AuthService [Register]: Clave privada cifrada con KEK.");

      print("AuthService [Register]: Llamando a AuthApi.register...");
      final apiResult = await _authApi.register(
        username: username,
        email: email,
        password: password,
        publicKey: publicKey,
        kekSalt: base64Encode(saltKek),
        encryptedPrivateKey: encryptedPrivateKeyB64,
        kekIv: kekIvB64,
      );

      if (apiResult['success'] == true) {
        print("AuthService [Register]: AuthApi.register reportó éxito.");
        _token = apiResult['token'];
        if (_token == null) throw Exception("AuthApi.register tuvo éxito pero no devolvió un token.");

        await _fetchAndSetUserData(_token!);
        print("AuthService [Register]: Datos del nuevo usuario obtenidos: $_username (ID: $_userId).");

        await _storageService.saveToken(_token!);
        await _storageService.savePrivateKey(generatedPrivateKey!);
        _sessionPrivateKey = generatedPrivateKey;
        print("AuthService [Register]: Token y clave privada ORIGINAL guardados localmente.");

        notifyListeners();
        return true;
      } else {
        final errorMessage = apiResult['message'] ?? 'Error desconocido durante el registro.';
        print("AuthService [Register] ERROR (desde AuthApi): $errorMessage");
        throw Exception(errorMessage);
      }
    } catch (e) {
      print("AuthService [Register] ERROR (General): $e");
      await _clearLocalSession(clearPrivateKey: true);
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      print("AuthService [Login]: Llamando a AuthApi.login para $username...");
      final apiResult = await _authApi.login(username, password);

      if (apiResult['success'] == true) {
        print("AuthService [Login]: AuthApi.login reportó éxito.");
        _token = apiResult['token'];
        final kekSaltB64 = apiResult['kekSalt'] as String?;
        final encryptedPrivateKeyB64 = apiResult['encryptedPrivateKey'] as String?;
        final kekIvB64 = apiResult['kekIv'] as String?;

        if (_token == null || kekSaltB64 == null || encryptedPrivateKeyB64 == null || kekIvB64 == null) {
          throw Exception("Respuesta de login incompleta recibida de AuthApi (faltan datos criptográficos).");
        }
        print("AuthService [Login]: Token y datos de clave cifrada recibidos.");

        await _fetchAndSetUserData(_token!);
        print("AuthService [Login]: Datos del usuario (/me) obtenidos: $_username (ID: $_userId).");

        print("AuthService [Login]: Re-derivando KEK y descifrando clave privada RSA...");
        final saltKek = base64Decode(kekSaltB64);
        final kekBytes = _cryptoService.deriveKeyFromPasswordPBKDF2(password, saltKek);
        final privateKey = _cryptoService.decryptAES_GCM(encryptedPrivateKeyB64, kekBytes, kekIvB64);
        print("AuthService [Login]: Clave privada RSA descifrada.");
        if (privateKey.isEmpty) {
          throw Exception("Error crítico: La clave privada descifrada está vacía.");
        }

        await _storageService.saveToken(_token!);
        await _storageService.savePrivateKey(privateKey);
        _sessionPrivateKey = privateKey;
        print("AuthService [Login]: Token y clave privada descifrada guardados localmente.");

        notifyListeners();
        return true;
      } else {
        final errorMessage = apiResult['message'] ?? 'Error desconocido durante el login.';
        print("AuthService [Login] ERROR (desde AuthApi): $errorMessage");
        throw Exception(errorMessage);
      }
    } catch (e) {
      print("AuthService [Login] ERROR (General): $e");
      await _clearLocalSession(clearPrivateKey: true);
      notifyListeners();
      return false;
    }
  }

  Future<String?> getPrivateKeyForSession() async {
    if (_sessionPrivateKey != null) {
      print("AuthService [getPrivateKeyForSession]: Usando clave privada en memoria.");
      return _sessionPrivateKey;
    }
    
    print("AuthService [getPrivateKeyForSession]: Cargando clave privada desde storage...");
    _sessionPrivateKey = await _storageService.getPrivateKey();
    
    if (_sessionPrivateKey == null) {
       print("AuthService [getPrivateKeyForSession]: ADVERTENCIA: No se encontró clave privada en storage.");
    } else {
       print("AuthService [getPrivateKeyForSession]: Clave privada cargada desde storage.");
    }
    return _sessionPrivateKey;
  }


  /// **LOGOUT:** Limpia el estado, el token y la clave privada de memoria y storage.
  Future<void> logout() async {
    print("AuthService: Cerrando sesión...");
    
 
    // Desconecta el WebSocket antes de limpiar la sesión.
    SocketService.instance.disconnect();
   

    await _clearLocalSession(clearPrivateKey: true); // Asegura borrar todo
    notifyListeners(); // Notifica a la UI para redirigir a LoginScreen
    print("AuthService: Sesión cerrada y datos locales eliminados.");
  }
}