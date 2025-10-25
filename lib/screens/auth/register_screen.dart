// lib/screens/auth/register_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
// Quitamos import de HomeScreen, ya no navegamos directamente desde aquí
// import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // --- Clave para el Form ---
  final _formKey = GlobalKey<FormState>();

  // --- Controladores ---
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController(); // Para confirmar

  // --- Estados de UI ---
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  /// Intenta registrar al usuario llamando a AuthService.
  Future<void> _submit() async {
    // Validar formulario
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Ocultar teclado si está abierto
    FocusScope.of(context).unfocus();

    // Mostrar indicador de carga
    setState(() { _isLoading = true; });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      // Llamamos a register solo con los datos necesarios
      final success = await authService.register(
        _usernameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text, // No trim password
      );

      if (!mounted) return;

      if (success) {
        print("RegisterScreen: Registro exitoso. AuthService navegará.");
        // AuthService ya se encarga de notificar y main.dart navegará a HomeScreen.
        // No necesitamos hacer pushReplacement aquí.
        // Navigator.of(context).pushReplacement(
        //   MaterialPageRoute(builder: (ctx) => const HomeScreen()),
        // );
      } else {
        // Mostrar SnackBar si el registro falla
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error en el registro. Verifica los datos o el usuario/email podría ya existir.'),
            backgroundColor: Colors.redAccent,
            ),
        );
      }
    } catch (e) {
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
      // Ocultar indicador si aún estamos montados
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

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
      appBar: AppBar(title: const Text('Crear Nueva Cuenta')), // Mantenemos AppBar aquí
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                 // --- Placeholder Logo/Icon ---
                Icon(
                  Icons.person_add_alt_1_rounded, // Icono de añadir usuario
                  size: 60,
                  color: Theme.of(context).primaryColor,
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
                // --- Campo de Usuario ---
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
                    // Podríamos añadir validación de caracteres si quisiéramos
                    return null;
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
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa tu email';
                    }
                    // Expresión regular simple para validar email
                    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                       return 'Ingresa un email válido';
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
                    if (value.length < 8) { // Aumentamos longitud mínima
                      return 'Debe tener al menos 8 caracteres';
                    }
                    // Podríamos añadir validaciones más complejas (mayúsculas, números, etc.)
                    return null;
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
                  textInputAction: TextInputAction.done,
                   onFieldSubmitted: (_) => _submit(), // Intentar registro al presionar Enter/Listo
                   validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirma tu contraseña';
                    }
                    if (value != _passwordController.text) { // Comprobar si coincide
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32), // Más espacio antes del botón
                // --- Botón de Registro ---
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
                // --- Botón para volver a Login ---
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(), // Simplemente volver
                  child: Text(
                     '¿Ya tienes cuenta? Inicia sesión',
                      style: TextStyle(color: Theme.of(context).hintColor), // Usar color de acento
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