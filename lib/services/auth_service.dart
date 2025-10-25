// lib/services/auth_service.dart

import 'dart:convert'; // Para base64Encode/Decode
import 'dart:typed_data'; // Para Uint8List
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http; // <-- YA NO SE USA http DIRECTAMENTE
import 'package:jwt_decoder/jwt_decoder.dart';
// import '../config/app_constants.dart'; // <-- YA NO SE USA AppConstants DIRECTAMENTE
import 'secure_storage.dart';
import 'crypto_service.dart';
import '../api/user_api.dart'; // Aún necesitamos UserApi para /me
import '../api/auth_api.dart'; // <-- ¡IMPORTAMOS LA API ACTUALIZADA!

/// Mi servicio central para manejar todo lo relacionado con la autenticación.
/// Utiliza ChangeNotifier para notificar a la UI sobre cambios en el estado de autenticación.
class AuthService with ChangeNotifier {
  // Mis ayudantes: Api de autenticación, almacenamiento, cripto, api de usuario
  final AuthApi _authApi = AuthApi(); // <-- USAMOS AuthApi
  final SecureStorageService _storageService = SecureStorageService();
  final CryptoService _cryptoService = CryptoService();
  final UserApi _userApi = UserApi(); // Para obtener datos del usuario post-login/registro

  // Estado interno de la sesión
  String? _token;
  int? _userId;
  String? _username;

  // Clave privada RSA en memoria para la sesión actual (después de login/registro)
  // La guardo aquí para no tener que leerla del storage a cada rato.
  String? _sessionPrivateKey;

  // Getters públicos para que la UI acceda al estado.
  String? get token => _token;
  int? get userId => _userId;
  String? get username => _username;

  /// Verifica si hay un token y si no ha expirado.
  /// Maneja posibles errores al decodificar un token corrupto.
  bool get isAuthenticated {
     try {
       // Hay token Y no está expirado? Entonces sí está autenticado.
       return _token != null && !JwtDecoder.isExpired(_token!);
     } catch (e) {
       // Si el token está malformado, JwtDecoder.isExpired lanza error. Lo considero no autenticado.
       print("AuthService: Error al decodificar token en isAuthenticated: $e");
       return false;
     }
  }

  /// Intenta cargar el token almacenado y validar la sesión al inicio de la app.
  /// Obtiene los datos del usuario (/me) si el token es válido.
  /// NO carga la clave privada aquí; eso se hace en login o bajo demanda.
  Future<void> init() async {
    print("AuthService: Iniciando... Intentando cargar token.");
    _token = await _storageService.getToken(); // Intenta leer del storage

    if (_token != null) {
      print("AuthService: Token encontrado.");
      bool isTokenExpired = false;
      try {
        isTokenExpired = JwtDecoder.isExpired(_token!); // Comprueba si expiró
      } catch(e) {
        // Si el token guardado está corrupto
        print("AuthService: Error al decodificar token almacenado: $e. Limpiando.");
        isTokenExpired = true; // Tratar como expirado
      }

      if (!isTokenExpired) {
        // Si el token parece válido, intento obtener los datos del usuario
        print("AuthService: Token no expirado. Obteniendo datos /me...");
        try {
          await _fetchAndSetUserData(_token!); // Llama a /api/users/me
          print("AuthService: Sesión potencialmente válida para usuario $_username (ID: $_userId). Clave privada NO cargada aún.");
        } catch (e) {
           // Si /me falla (ej. token revocado en backend, backend caído)
           print("AuthService: Error al obtener datos /me con token: $e. Limpiando token local.");
           await _clearLocalSession(clearPrivateKey: false); // Limpiar solo token, no clave!
        }
      } else {
        // Si el token está expirado
        print("AuthService: Token expirado. Limpiando sesión local.");
        await _clearLocalSession(clearPrivateKey: true); // Limpiar todo si el token expira
      }
    } else {
      // Si no había token guardado
      print("AuthService: No se encontró token almacenado.");
    }
     // Notifica a la UI (ej. a main.dart) que la inicialización terminó.
     notifyListeners();
  }

  /// Limpia el estado local (token, user data, clave en memoria) y opcionalmente la clave del storage.
  Future<void> _clearLocalSession({required bool clearPrivateKey}) async {
      _token = null;
      _userId = null;
      _username = null;
      _sessionPrivateKey = null; // Borra la clave de la memoria
      await _storageService.deleteToken(); // Borra el token del storage

      // Borrar la clave privada del storage SOLO si es un logout explícito o el token expiró.
      // No la borramos si solo falló la llamada a /me (podría ser temporal).
      if (clearPrivateKey) {
        print("AuthService: Borrando también la clave privada del storage.");
        await _storageService.deletePrivateKey();
      } else {
        print("AuthService: Manteniendo la clave privada en el storage.");
      }
  }

  /// Obtiene datos del usuario (/api/users/me) usando el token y actualiza el estado interno.
  Future<void> _fetchAndSetUserData(String token) async {
      final userData = await _userApi.getMe(token); // Llama a la API
      // Asegurarse de convertir el ID a int correctamente
      _userId = (userData['id'] as num?)?.toInt();
      _username = userData['username'];
       // Validar que recibimos lo esperado
       if (_userId == null || _username == null) {
         throw Exception("Datos de usuario (/me) inválidos o incompletos recibidos del backend.");
       }
  }


  /// **REGISTRO REFACTORIZADO:** Usa `_authApi.register`.
  /// 1. Realiza la lógica criptográfica (generar claves, derivar KEK, cifrar privada).
  /// 2. Llama a `AuthApi.register` para enviar los datos al backend.
  /// 3. Si `AuthApi` devuelve éxito, guarda el token y la clave privada ORIGINAL localmente.
  Future<bool> register(String username, String email, String password) async {
    String? generatedPrivateKey; // Variable local temporal para guardar la clave generada
    try {
      // --- PASO 1: Lógica Criptográfica (permanece en AuthService) ---
      print("AuthService [Register]: Iniciando proceso criptográfico...");
      // Generar claves RSA
      final keyPair = await _cryptoService.generateRSAKeyPair();
      final publicKey = keyPair['publicKey']!;
      generatedPrivateKey = keyPair['privateKey']!;
      if (publicKey.isEmpty || generatedPrivateKey == null || generatedPrivateKey!.isEmpty) {
        throw Exception("Error crítico: Fallo al generar claves RSA.");
      }
      print("AuthService [Register]: Claves RSA generadas.");

      // Derivar KEK de la contraseña
      final saltKek = _cryptoService.generateSecureRandomSalt();
      final kekBytes = _cryptoService.deriveKeyFromPasswordPBKDF2(password, saltKek);
      print("AuthService [Register]: KEK derivada de la contraseña.");

      // Cifrar la clave privada con KEK (AES-GCM)
      final encryptedKeyData = _cryptoService.encryptAES_GCM(generatedPrivateKey!, kekBytes);
      final encryptedPrivateKeyB64 = encryptedKeyData['ciphertext']!;
      final kekIvB64 = encryptedKeyData['iv']!;
      print("AuthService [Register]: Clave privada cifrada con KEK.");
      // --- Fin Lógica Criptográfica ---

      // --- PASO 2: Llamada a la API (delegada a AuthApi) ---
      print("AuthService [Register]: Llamando a AuthApi.register...");
      // Pasamos todos los datos necesarios a la API
      final apiResult = await _authApi.register(
        username: username,
        email: email,
        password: password, // El backend hasheará esto
        publicKey: publicKey, // La clave pública en formato PEM
        kekSalt: base64Encode(saltKek), // El salt usado para la KEK (Base64)
        encryptedPrivateKey: encryptedPrivateKeyB64, // La clave privada cifrada (Base64)
        kekIv: kekIvB64, // El IV usado con la KEK (Base64)
      );
      // --- Fin Llamada a la API ---

      // --- PASO 3: Procesar Resultado y Guardar Estado ---
      if (apiResult['success'] == true) {
        print("AuthService [Register]: AuthApi.register reportó éxito.");
        _token = apiResult['token']; // Extraer el token de la respuesta
        if (_token == null) throw Exception("AuthApi.register tuvo éxito pero no devolvió un token.");

        // Obtener ID y username del nuevo usuario usando el token
        await _fetchAndSetUserData(_token!);
        print("AuthService [Register]: Datos del nuevo usuario obtenidos: $_username (ID: $_userId).");

        // Guardar el token y la clave privada ORIGINAL (sin cifrar) localmente
        await _storageService.saveToken(_token!);
        await _storageService.savePrivateKey(generatedPrivateKey!); // Guarda la original
        _sessionPrivateKey = generatedPrivateKey; // Guarda en memoria para esta sesión
        print("AuthService [Register]: Token y clave privada ORIGINAL guardados localmente.");

        notifyListeners(); // Notifica a la UI del cambio de estado de autenticación
        return true; // Registro exitoso
      } else {
        // Si AuthApi reportó un error (ej: usuario ya existe)
        final errorMessage = apiResult['message'] ?? 'Error desconocido durante el registro.';
        print("AuthService [Register] ERROR (desde AuthApi): $errorMessage");
        // Lanzamos la excepción para que sea capturada por el catch general
        throw Exception(errorMessage);
      }
    } catch (e) {
      // Captura errores de criptografía, red (desde AuthApi), o lógica
      print("AuthService [Register] ERROR (General): $e");
      // Es importante limpiar cualquier estado parcial si el registro falla
      await _clearLocalSession(clearPrivateKey: true); // Borrar todo en fallo de registro
      notifyListeners(); // Asegura que la UI sepa que no está autenticado
      return false; // Registro fallido
    }
  }

  /// **LOGIN REFACTORIZADO:** Usa `_authApi.login`.
  /// 1. Llama a `AuthApi.login`.
  /// 2. Si `AuthApi` devuelve éxito, extrae token y datos criptográficos.
  /// 3. Realiza la lógica criptográfica (re-derivar KEK, descifrar privada).
  /// 4. Guarda el token y la clave privada DESCIFRADA localmente.
  Future<bool> login(String username, String password) async {
    try {
      // --- PASO 1: Llamada a la API (delegada a AuthApi) ---
      print("AuthService [Login]: Llamando a AuthApi.login para $username...");
      final apiResult = await _authApi.login(username, password); // Llama a la API
      // --- Fin Llamada a la API ---

      // --- PASO 2: Procesar Resultado de la API ---
      if (apiResult['success'] == true) {
        print("AuthService [Login]: AuthApi.login reportó éxito.");
        // Extraer todos los datos devueltos por AuthApi (que los obtuvo del backend)
        _token = apiResult['token'];
        final kekSaltB64 = apiResult['kekSalt'] as String?;
        final encryptedPrivateKeyB64 = apiResult['encryptedPrivateKey'] as String?;
        final kekIvB64 = apiResult['kekIv'] as String?;

        // Validar que recibimos todo lo necesario para descifrar la clave
        if (_token == null || kekSaltB64 == null || encryptedPrivateKeyB64 == null || kekIvB64 == null) {
          throw Exception("Respuesta de login incompleta recibida de AuthApi (faltan datos criptográficos).");
        }
        print("AuthService [Login]: Token y datos de clave cifrada recibidos.");

        // Obtener ID y username usando el nuevo token
        await _fetchAndSetUserData(_token!);
        print("AuthService [Login]: Datos del usuario (/me) obtenidos: $_username (ID: $_userId).");

        // --- PASO 3: Lógica Criptográfica (permanece en AuthService) ---
        print("AuthService [Login]: Re-derivando KEK y descifrando clave privada RSA...");
        // Decodificar el salt recibido
        final saltKek = base64Decode(kekSaltB64);
        // Re-derivar la KEK usando la contraseña ingresada y el salt
        final kekBytes = _cryptoService.deriveKeyFromPasswordPBKDF2(password, saltKek);
        // Descifrar la clave privada usando la KEK y el IV recibidos (AES-GCM)
        final privateKey = _cryptoService.decryptAES_GCM(encryptedPrivateKeyB64, kekBytes, kekIvB64);
        print("AuthService [Login]: Clave privada RSA descifrada.");
        // Validar que la clave descifrada no esté vacía
        if (privateKey.isEmpty) {
          // Esto podría indicar contraseña incorrecta si el descifrado falla silenciosamente,
          // o un problema grave si la clave guardada estaba corrupta.
          throw Exception("Error crítico: La clave privada descifrada está vacía. ¿Contraseña incorrecta?");
        }
        // --- Fin Lógica Criptográfica ---

        // --- PASO 4: Guardar Estado Local ---
        // Guardar el token y la clave privada DESCIFRADA localmente
        await _storageService.saveToken(_token!);
        await _storageService.savePrivateKey(privateKey); // Guarda la clave descifrada
        _sessionPrivateKey = privateKey; // Guarda también en memoria para la sesión
        print("AuthService [Login]: Token y clave privada descifrada guardados localmente.");

        notifyListeners(); // Notifica a la UI del cambio de estado
        return true; // Login exitoso
      } else {
        // Si AuthApi reportó un error (ej. credenciales incorrectas)
        final errorMessage = apiResult['message'] ?? 'Error desconocido durante el login.';
        print("AuthService [Login] ERROR (desde AuthApi): $errorMessage");
        // Lanzar la excepción para el catch general
        throw Exception(errorMessage);
      }
    } catch (e) {
      // Captura errores de red (AuthApi), criptográficos, o de lógica
      print("AuthService [Login] ERROR (General): $e");
      // Limpiar sesión local si falla el login (más seguro borrar todo)
      await _clearLocalSession(clearPrivateKey: true);
      notifyListeners(); // Asegura que la UI sepa que falló
      return false; // Login fallido
    }
  }

  /// Carga la clave privada desde SecureStorage si aún no está en memoria.
  /// Se usa típicamente antes de entrar a un chat o realizar una operación criptográfica.
  Future<String?> getPrivateKeyForSession() async {
    // Si ya la tenemos en memoria, la devolvemos directamente.
    if (_sessionPrivateKey != null) {
      print("AuthService [getPrivateKeyForSession]: Usando clave privada en memoria.");
      return _sessionPrivateKey;
    }
    // Si no, intentamos cargarla desde el almacenamiento seguro.
    print("AuthService [getPrivateKeyForSession]: Cargando clave privada desde storage...");
    _sessionPrivateKey = await _storageService.getPrivateKey();
    if (_sessionPrivateKey == null) {
       print("AuthService [getPrivateKeyForSession]: ADVERTENCIA: No se encontró clave privada en storage.");
       // Esto es un estado potencialmente problemático. La UI (ChatScreen) debería manejarlo.
    } else {
       print("AuthService [getPrivateKeyForSession]: Clave privada cargada desde storage.");
    }
    return _sessionPrivateKey;
  }


  /// **LOGOUT:** Limpia el estado, el token y la clave privada de memoria y storage.
  Future<void> logout() async {
    print("AuthService: Cerrando sesión...");
    await _clearLocalSession(clearPrivateKey: true); // Asegura borrar todo
    notifyListeners(); // Notifica a la UI para redirigir a LoginScreen
    print("AuthService: Sesión cerrada y datos locales eliminados.");
  }

} // Fin AuthService