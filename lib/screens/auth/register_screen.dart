// lib/screens/auth/register_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
// ¡Añadimos el import de HomeScreen para poder navegar a ella!
import '../home/home_screen.dart'; 

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

    // --- ¡CORRECCIÓN! ---
    // Declarar 'success' aquí, fuera del try, para que sea visible en 'finally'.
    bool success = false;
    // --- FIN CORRECCIÓN ---

    try {
      // 4. Llamar a mi AuthService (con listen: false)
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // 5. Asignar el valor a la variable 'success' ya declarada
      success = await authService.register( // <-- Quitar 'final'
        _usernameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text, // La contraseña
      );

      // 6. Verificar si el widget sigue montado después del `await`.
      if (!mounted) return;

      if (success) {
        // 7a. Si el registro es exitoso (`true`):
        print("RegisterScreen: Registro exitoso. Navegando a HomeScreen...");
        
        // ¡Navegación explícita!
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (ctx) => const HomeScreen()),
          (route) => false, // Esta condición borra todas las rutas anteriores
        );
      
      } else {
        // 7b. Si falla (`false`):
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error en el registro. Verifica los datos o el usuario/email podría ya existir.'),
            backgroundColor: Colors.redAccent,
            ),
        );
      }

    } catch (e) {
       // 8. Capturar cualquier otro error inesperado (ej. red).
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
      // 9. Ocultar el indicador de carga, pase lo que pase.
      if (mounted) {
        // ¡Ahora 'success' SÍ es visible!
        // Solo ocultamos el spinner si el registro falló.
        // Si tuvo éxito, la pantalla se destruye y no es necesario.
        if (!success) {
           setState(() { _isLoading = false; });
        }
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
  Widget build(BuildContext context) {
    return Scaffold(
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
                 
                Image.asset(
                  'assets/images/my_logo.png', // Misma ruta del logo
                  height: 60, 
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.person_add_alt_1_rounded, 
                      size: 60,
                      color: Theme.of(context).primaryColor,
                    );
                  },
                ),

                const SizedBox(height: 16),
                 Text(
                  'Únete a la conversación segura',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColorDark,
                  ),
                ),
                const SizedBox(height: 24),
                
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                     labelText: 'Nombre de Usuario',
                     prefixIcon: Icon(Icons.person_outline),
                    ),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa un nombre de usuario';
                    }
                    if (value.trim().length < 3) {
                      return 'Debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                     labelText: 'Email',
                     prefixIcon: Icon(Icons.email_outlined),
                    ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu email';
                    }
                    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                       return 'Ingresa un email válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
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
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa una contraseña';
                    }
                    if (value.length < 8) {
                      return 'Debe tener al menos 8 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
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
                  textInputAction: TextInputAction.done,
                   onFieldSubmitted: (_) => _submit(),
                   validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirma tu contraseña';
                    }
                    if (value != _passwordController.text) { 
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submit,
                         style: ElevatedButton.styleFrom(
                           padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('REGISTRARME', style: TextStyle(fontSize: 16)),
                      ),
                const SizedBox(height: 8),
                
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(), 
                  child: Text(
                     '¿Ya tienes cuenta? Inicia sesión',
                      style: TextStyle(color: Theme.of(context).hintColor),
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