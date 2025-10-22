

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../api/user_api.dart';
import '../../api/conversation_api.dart'; // <-- 1. IMPORTA LA NUEVA API
import '../chat/chat_screen.dart';   // <-- 2. IMPORTA LA NUEVA PANTALLA

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  late Future<List<dynamic>> _usersFuture;
  final UserApi _userApi = UserApi();
  final ConversationApi _conversationApi = ConversationApi(); // <-- 3. CREA UNA INSTANCIA
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() {
    final authService = Provider.of<AuthService>(context, listen: false);
    _usersFuture = _userApi.getAllUsers(authService.token!);
  }

  // 4. MÉTODO PARA MANEJAR LA CREACIÓN DEL CHAT
  Future<void> _startChatWithUser(int userId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final newConversation = await _conversationApi.createConversation(authService.token!, userId);

      if (!mounted) return;

      // Navega a la pantalla de chat con la conversación recién creada
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversation: newConversation),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear el chat: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar nueva conversación'),
      ),
      body: Stack(
        children: [
          FutureBuilder<List<dynamic>>(
            future: _usersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error al cargar usuarios: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No se encontraron usuarios.'));
              }

              final users = snapshot.data!;

              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (ctx, index) {
                  final user = users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(user['username'][0].toUpperCase()),
                    ),
                    title: Text(user['username']),
                    onTap: () {
                      // 5. LLAMA AL NUEVO MÉTODO AL TOCAR UN USUARIO
                      _startChatWithUser(user['id']);
                    },
                  );
                },
              );
            },
          ),
          // Muestra un indicador de carga encima de la lista cuando se está creando el chat
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}