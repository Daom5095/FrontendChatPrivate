// lib/screens/auth/login_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart'; 

/// Mi pantalla de inicio de sesión.
///
/// Es `Stateful` porque necesita manejar el estado del formulario,
/// los controladores de texto y el indicador de carga (`_isLoading`).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- Clave para el Form ---
  /// La clave global para mi widget Form, la uso para
  /// validar los campos (`_formKey.currentState!.validate()`).
  final _formKey = GlobalKey<FormState>();

  // --- Controladores ---
  /// Controlador para el campo de texto del nombre de usuario.
  final _usernameController = TextEditingController();
  /// Controlador para el campo de texto de la contraseña.
  final _passwordController = TextEditingController();

  // --- Estados de UI ---
  /// `true` cuando se está procesando el login (para mostrar el spinner).
  bool _isLoading = false;
  /// `true` si la contraseña debe ser visible (para el icono del ojo).
  bool _isPasswordVisible = false;

  /// Intenta iniciar sesión llamando a AuthService.
  /// Se activa al presionar el botón "INICIAR SESIÓN" o 'listo' en el teclado.
  Future<void> _submit() async {
    // 1. Validar el formulario usando la _formKey.
    // Si `validate()` devuelve false (por algún validator), detengo la ejecución.
    if (!_formKey.currentState!.validate()) {
      return; // Si hay errores de validación, no hacer nada más
    }

    // 2. Mostrar indicador de carga y deshabilitar botones.
    setState(() { _isLoading = true; });

    try { 
      // 3. Llamar a mi AuthService para que haga la lógica de login.
      // Uso `listen: false` porque estoy dentro de una función y no
      // necesito que este widget se reconstruya si AuthService cambia.
      final authService = Provider.of<AuthService>(context, listen: false);
      
      final success = await authService.login(
        _usernameController.text.trim(), // Uso trim() para quitar espacios
        _passwordController.text, // La contraseña no necesita trim
      );

      // 4. Verificar si el widget sigue "montado" (en pantalla) después
      // de la llamada asíncrona. Si el usuario navegó hacia atrás
      // mientras cargaba, no debo llamar a setState ni a ScaffoldMessenger.
      if (!mounted) return;

      if (!success) {
        // 5a. Si falla (AuthService devuelve false), muestro un error.
        // AuthService ya manejó la limpieza del token si fue necesario.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario o contraseña incorrectos.'),
            backgroundColor: Colors.redAccent, // Color de error
            ),
        );
      }
      // 5b. Si `success` es true, no hago nada aquí.
      // Mi `AuthService` (al ser un ChangeNotifier) notificará a sus listeners,
      // y `main.dart` (que sí está escuchando) se encargará
      // de navegar a `HomeScreen` automáticamente.

    } catch (e) {
       // 6. Capturar cualquier otro error inesperado (ej. red, servidor caído).
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
      // 7. Ocultar el indicador de carga, tanto si tuvo éxito como si falló.
      // Solo lo hago si el widget sigue montado.
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  /// Limpio mis controladores cuando se destruye la pantalla.
  /// Esto es importante para evitar fugas de memoria.
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No uso AppBar aquí para un look más limpio, tipo app de login.
      body: Center( // Centrar todo el contenido verticalmente
        child: SingleChildScrollView( // Permite hacer scroll si el teclado cubre los campos
           padding: const EdgeInsets.all(24.0), // Padding general
          child: Form( // Envuelvo mis campos en un Form
            key: _formKey, // Asocio la clave para la validación
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // Centrar verticalmente
              crossAxisAlignment: CrossAxisAlignment.stretch, // Estirar botones horizontalmente
              children: [
                
                // --- Logo de mi App ---
                Image.asset(
                  'assets/images/my_logo.png', // Ruta definida en pubspec.yaml
                  height: 80, 
                  // Defino un `errorBuilder` como fallback.
                  // Si por alguna razón el logo no carga, muestro un icono
                  // para que la UI no se rompa.
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.lock_person_rounded, 
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    );
                  },
                ),
              

                const SizedBox(height: 24),
                // Títulos (usando los estilos de mi Tema en main.dart)
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
                  textInputAction: TextInputAction.next, // Botón "Siguiente" en el teclado
                  validator: (value) { // Validación del Form
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor, ingresa tu usuario';
                    }
                    return null; // Devuelve null si es válido
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
                         // Cambio el icono basado en el estado `_isPasswordVisible`
                         _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                       ),
                       onPressed: () {
                         // Alterno el estado al presionar el icono
                         setState(() {
                           _isPasswordVisible = !_isPasswordVisible;
                         });
                       },
                    ),
                  ),
                  obscureText: !_isPasswordVisible, // Ocultar texto si el estado es falso
                  textInputAction: TextInputAction.done, // Botón "Listo" en el teclado
                   onFieldSubmitted: (_) => _submit(), // Llama a _submit al presionar "Listo"
                   validator: (value) { // Validación del Form
                    if (value == null || value.isEmpty) {
                      return 'Por favor, ingresa tu contraseña';
                    }
                     if (value.length < 6) { // Validación simple de longitud mínima
                       return 'La contraseña debe tener al menos 6 caracteres';
                     }
                    return null; // Válido
                  },
                ),
                const SizedBox(height: 24),
                
                // --- Botón de Login ---
                // Muestro el spinner o el botón basado en el estado `_isLoading`
                _isLoading
                    ? const Center(child: CircularProgressIndicator()) // Indicador centrado
                    : ElevatedButton(
                        onPressed: _submit, // Llama a mi función de login
                        style: ElevatedButton.styleFrom( // Estilo de mi Tema
                           padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('INICIAR SESIÓN', style: TextStyle(fontSize: 16)),
                      ),
                const SizedBox(height: 16),
                
                // --- Botón para ir a Registro ---
                TextButton(
                  onPressed: _isLoading ? null : () { // Deshabilitado si está cargando
                    // Navego a la pantalla de registro
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (ctx) => const RegisterScreen()),
                    );
                  },
                  child: Text(
                     '¿No tienes cuenta? Regístrate aquí',
                     style: TextStyle(color: Theme.of(context).primaryColor),
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