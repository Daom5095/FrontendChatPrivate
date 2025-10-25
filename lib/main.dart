// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/auth/login_screen.dart';   // Pantalla de inicio de sesión
import 'screens/home/home_screen.dart';     // Pantalla principal (lista de chats)
import 'screens/splash_screen.dart'; // Pantalla de carga inicial
import 'services/auth_service.dart';     // Nuestro servicio de autenticación

// Punto de entrada principal de la aplicación Flutter
void main() {
  // WidgetsFlutterBinding.ensureInitialized(); // No es necesario aquí aún
  runApp(const MyApp()); // Ejecuta el widget raíz
}

/// El widget raíz de la aplicación. Es StatefulWidget para manejar
/// la inicialización asíncrona de AuthService.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Guardamos la instancia de AuthService aquí para que persista durante toda la vida de la app.
  final AuthService _authService = AuthService();

  // Guardamos el Future devuelto por _authService.init() para pasarlo al FutureBuilder.
  // 'late final' asegura que se inicialice una vez en initState y no cambie.
  late final Future<void> _initAuthFuture;

  @override
  void initState() {
    super.initState();
    print("MyApp [initState]: Iniciando AuthService...");
    // Llamamos a init UNA SOLA VEZ aquí y guardamos la 'promesa'.
    _initAuthFuture = _authService.init();
    print("MyApp [initState]: Llamada a AuthService.init() realizada.");
  }

  @override
  Widget build(BuildContext context) {
    // Usamos ChangeNotifierProvider.value porque ya creamos la instancia _authService arriba.
    // Esto hace que _authService esté disponible para todos los widgets descendientes.
    return ChangeNotifierProvider.value(
      value: _authService,
      // Consumer escucha los cambios en AuthService (ej. cuando isAuthenticated cambia después de login/logout)
      // aunque aquí lo usamos principalmente para acceder a 'auth.isAuthenticated' después del FutureBuilder.
      child: Consumer<AuthService>(
        builder: (ctx, auth, _) {
          // MaterialApp es la base de nuestra aplicación visual.
          return MaterialApp(
            title: 'Chat Privado Seguro', // Título de la app
            theme: ThemeData( // Tema visual básico
              primarySwatch: Colors.deepPurple, // Color principal
              visualDensity: VisualDensity.adaptivePlatformDensity, // Ajuste visual
              // Podríamos definir más estilos aquí (botones, appbar, etc.)
            ),
            debugShowCheckedModeBanner: false, // Ocultar banner de debug
            // La pantalla principal ('home') se decide de forma asíncrona.
            home: FutureBuilder(
              // El Future que estamos esperando es el resultado de AuthService.init()
              future: _initAuthFuture,
              // El builder se llama cada vez que el estado del Future cambia (esperando, error, completado)
              builder: (context, snapshot) {
                // Mientras esperamos que AuthService.init() termine...
                if (snapshot.connectionState == ConnectionState.waiting) {
                   print("MyApp [FutureBuilder]: AuthService.init() en progreso. Mostrando SplashScreen.");
                  // ...mostramos la pantalla de carga.
                  return const SplashScreen();
                }
                // Si hubo un error durante AuthService.init() (poco probable si se maneja bien dentro)
                if (snapshot.hasError) {
                   print("MyApp [FutureBuilder]: ERROR durante AuthService.init(): ${snapshot.error}. Mostrando LoginScreen como fallback.");
                   // Podríamos mostrar una pantalla de error aquí, pero ir a Login es seguro.
                   // return ErrorScreen(error: snapshot.error);
                   return const LoginScreen(); // Fallback seguro
                }

                // Si AuthService.init() terminó con éxito:
                print("MyApp [FutureBuilder]: AuthService.init() completado. Estado Auth: ${auth.isAuthenticated}");
                // Verificamos si el usuario está autenticado (según AuthService)
                // y mostramos la pantalla correspondiente.
                return auth.isAuthenticated
                    ? const HomeScreen()    // Si está autenticado -> Pantalla principal
                    : const LoginScreen();   // Si no -> Pantalla de login
              },
            ), // Fin FutureBuilder
          ); // Fin MaterialApp
        },
      ), // Fin Consumer
    ); // Fin ChangeNotifierProvider
  }
} // Fin _MyAppState