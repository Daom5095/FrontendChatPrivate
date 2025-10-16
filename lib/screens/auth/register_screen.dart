import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
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

    if (!mounted) return;


    if (success) {
   
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error en el registro. Inténtalo de nuevo.')),
      );
    }
    // --------------------------------

    setState(() { _isLoading = false; });
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
              TextFormField(
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
}
