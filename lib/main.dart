// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; // 1. IMPORTAR Google Fonts
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  late final Future<void> _initAuthFuture;

  @override
  void initState() {
    super.initState();
    print("MyApp [initState]: Iniciando AuthService...");
    _initAuthFuture = _authService.init();
    print("MyApp [initState]: Llamada a AuthService.init() realizada.");
  }

  @override
  Widget build(BuildContext context) {
    
    // --- NUEVA PALETA DE COLORES (BASADA EN TU IMAGEN) ---
    const Color primaryBlue = Color(0xFF23518C);      // Azul medio vibrante
    const Color accentPeriwinkle = Color(0xFF899DD9); // Azul lavanda claro
    const Color textAlmostBlack = Color(0xFF0D1826);   // Azul muy oscuro (casi negro)
    const Color textMutedBlueGrey = Color(0xFF8F9FBF); // Gris azulado apagado
    // --- FIN PALETA ---

    return ChangeNotifierProvider.value(
      value: _authService,
      child: Consumer<AuthService>(
        builder: (ctx, auth, _) {
          return MaterialApp(
            title: 'Chat Privado Seguro',
            debugShowCheckedModeBanner: false,

            // --- 2. CONFIGURACIÓN DEL TEMA VISUAL (ACTUALIZADA) ---
            theme: ThemeData(
              // **Paleta de Colores**
              primarySwatch: Colors.blue, // Base genérica
              primaryColor: primaryBlue, // El azul medio es el primario
              primaryColorDark: textAlmostBlack, // El más oscuro para iconos sobre acento
              hintColor: accentPeriwinkle, // El lavanda es el acento
              scaffoldBackgroundColor: Colors.white, // Fondo blanco
              cardColor: Colors.white, 
              dividerColor: Colors.grey[200], // Un gris neutro claro

              // **Tipografía (Lato)**
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
                elevation: 1, 
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
                    borderRadius: BorderRadius.circular(25),
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
            // --- FIN CONFIGURACIÓN DEL TEMA ---

            // --- Lógica de Navegación Inicial (sin cambios) ---
            home: FutureBuilder(
              future: _initAuthFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  print("MyApp [FutureBuilder]: AuthService.init() en progreso. Mostrando SplashScreen.");
                  return const SplashScreen();
                }
                if (snapshot.hasError) {
                   print("MyApp [FutureBuilder]: ERROR durante AuthService.init(): ${snapshot.error}. Mostrando LoginScreen como fallback.");
                   return const LoginScreen();
                }
                print("MyApp [FutureBuilder]: AuthService.init() completado. Estado Auth: ${auth.isAuthenticated}");
                return auth.isAuthenticated
                    ? const HomeScreen()
                    : const LoginScreen();
              },
            ),
          );
        },
      ),
    );
  }
}