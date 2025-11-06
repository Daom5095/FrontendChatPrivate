// lib/screens/auth/register_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
// Quitamos import de HomeScreen, ya no navegamos directamente desde aquí

/// Mi pantalla de registro de nuevos usuarios.
///
/// Es `Stateful` porque maneja el estado del formulario,
/// los controladores de texto, los validadores y el
/// indicador de carga (`_isLoading`).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // --- Clave para el Form ---
  /// La clave global para mi widget Form, la uso para
  /// validar todos los campos a la vez.
  final _formKey = GlobalKey<FormState>();

  // --- Controladores ---
  /// Controlador para el campo de nombre de usuario.
  final _usernameController = TextEditingController();
  /// Controlador para el campo de email.
  final _emailController = TextEditingController();
  /// Controlador para el campo de contraseña.
  final _passwordController = TextEditingController();
  /// Controlador para el campo de confirmar contraseña.
  final _confirmPasswordController = TextEditingController();

  // --- Estados de UI ---
  /// `true` cuando se está procesando el registro (para mostrar el spinner).
  bool _isLoading = false;
  /// `true` si la contraseña debe ser visible.
  bool _isPasswordVisible = false;
  /// `true` si la *confirmación* de contraseña debe ser visible.
  bool _isConfirmPasswordVisible = false;

  /// Intenta registrar al usuario llamando a AuthService.
  /// Se activa al presionar el botón "REGISTRARME".
  Future<void> _submit() async {
    // 1. Validar el formulario usando la _formKey.
    if (!_formKey.currentState!.validate()) {
      return; // Si hay errores, no continúo.
    }
    // 2. Ocultar el teclado si estaba abierto.
    FocusScope.of(context).unfocus();

    // 3. Mostrar indicador de carga.
    setState(() { _isLoading = true; });

    try {
      // 4. Llamar a mi AuthService (con listen: false)
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Llamo a `authService.register`. Este método ahora
      // se encarga de *toda* la lógica de criptografía (generar claves,
      // derivar KEK, cifrar) Y de llamar a la API.
      final success = await authService.register(
        _usernameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text, // La contraseña
      );

      // 5. Verificar si el widget sigue montado después del `await`.
      if (!mounted) return;

      if (success) {
        // 6a. Si el registro es exitoso (`true`):
        print("RegisterScreen: Registro exitoso. AuthService navegará.");
        // No necesito navegar. `AuthService` notificó a `main.dart`,
        // que automáticamente nos llevará a `HomeScreen`.
        // Si el usuario está en esta pantalla (RegisterScreen), esta
        // pantalla simplemente desaparecerá de la pila de navegación.
      } else {
        // 6b. Si falla (`false`):
        // Muestro un error genérico. AuthService ya imprimió el error
        // detallado (ej. "usuario ya existe") en la consola.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error en el registro. Verifica los datos o el usuario/email podría ya existir.'),
            backgroundColor: Colors.redAccent,
            ),
        );
      }
    } catch (e) {
       // 7. Capturar cualquier otro error inesperado (ej. red).
       print("RegisterScreen Error en _submit: $e");
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('Error inesperado al registrar: ${e.toString()}'),
               backgroundColor: Colors.redAccent,
              ),
          );
       }
    } finally {
      // 8. Ocultar el indicador de carga, pase lo que pase.
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

   /// Limpio mis controladores cuando se destruye la pantalla.
  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContextBContext) {
    return Scaffold(
      // Muestro un AppBar aquí para que el usuario pueda volver fácilmente
      // a la pantalla de Login si entró por error.
      appBar: AppBar(title: const Text('Crear Nueva Cuenta')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                 
                // --- Logo/Icono ---
                Image.asset(
                  'assets/images/my_logo.png', // Misma ruta del logo
                  height: 60, // Un poco más pequeño que en el login
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback a un icono relevante si el logo falla
                    return Icon(
                      Icons.person_add_alt_1_rounded, 
                      size: 60,
                      color: Theme.of(context).primaryColor,
                    );
                  },
                ),
                // --- Fin Logo/Icono ---

                const SizedBox(height: 16),
                // Título
                 Text(
                  'Únete a la conversación segura',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColorDark,
                  ),
                ),
                const SizedBox(height: 24),
                
                // --- Campo de Usuario ---
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                     labelText: 'Nombre de Usuario',
                     prefixIcon: Icon(Icons.person_outline),
                    ),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next, // Teclado: Siguiente
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa un nombre de usuario';
                    }
                    if (value.trim().length < 3) {
                      return 'Debe tener al menos 3 caracteres';
                    }
                    return null; // Válido
                  },
                ),
                const SizedBox(height: 16),
                
                // --- Campo de Email ---
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                     labelText: 'Email',
                     prefixIcon: Icon(Icons.email_outlined),
                    ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next, // Teclado: Siguiente
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu email';
                    }
                    // Expresión regular simple para validar email
                    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                       return 'Ingresa un email válido';
                    }
                    return null; // Válido
                  },
                ),
                const SizedBox(height: 16),
                
                // --- Campo de Contraseña ---
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                       icon: Icon(
                         _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                       ),
                       onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    ),
                  ),
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.next, // Teclado: Siguiente
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa una contraseña';
                    }
                    // Aumento la seguridad pidiendo 8 caracteres para el registro
                    if (value.length < 8) {
                      return 'Debe tener al menos 8 caracteres';
                    }
                    return null; // Válido
                  },
                ),
                const SizedBox(height: 16),
                
                // --- Campo de Confirmar Contraseña ---
                 TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirmar Contraseña',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                     suffixIcon: IconButton(
                       icon: Icon(
                         _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                       ),
                       onPressed: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                    ),
                  ),
                  obscureText: !_isConfirmPasswordVisible,
                  textInputAction: TextInputAction.done, // Teclado: Listo
                   onFieldSubmitted: (_) => _submit(), // Intentar registro al presionar "Listo"
                   validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirma tu contraseña';
                    }
                    // Compruebo si coincide con el campo anterior
                    if (value != _passwordController.text) { 
                      return 'Las contraseñas no coinciden';
                    }
                    return null; // Válido
                  },
                ),
                const SizedBox(height: 32), // Más espacio antes del botón
                
                // --- Botón de Registro ---
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submit, // Llama a mi función de registro
                         style: ElevatedButton.styleFrom(
                           padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('REGISTRARME', style: TextStyle(fontSize: 16)),
                      ),
                const SizedBox(height: 8),
                
                // --- Botón para volver a Login ---
                TextButton(
                  // Deshabilitado si está cargando
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(), // Simplemente vuelve atrás
                  child: Text(
                     '¿Ya tienes cuenta? Inicia sesión',
                      style: TextStyle(color: Theme.of(context).hintColor), // Color de acento
                    ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}