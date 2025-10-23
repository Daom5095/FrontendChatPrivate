// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  // Guardamos la "promesa" (Future) en el estado para que solo se cree una vez.
  late Future<void> _initAuthFuture; // <-- Renombrado para claridad

  // El AuthService también se crea aquí para que persista.
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Llamamos a init UNA SOLA VEZ cuando el widget se inicializa.
    _initAuthFuture = _authService.init(); // <-- LLAMADA CORREGIDA a init()
  }

  @override
  Widget build(BuildContext context) {
    // Usamos ChangeNotifierProvider.value para proveer la instancia ya creada.
    return ChangeNotifierProvider.value(
      value: _authService,
      child: Consumer<AuthService>(
        builder: (ctx, auth, _) {
          return MaterialApp(
            title: 'Chat Seguro',
            theme: ThemeData(
              primarySwatch: Colors.deepPurple,
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
            home: FutureBuilder(
              // Usamos la promesa que guardamos en el estado.
              future: _initAuthFuture,
              builder: (context, snapshot) {
                // Mientras la promesa inicial se completa, muestra la pantalla de carga.
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SplashScreen();
                }
                // Una vez completada, decide qué pantalla mostrar basado en el estado.
                // Usamos el getter corregido/añadido isAuthenticated
                return auth.isAuthenticated // <-- GETTER CORREGIDO
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