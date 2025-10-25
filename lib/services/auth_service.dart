// lib/services/auth_service.dart

import 'dart:convert';
import 'dart:typed_data'; // Para Uint8List
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

  // Clave privada RSA en memoria para la sesión actual (después de login/registro)
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

  /// Intenta cargar el token almacenado y validar la sesión al inicio.
  /// NO carga la clave privada aquí, se hará bajo demanda o en login.
  Future<void> init() async {
    _token = await _storageService.getToken();
    if (_token != null) {
      bool isTokenExpired = false;
      try {
        isTokenExpired = JwtDecoder.isExpired(_token!);
      } catch(e) {
        print("AuthService: Error al decodificar token almacenado: $e. Limpiando.");
        isTokenExpired = true;
      }

      if (!isTokenExpired) {
        try {
          await _fetchAndSetUserData(_token!); // Obtener ID y nombre de usuario
          print("AuthService: Sesión potencialmente válida para usuario $_username (ID: $_userId). Clave privada NO cargada aún.");
        } catch (e) {
           print("AuthService: Error al obtener datos /me con token: $e. Limpiando.");
           await _clearLocalSession(); // Limpiar token si /me falla
        }
      } else {
        print("AuthService: Token expirado. Limpiando.");
        await _clearLocalSession(); // Limpiar todo si el token expira
      }
    } else {
      print("AuthService: No se encontró token.");
    }
     notifyListeners();
  }

  /// Limpia el estado local (token, user data, clave en memoria) y storage.
  Future<void> _clearLocalSession() async {
      _token = null;
      _userId = null;
      _username = null;
      _sessionPrivateKey = null;
      await _storageService.deleteToken();
      // ¡NO BORRAMOS la clave privada del secure storage en este punto!
      // Podría ser un error temporal de red. Solo borramos el token.
      //await _storageService.deletePrivateKey();
  }

  /// Obtiene datos del usuario (/me) y actualiza el estado interno.
  Future<void> _fetchAndSetUserData(String token) async {
      final userData = await _userApi.getMe(token);
      _userId = (userData['id'] as num?)?.toInt();
      _username = userData['username'];
       if (_userId == null || _username == null) {
         throw Exception("Datos de usuario (/me) inválidos recibidos.");
       }
  }


  /// **REGISTRO MODIFICADO:** Guarda clave privada cifrada en backend.
  Future<bool> register(String username, String email, String password) async {
    String? generatedPrivateKey; // Guardar temporalmente para guardar localmente al final
    try {
      // 1. Generar claves RSA
      print("AuthService: Generando par de claves RSA...");
      final keyPair = await _cryptoService.generateRSAKeyPair();
      final publicKey = keyPair['publicKey']!;
      generatedPrivateKey = keyPair['privateKey']!; // Guardar la original

      if (publicKey.isEmpty || generatedPrivateKey == null || generatedPrivateKey!.isEmpty) {
        throw Exception("Claves RSA generadas vacías o nulas.");
      }
      print("AuthService: Claves RSA generadas.");

      // 2. Derivar KEK y cifrar clave privada
      print("AuthService: Derivando KEK y cifrando clave privada...");
      final saltKek = _cryptoService.generateSecureRandomSalt();
      final kekBytes = _cryptoService.deriveKeyFromPasswordPBKDF2(password, saltKek);
      final encryptedKeyData = _cryptoService.encryptAES_GCM(generatedPrivateKey!, kekBytes);
      final encryptedPrivateKeyB64 = encryptedKeyData['ciphertext']!;
      final kekIvB64 = encryptedKeyData['iv']!; // IV usado para cifrar la clave privada
      print("AuthService: Clave privada cifrada con KEK.");

      // 3. Enviar datos al backend (NUEVO ENDPOINT o modificar existente)
      // Asumiremos un endpoint modificado /api/auth/register que acepta los nuevos campos
      print("AuthService: Enviando datos de registro al backend...");
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/api/auth/register'), // O el nuevo endpoint si lo creas
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password, // El backend hará el hash para login
          'publicKey': publicKey,
          // Nuevos campos para recuperación
          'kekSalt': base64Encode(saltKek),
          'encryptedPrivateKey': encryptedPrivateKeyB64,
          'kekIv': kekIvB64,
        }),
      );

      // 4. Procesar respuesta del backend
      if (response.statusCode == 200) {
        print("AuthService: Registro exitoso en backend.");
        final Map<String, dynamic> data = json.decode(response.body);
        _token = data['token'];
        if (_token == null) throw Exception("Backend no devolvió token.");

        await _fetchAndSetUserData(_token!);
        await _storageService.saveToken(_token!);
        // Guardar la clave privada ORIGINAL (sin cifrar) localmente para la sesión actual
        await _storageService.savePrivateKey(generatedPrivateKey!);
        _sessionPrivateKey = generatedPrivateKey; // Guardar en memoria también
        print("AuthService: Token y clave privada original guardados localmente.");

        notifyListeners();
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

  /// **LOGIN MODIFICADO:** Recupera y descifra la clave privada.
  Future<bool> login(String username, String password) async {
    try {
      // 1. Llamar al endpoint de login normal
      print("AuthService: Iniciando login...");
      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      // 2. Procesar respuesta del backend
      if (response.statusCode == 200) {
        print("AuthService: Login exitoso en backend.");
        final Map<String, dynamic> data = json.decode(response.body);
        _token = data['token'];
        // --- RECUPERAR DATOS PARA DESCIFRADO ---
        // Asumimos que el backend AHORA devuelve estos campos en el login exitoso
        final kekSaltB64 = data['kekSalt'] as String?;
        final encryptedPrivateKeyB64 = data['encryptedPrivateKey'] as String?;
        final kekIvB64 = data['kekIv'] as String?;
        // ----------------------------------------

        if (_token == null || kekSaltB64 == null || encryptedPrivateKeyB64 == null || kekIvB64 == null) {
          throw Exception("Respuesta de login incompleta del backend (faltan datos de clave cifrada).");
        }
         print("AuthService: Token y datos de clave cifrada recibidos.");

        // 3. Obtener datos del usuario (/me)
        await _fetchAndSetUserData(_token!);
        print("AuthService: Datos del usuario (/me) obtenidos.");

        // 4. Re-derivar KEK y descifrar clave privada RSA
        print("AuthService: Derivando KEK y descifrando clave privada...");
        final saltKek = base64Decode(kekSaltB64);
        final kekBytes = _cryptoService.deriveKeyFromPasswordPBKDF2(password, saltKek);
        final privateKey = _cryptoService.decryptAES_GCM(encryptedPrivateKeyB64, kekBytes, kekIvB64);
        print("AuthService: Clave privada descifrada con éxito.");

        // 5. Guardar token y clave privada DESCIFRADA localmente
        await _storageService.saveToken(_token!);
        await _storageService.savePrivateKey(privateKey);
        _sessionPrivateKey = privateKey; // Guardar en memoria
        print("AuthService: Token y clave privada descifrada guardados localmente.");

        notifyListeners();
        return true;
      } else {
        print("AuthService ERROR al iniciar sesión (Backend): ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("AuthService ERROR al iniciar sesión (General): $e");
      // Si falla el login, limpiar cualquier estado residual
      await _clearLocalSession();
      notifyListeners(); // Notificar que la autenticación falló
      return false;
    }
  }

  /// Carga la clave privada desde SecureStorage si aún no está en memoria.
  /// Se usa antes de entrar a un chat.
  Future<String?> getPrivateKeyForSession() async {
    if (_sessionPrivateKey != null) {
      return _sessionPrivateKey;
    }
    print("AuthService: Cargando clave privada desde storage para la sesión...");
    _sessionPrivateKey = await _storageService.getPrivateKey();
    if (_sessionPrivateKey == null) {
       print("AuthService: No se encontró clave privada en storage.");
       // Podríamos intentar recuperarla si el token aún es válido? No con este modelo.
    } else {
       print("AuthService: Clave privada cargada desde storage.");
    }
    return _sessionPrivateKey;
  }


  /// **LOGOUT MODIFICADO:** Limpia también la clave en memoria.
  Future<void> logout() async {
    print("AuthService: Cerrando sesión...");
    _token = null;
    _userId = null;
    _username = null;
    _sessionPrivateKey = null; // Limpiar clave en memoria
    await _storageService.deleteToken();
    await _storageService.deletePrivateKey(); // Limpiar clave en storage
    notifyListeners();
    print("AuthService: Sesión cerrada y datos locales eliminados.");
  }
}