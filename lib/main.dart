// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; // Para las fuentes personalizadas
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';

void main() {
  // Punto de entrada principal de la aplicación Flutter.
  runApp(const MyApp());
}

/// El widget raíz de mi aplicación.
/// Es un StatefulWidget para poder manejar la inicialización de servicios.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Instancia única de mi servicio de autenticación.
  final AuthService _authService = AuthService();
  // Un Future que representa la inicialización del servicio (cargar token, etc.)
  late final Future<void> _initAuthFuture;

  @override
  void initState() {
    super.initState();
    print("MyApp [initState]: Iniciando AuthService...");
    // Llamo al método init() de AuthService. Este intentará cargar un token
    // almacenado para ver si ya hay una sesión activa.
    _initAuthFuture = _authService.init();
    print("MyApp [initState]: Llamada a AuthService.init() realizada.");
  }

  @override
  Widget build(BuildContext context) {
    
    // --- Defino mi paleta de colores personalizada ---
    // (Basada en el logo y un estilo moderno)
    const Color primaryBlue = Color(0xFF23518C);      // Azul medio vibrante
    const Color accentPeriwinkle = Color(0xFF899DD9); // Azul lavanda claro
    const Color textAlmostBlack = Color(0xFF0D1826);   // Azul muy oscuro (casi negro)
    const Color textMutedBlueGrey = Color(0xFF8F9FBF); // Gris azulado apagado
    // --- FIN PALETA ---

    // ChangeNotifierProvider expone mi AuthService al árbol de widgets.
    // Usamos .value porque la instancia ya fue creada (_authService).
    return ChangeNotifierProvider.value(
      value: _authService,
      child: Consumer<AuthService>(
        // Consumer reconstruye la app cuando AuthService llama a notifyListeners()
        // (por ejemplo, después de login o logout).
        builder: (ctx, auth, _) {
          return MaterialApp(
            title: 'Chat Privado Seguro',
            debugShowCheckedModeBanner: false, // Oculto el banner de "Debug"

            // --- --------------------------------- ---
            // --- INICIO DE CONFIGURACIÓN DEL TEMA  ---
            // --- --------------------------------- ---
            theme: ThemeData(
              // **Paleta de Colores**
              primarySwatch: Colors.blue, // Base genérica
              primaryColor: primaryBlue, // El azul medio es el primario
              primaryColorDark: textAlmostBlack, // El más oscuro para iconos sobre acento
              hintColor: accentPeriwinkle, // El lavanda es el acento
              scaffoldBackgroundColor: Colors.white, // Fondo blanco
              cardColor: Colors.white, 
              dividerColor: Colors.grey[200], // Un gris neutro claro

              // **Tipografía (Usando Google Fonts - Lato)**
              textTheme: GoogleFonts.latoTextTheme( 
                Theme.of(context).textTheme,
              ).copyWith( 
                 // Títulos de Login/Registro
                 headlineMedium: GoogleFonts.lato(fontWeight: FontWeight.bold, color: primaryBlue),
                 // Subtítulos de Login/Registro
                 titleMedium: GoogleFonts.lato(color: textMutedBlueGrey),
                 // Títulos grandes (ej. "Mis Chats")
                 titleLarge: GoogleFonts.lato(fontWeight: FontWeight.bold, color: textAlmostBlack),
                 // Títulos más pequeños
                 headlineSmall: GoogleFonts.lato(fontWeight: FontWeight.bold, color: primaryBlue),
                 // Texto de cuerpo
                 bodyMedium: GoogleFonts.lato(fontSize: 15, color: textAlmostBlack),
                 // Texto de subtítulos (ej. hora en burbuja de chat)
                 bodySmall: GoogleFonts.lato(color: textMutedBlueGrey),
              ),

              // **Estilos Específicos de Widgets**
              appBarTheme: AppBarTheme(
                backgroundColor: Colors.white, // AppBar blanca
                foregroundColor: textAlmostBlack, // Iconos y texto en el color más oscuro
                elevation: 1, // Sombra sutil
                titleTextStyle: GoogleFonts.lato(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textAlmostBlack),
              ),

              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue, // Botones con el azul primario
                  foregroundColor: Colors.white, // Texto blanco
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), 
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25), // Bordes redondeados
                  ),
                ),
              ),

              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: accentPeriwinkle, // FAB con el azul acento
                foregroundColor: textAlmostBlack, // Icono en el color más oscuro
              ),

              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white, 
                // Color del texto "Nombre de usuario", "Contraseña", etc.
                labelStyle: const TextStyle(color: textMutedBlueGrey),
                hintStyle: const TextStyle(color: textMutedBlueGrey), // Para el hint en la barra de chat
                
                border: OutlineInputBorder( 
                  borderRadius: BorderRadius.circular(25), 
                  borderSide: const BorderSide(color: textMutedBlueGrey), // Borde gris-azulado
                ),
                focusedBorder: OutlineInputBorder( 
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: primaryBlue, width: 1.5), // Borde azul primario al enfocar
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),

              // Para los links "Regístrate aquí"
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: primaryBlue, // Color azul primario
                )
              ),

              listTileTheme: ListTileThemeData(
                 iconColor: primaryBlue, // Iconos en listas
              ),

               visualDensity: VisualDensity.adaptivePlatformDensity, 
            ),
            // --- ------------------------------- ---
            // --- FIN CONFIGURACIÓN DEL TEMA      ---
            // --- ------------------------------- ---

            // --- Lógica de Navegación Inicial ---
            home: FutureBuilder(
              // Espero a que el Future _initAuthFuture (AuthService.init()) termine
              future: _initAuthFuture,
              builder: (context, snapshot) {
                
                // 1. Mientras está cargando (esperando a init())
                if (snapshot.connectionState == ConnectionState.waiting) {
                  print("MyApp [FutureBuilder]: AuthService.init() en progreso. Mostrando SplashScreen.");
                  return const SplashScreen(); // Muestro pantalla de carga
                }

                // 2. Si init() falló (muy raro, pero posible)
                if (snapshot.hasError) {
                   print("MyApp [FutureBuilder]: ERROR durante AuthService.init(): ${snapshot.error}. Mostrando LoginScreen como fallback.");
                   // Muestro Login como fallback seguro
                   return const LoginScreen();
                }

                // 3. Cuando init() termina (con o sin sesión válida)
                print("MyApp [FutureBuilder]: AuthService.init() completado. Estado Auth: ${auth.isAuthenticated}");
                // Reviso el estado de `auth` (gracias al Consumer) para decidir qué pantalla mostrar.
                return auth.isAuthenticated
                    ? const HomeScreen()   // Si está autenticado, voy al Home
                    : const LoginScreen(); // Si no, voy al Login
              },
            ),
          );
        },
      ),
    );
  }
}