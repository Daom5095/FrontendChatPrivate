// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_state_service.dart'; // <-- IMPORTAR EL NUEVO SERVICIO

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
  // --- AÑADIR EL NUEVO SERVICIO ---
  final ChatStateService _chatStateService = ChatStateService();
  late final Future<void> _initAuthFuture;

  @override
  void initState() {
    super.initState();
    print("MyApp [initState]: Iniciando AuthService...");
    _initAuthFuture = _authService.init();
    print("MyApp [initState]: Llamada a AuthService.init() realizada.");
  }

  // --- AÑADIR DISPOSE ---
  @override
  void dispose() {
    _authService.dispose();
    _chatStateService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    
    // ... (toda la paleta de colores no cambia) ...
    const Color primaryBlue = Color(0xFF23518C);
    const Color accentPeriwinkle = Color(0xFF899DD9);
    const Color textAlmostBlack = Color(0xFF0D1826);
    const Color textMutedBlueGrey = Color(0xFF8F9FBF);

    // --- MODIFICACIÓN: USAR MULTIPROVIDER ---
    // En lugar de un solo ChangeNotifierProvider, usamos MultiProvider
    // para proveer tanto AuthService como ChatStateService.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authService),
        ChangeNotifierProvider.value(value: _chatStateService),
      ],
      // --- FIN MODIFICACIÓN ---

      child: Consumer<AuthService>(
        builder: (ctx, auth, _) {
          return MaterialApp(
            title: 'Chat Privado Seguro',
            debugShowCheckedModeBanner: false,

            // ... (todo el ThemeData no cambia) ...
            theme: ThemeData(
              primarySwatch: Colors.blue,
              primaryColor: primaryBlue,
              primaryColorDark: textAlmostBlack,
              hintColor: accentPeriwinkle,
              scaffoldBackgroundColor: Colors.white,
              cardColor: Colors.white, 
              dividerColor: Colors.grey[200],
              textTheme: GoogleFonts.latoTextTheme( 
                Theme.of(context).textTheme,
              ).copyWith( 
                 headlineMedium: GoogleFonts.lato(fontWeight: FontWeight.bold, color: primaryBlue),
                 titleMedium: GoogleFonts.lato(color: textMutedBlueGrey),
                 titleLarge: GoogleFonts.lato(fontWeight: FontWeight.bold, color: textAlmostBlack),
                 headlineSmall: GoogleFonts.lato(fontWeight: FontWeight.bold, color: primaryBlue),
                 bodyMedium: GoogleFonts.lato(fontSize: 15, color: textAlmostBlack),
                 bodySmall: GoogleFonts.lato(color: textMutedBlueGrey),
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: Colors.white,
                foregroundColor: textAlmostBlack,
                elevation: 1,
                titleTextStyle: GoogleFonts.lato(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textAlmostBlack),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), 
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: accentPeriwinkle,
                foregroundColor: textAlmostBlack,
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white, 
                labelStyle: const TextStyle(color: textMutedBlueGrey),
                hintStyle: const TextStyle(color: textMutedBlueGrey),
                border: OutlineInputBorder( 
                  borderRadius: BorderRadius.circular(25), 
                  borderSide: const BorderSide(color: textMutedBlueGrey),
                ),
                focusedBorder: OutlineInputBorder( 
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: primaryBlue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: primaryBlue,
                )
              ),
              listTileTheme: ListTileThemeData(
                 iconColor: primaryBlue,
              ),
               visualDensity: VisualDensity.adaptivePlatformDensity, 
            ),

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