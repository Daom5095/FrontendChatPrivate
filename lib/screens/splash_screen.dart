// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';

/// Una pantalla simple que se muestra mientras la aplicación
/// inicializa servicios importantes (como `AuthService.init()`).
///
/// Es un `StatelessWidget` porque no maneja ningún estado propio,
/// solo muestra una animación de carga.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Scaffold proporciona la estructura básica (fondo blanco).
    return const Scaffold(
      // Center para centrar el contenido vertical y horizontalmente.
      body: Center(
        // Column para apilar el indicador (spinner) y el texto.
        child: Column(
          // mainAxisAlignment: MainAxisAlignment.center centra
          // los hijos verticalmente dentro de la Columna.
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(), // El indicador de carga giratorio
            SizedBox(height: 20), // Un espacio vertical entre el indicador y el texto
            Text('Verificando sesión...'), // Texto informativo para el usuario
          ],
        ),
      ),
    );
  }
}