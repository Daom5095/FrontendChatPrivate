// lib/screens/auth/login_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart'; // Para navegar al registro

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- Clave para el Form ---
  final _formKey = GlobalKey<FormState>(); // Necesario para validar

  // --- Controladores ---
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // --- Estados de UI ---
  bool _isLoading = false;
  bool _isPasswordVisible = false; // Estado para mostrar/ocultar contraseña

  /// Intenta iniciar sesión llamando a AuthService.
  Future<void> _submit() async {
    // Validar el formulario antes de continuar
    if (!_formKey.currentState!.validate()) {
      return; // Si hay errores de validación, no hacer nada más
    }

    // Mostrar indicador de carga
    setState(() { _isLoading = true; });

    try { // Envolver la llamada en try-catch para errores inesperados
      final authService = Provider.of<AuthService>(context, listen: false);
      final success = await authService.login(
        _usernameController.text.trim(), // Usar trim para quitar espacios
        _passwordController.text, // La contraseña no necesita trim usualmente
      );

      // Verificar si el widget sigue montado DESPUÉS del await
      if (!mounted) return;

      if (!success) {
        // Mostrar SnackBar si el login falla (ej. credenciales incorrectas)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario o contraseña incorrectos.'),
            backgroundColor: Colors.redAccent, // Color de error
            ),
        );
      }
      // Si el login es exitoso, AuthService notificará y main.dart
      // se encargará de navegar a HomeScreen automáticamente.
      // No necesitamos navegar desde aquí.

    } catch (e) {
       // Capturar otros errores (red, etc.)
       print("LoginScreen Error en _submit: $e");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Error al intentar iniciar sesión: ${e.toString()}'),
             backgroundColor: Colors.redAccent,
            ),
         );
       }
    } finally {
      // Ocultar indicador de carga, independientemente del resultado
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    // Liberar controladores
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Quitamos el AppBar para un look más limpio, opcional
      // appBar: AppBar(title: const Text('Iniciar Sesión')),
      body: Center( // Centrar todo el contenido verticalmente
        child: SingleChildScrollView( // Permite scroll si el teclado cubre
           padding: const EdgeInsets.all(24.0), // Más padding general
          child: Form( // Envolver en un Form
            key: _formKey, // Asociar la clave
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Centrar verticalmente
              crossAxisAlignment: CrossAxisAlignment.stretch, // Estirar elementos horizontalmente
              children: [
                
                // --- CAMBIO: Placeholder para Logo ---
                // Reemplaza 'my_logo.png' por el nombre real de tu archivo de logo
                Image.asset(
                  'assets/images/my_logo.png', // Asegúrate que esta ruta exista
                  height: 80, // Ajusta el tamaño
                  // Opcional: Manejar error si el logo no carga
                  errorBuilder: (context, error, stackTrace) {
                    // Si falla la carga del logo, muestra el icono original
                    return Icon(
                      Icons.lock_person_rounded, 
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    );
                  },
                ),
                // --- FIN CAMBIO ---

                const SizedBox(height: 24),
                Text(
                  'Bienvenido',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColorDark,
                  ),
                ),
                 Text(
                  'Inicia sesión para chatear seguro',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                // --- Campo de Usuario ---
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                     labelText: 'Nombre de Usuario',
                     prefixIcon: Icon(Icons.person_outline), // Icono
                    ),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next, // Teclado: botón Siguiente
                  validator: (value) { // Validación en línea
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, ingresa tu usuario';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // --- Campo de Contraseña ---
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    // Icono para mostrar/ocultar contraseña
                    suffixIcon: IconButton(
                       icon: Icon(
                         _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                       ),
                       onPressed: () {
                         setState(() {
                           _isPasswordVisible = !_isPasswordVisible;
                         });
                       },
                    ),
                  ),
                  obscureText: !_isPasswordVisible, // Ocultar si no es visible
                  textInputAction: TextInputAction.done, // Teclado: botón Listo/Enviar
                   onFieldSubmitted: (_) => _submit(), // Intentar login al presionar Enter/Listo
                   validator: (value) { // Validación en línea
                    if (value == null || value.isEmpty) {
                      return 'Por favor, ingresa tu contraseña';
                    }
                     if (value.length < 6) { // Ejemplo de validación de longitud mínima
                       return 'La contraseña debe tener al menos 6 caracteres';
                     }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                // --- Botón de Login ---
                _isLoading
                    ? const Center(child: CircularProgressIndicator()) // Indicador centrado
                    : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom( // Estilo un poco más grande
                           padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('INICIAR SESIÓN', style: TextStyle(fontSize: 16)),
                      ),
                const SizedBox(height: 16),
                // --- Botón para ir a Registro ---
                TextButton(
                  onPressed: _isLoading ? null : () { // Deshabilitar si está cargando
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const RegisterScreen()),
                    );
                  },
                  child: Text(
                     '¿No tienes cuenta? Regístrate aquí',
                     style: TextStyle(color: Theme.of(context).primaryColor), // Usará Teal
                    ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}