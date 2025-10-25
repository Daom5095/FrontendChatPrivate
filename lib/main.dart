// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; // <-- 1. IMPORTAR Google Fonts
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
    return ChangeNotifierProvider.value(
      value: _authService,
      child: Consumer<AuthService>(
        builder: (ctx, auth, _) {
          return MaterialApp(
            title: 'Chat Privado Seguro',
            debugShowCheckedModeBanner: false,

            // --- 2. CONFIGURACIÓN DEL TEMA VISUAL ---
            theme: ThemeData(
              // **Paleta de Colores**
              primarySwatch: Colors.deepPurple, // Mantenemos la base
              primaryColor: Colors.deepPurple[800], // Tono oscuro para elementos principales
              hintColor: Colors.teal[400], // Color de acento (secundario)
              scaffoldBackgroundColor: const Color(0xFFF8F8FA), // Fondo principal grisáceo claro
              cardColor: Colors.white, // Color para cards, diálogos, etc.
              dividerColor: Colors.grey[300], // Color para separadores

              // **Tipografía usando Google Fonts (Lato)**
              // Asegúrate de haber ejecutado: flutter pub add google_fonts
              textTheme: GoogleFonts.latoTextTheme( // Aplicar Lato a todo el texto
                Theme.of(context).textTheme, // Usar estilos base del tema
              ).copyWith( // Ajustes específicos
                 titleLarge: GoogleFonts.lato(fontWeight: FontWeight.bold), // Títulos grandes en negrita
                 headlineSmall: GoogleFonts.lato(fontWeight: FontWeight.bold), // Títulos más pequeños
                 bodyMedium: GoogleFonts.lato(fontSize: 15), // Tamaño base del cuerpo
              ),

              // **Estilos Específicos de Widgets**
              appBarTheme: AppBarTheme(
                backgroundColor: Colors.deepPurple[800], // Fondo oscuro
                foregroundColor: Colors.white, // Texto e iconos blancos
                elevation: 1, // Sombra sutil
                titleTextStyle: GoogleFonts.lato( // Fuente específica para AppBar
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),

              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple[700], // Color de fondo del botón
                  foregroundColor: Colors.white, // Color del texto del botón
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20), // Botones redondeados
                  ),
                ),
              ),

              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: Colors.teal[400], // Color de acento
                foregroundColor: Colors.white, // Icono blanco
              ),

              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.grey[150], // Fondo ligero para campos de texto
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none, // Sin borde por defecto
                ),
                focusedBorder: OutlineInputBorder( // Borde al enfocar
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.deepPurple[700]!, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),

              listTileTheme: ListTileThemeData(
                 iconColor: Colors.deepPurple[700], // Color para iconos en listas
              ),

               visualDensity: VisualDensity.adaptivePlatformDensity, // Ajuste visual
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