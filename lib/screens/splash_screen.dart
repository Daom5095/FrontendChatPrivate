// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';

/// Una pantalla simple que se muestra mientras la aplicación
/// inicializa servicios importantes (como AuthService.init()).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Scaffold proporciona la estructura básica de la pantalla.
    return const Scaffold(
      // Center para centrar el contenido vertical y horizontalmente.
      body: Center(
        // Column para apilar el indicador y el texto.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Centrar verticalmente en la columna
          children: [
            CircularProgressIndicator(), // El indicador de carga giratorio
            SizedBox(height: 20), // Un espacio entre el indicador y el texto
            Text('Verificando sesión...'), // Texto informativo
          ],
        ),
      ),
    );
  }
}