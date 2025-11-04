// lib/services/auth_service.dart

import 'dart:convert'; // Para base64Encode/Decode
import 'dart:typed_data'; // Para Uint8List
import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'secure_storage.dart';
import 'crypto_service.dart';
import '../api/user_api.dart'; 
import '../api/auth_api.dart'; 

/// Mi servicio central para manejar todo lo relacionado con la autenticación.
///
/// Utiliza `ChangeNotifier` (de Provider) para notificar a la UI
/// (específicamente a `main.dart`) sobre cambios en el estado de autenticación
/// (ej. login o logout).
///
/// Esta clase orquesta la lógica de negocio, llamando a:
/// - `AuthApi` y `UserApi` para la comunicación de red.
/// - `CryptoService` para las operaciones criptográficas.
/// - `SecureStorageService` para persistir la sesión.
class AuthService with ChangeNotifier {
  // --- Mis Ayudantes ---
  /// El cliente API para endpoints /api/auth
  final AuthApi _authApi = AuthApi();
  /// Mi wrapper para FlutterSecureStorage
  final SecureStorageService _storageService = SecureStorageService();
  /// Mi caja de herramientas criptográficas
  final CryptoService _cryptoService = CryptoService();
  /// El cliente API para endpoints /api/users
  final UserApi _userApi = UserApi(); // Para obtener datos del usuario post-login/registro

  // --- Estado Interno de la Sesión ---
  /// El token JWT, `null` si no está autenticado.
  String? _token;
  /// El ID del usuario actual.
  int? _userId;
  /// El nombre del usuario actual.
  String? _username;

  /// La clave privada RSA (en formato PEM) del usuario.
  /// La guardo aquí en memoria *después* del login/registro para
  /// no tener que leerla del `SecureStorage` (que es lento)
  /// cada vez que necesite descifrar un mensaje.
  String? _sessionPrivateKey;

  // --- Getters Públicos ---
  /// Devuelve el token JWT actual.
  String? get token => _token;
  /// Devuelve el ID del usuario actual.
  int? get userId => _userId;
  /// Devuelve el nombre del usuario actual.
  String? get username => _username;

  /// Verifica si hay un token y si no ha expirado.
  ///
  /// Maneja posibles errores al decodificar un token corrupto.
  /// La UI escucha este getter (indirectamente vía Consumer)
  /// para decidir si muestra `LoginScreen` o `HomeScreen`.
  bool get isAuthenticated {
     try {
       // Hay token Y no está expirado? Entonces sí está autenticado.
       return _token != null && !JwtDecoder.isExpired(_token!);
     } catch (e) {
       // Si el token está malformado, JwtDecoder.isExpired lanza error.
       // Lo considero no autenticado.
       print("AuthService: Error al decodificar token en isAuthenticated: $e");
       return false;
     }
  }

  /// Intenta cargar el token almacenado y validar la sesión al inicio de la app.
  ///
  /// Este método es llamado por `main.dart` al arrancar.
  /// 1. Intenta leer el token del `SecureStorage`.
  /// 2. Si existe y no está expirado, llama a `_fetchAndSetUserData` (GET /api/users/me).
  /// 3. Si `_fetchAndSetUserData` falla (ej. token revocado), limpia el token local.
  /// 4. Si el token está expirado o no existe, simplemente no hace nada.
  /// 5. Finalmente, notifica a los listeners (main.dart) que la inicialización terminó.
  ///
  /// **Importante:** NO carga la clave privada aquí; eso se hace solo
  /// durante `login` o `register`, o bajo demanda (`getPrivateKeyForSession`).
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
           // Limpiamos la sesión local, PERO mantenemos la clave privada en el storage.
           // El fallo de /me podría ser temporal, y si el usuario vuelve a hacer login
           // (con la contraseña correcta), podrá descifrar su clave.
           await _clearLocalSession(clearPrivateKey: false);
        }
      } else {
        // Si el token está expirado
        print("AuthService: Token expirado. Limpiando sesión local.");
        // Si el token expira, es más seguro borrar todo, incluida la clave.
        await _clearLocalSession(clearPrivateKey: true);
      }
    } else {
      // Si no había token guardado
      print("AuthService: No se encontró token almacenado.");
    }
     // Notifica a la UI (ej. a main.dart) que la inicialización terminó.
     // Esto hará que el FutureBuilder en main.dart se resuelva.
     notifyListeners();
  }

  /// Limpia el estado local (token, user data, clave en memoria) y opcionalmente la clave del storage.
  ///
  /// - `clearPrivateKey`:
  ///   - `true`: Borra todo (logout, registro fallido, token expirado).
  ///   - `false`: Borra token y sesión en memoria, pero MANTIENE la clave privada
  ///     en `SecureStorage` (ej. fallo temporal de /me).
  Future<void> _clearLocalSession({required bool clearPrivateKey}) async {
      _token = null;
      _userId = null;
      _username = null;
      _sessionPrivateKey = null; // Borra la clave de la memoria
      await _storageService.deleteToken(); // Borra el token del storage

      if (clearPrivateKey) {
        print("AuthService: Borrando también la clave privada del storage.");
        await _storageService.deletePrivateKey();
      } else {
        print("AuthService: Manteniendo la clave privada en el storage.");
      }
  }

  /// Obtiene datos del usuario (GET /api/users/me) usando el token y actualiza el estado interno.
  Future<void> _fetchAndSetUserData(String token) async {
      // Llama a la API
      final userData = await _userApi.getMe(token);
      
      // Asegurarse de convertir el ID a int correctamente
      _userId = (userData['id'] as num?)?.toInt();
      _username = userData['username'];
      
       // Validar que recibimos lo esperado
       if (_userId == null || _username == null) {
         throw Exception("Datos de usuario (/me) inválidos o incompletos recibidos del backend.");
       }
  }


  /// **Lógica de REGISTRO (Refactorizada).**
  ///
  /// Orquesta todo el proceso de registro:
  /// 1. **Criptografía (Local):**
  ///    - Genera un nuevo par de claves RSA (`_cryptoService.generateRSAKeyPair`).
  ///    - Genera un `saltKek` aleatorio.
  ///    - Deriva la KEK (Key Encryption Key) desde la `password` y `saltKek` (`_cryptoService.deriveKeyFromPasswordPBKDF2`).
  ///    - Cifra la nueva clave privada RSA con la KEK (`_cryptoService.encryptAES_GCM`).
  /// 2. **Llamada a API (Red):**
  ///    - Llama a `_authApi.register` enviando *todo* al backend (username, email, pass,
  ///      publicKey, kekSalt, encryptedPrivateKey, kekIv).
  /// 3. **Procesar Éxito (Local):**
  ///    - Si la API devuelve éxito (`success: true` y un `token`):
  ///    - Guarda el nuevo `_token` en estado y storage.
  ///    - Llama a `_fetchAndSetUserData` para obtener el ID y username del nuevo usuario.
  ///    - Guarda la clave privada **ORIGINAL** (sin cifrar) en `_sessionPrivateKey` y en `SecureStorage`.
  ///    - Notifica a la UI (via `notifyListeners`) que el estado de auth cambió.
  /// 4. **Procesar Fallo:**
  ///    - Si algo falla (cripto, red, o la API devuelve `success: false`),
  ///      captura la excepción, limpia *toda* la sesión (`_clearLocalSession(clearPrivateKey: true)`)
  ///      y devuelve `false`.
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

  /// **Lógica de LOGIN (Refactorizada).**
  ///
  /// Orquesta todo el proceso de login:
  /// 1. **Llamada a API (Red):**
  ///    - Llama a `_authApi.login` (username, password).
  /// 2. **Procesar Respuesta API:**
  ///    - Si la API devuelve éxito (`success: true`), extrae el `token` y
  ///      los datos criptográficos (`kekSalt`, `encryptedPrivateKey`, `kekIv`).
  ///    - Llama a `_fetchAndSetUserData` para obtener ID y username.
  /// 3. **Criptografía (Local):**
  ///    - Re-deriva la KEK usando la `password` ingresada y el `kekSalt` recibido
  ///      (`_cryptoService.deriveKeyFromPasswordPBKDF2`).
  ///    - Descifra la `encryptedPrivateKey` usando la KEK y el `kekIv`
  ///      (`_cryptoService.decryptAES_GCM`).
  /// 4. **Guardar Estado (Local):**
  ///    - Si el descifrado es exitoso, guarda el `_token` y la clave privada
  ///      **DESCIFRADA** en `_sessionPrivateKey` y en `SecureStorage`.
  ///    - Notifica a la UI (via `notifyListeners`).
  /// 5. **Procesar Fallo:**
  ///    - Si algo falla (red, API, o descifrado), captura la excepción,
  ///      limpia *toda* la sesión (`_clearLocalSession(clearPrivateKey: true)`)
  ///      y devuelve `false`.
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
          // Si el descifrado falla (ej. contraseña incorrecta), decryptAES_GCM
          // lanzará un error que será capturado por el catch general.
          // Esta validación es una doble seguridad.
          throw Exception("Error crítico: La clave privada descifrada está vacía.");
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
      // Captura errores de red (AuthApi), criptográficos (contraseña incorrecta), o de lógica
      print("AuthService [Login] ERROR (General): $e");
      // Limpiar sesión local si falla el login (más seguro borrar todo)
      await _clearLocalSession(clearPrivateKey: true);
      notifyListeners(); // Asegura que la UI sepa que falló
      return false; // Login fallido
    }
  }

  /// Carga la clave privada desde SecureStorage si aún no está en memoria.
  ///
  /// Se usa típicamente antes de entrar a un chat (`HomeScreen`, `ChatScreen`)
  /// para asegurarse de que la clave esté disponible para descifrar mensajes.
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
       // Esto es un estado potencialmente problemático.
       // La UI (ChatScreen) debe manejar este null y mostrar un error.
    } else {
       print("AuthService [getPrivateKeyForSession]: Clave privada cargada desde storage.");
    }
    return _sessionPrivateKey;
  }


  /// **LOGOUT:** Limpia el estado, el token y la clave privada de memoria y storage.
  ///
  /// Llama a `_clearLocalSession` forzando el borrado de la clave privada.
  Future<void> logout() async {
    print("AuthService: Cerrando sesión...");
    await _clearLocalSession(clearPrivateKey: true); // Asegura borrar todo
    notifyListeners(); // Notifica a la UI para redirigir a LoginScreen
    print("AuthService: Sesión cerrada y datos locales eliminados.");
  }

} 