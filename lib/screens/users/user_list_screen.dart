import 'package:flutter/material.dart';

class UserListScreen extends StatelessWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar nueva conversación'),
      ),
      body: const Center(
        child: Text('Aquí aparecerá la lista de usuarios.'),
      ),
    );
  }
}