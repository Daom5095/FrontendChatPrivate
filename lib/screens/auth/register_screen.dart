import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController(); // Asegúrate de tener este controlador
  final _passwordController = TextEditingController();
  bool _isLoading = false;

Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() { _isLoading = true; });

    final authService = Provider.of<AuthService>(context, listen: false);

    final success = await authService.register(
      _usernameController.text,
      _emailController.text,
      _passwordController.text,
    );

    // IMPORTANTE: Verificar montaje DESPUÉS del await
    if (!mounted) return;

    if (success) {
      print("Registro exitoso en backend. Navegando a HomeScreen...");
      // Ahora HomeScreen será reconocido
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (ctx) => HomeScreen()), // SIN const
      );
      // No necesitamos detener el loading aquí
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error en el registro. Verifica los datos o el usuario/email podría ya existir.')),
      );
      // Solo detenemos el indicador de carga si falla
      // if (mounted) { // No es necesario comprobar mounted de nuevo aquí
         setState(() { _isLoading = false; });
      // }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear Cuenta')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Usuario'),
                validator: (value) => value!.isEmpty ? 'Ingresa un usuario' : null,
              ),
              TextFormField( // Asegúrate de que el campo de email exista
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value!.isEmpty || !value.contains('@') ? 'Ingresa un email válido' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                obscureText: true,
                validator: (value) => value!.length < 6 ? 'La contraseña debe tener al menos 6 caracteres' : null,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(onPressed: _submit, child: const Text('Registrarse')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Es buena práctica liberar los controladores
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}