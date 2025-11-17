// lib/screens/users/user_list_screen.dart

import 'dart:math'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart'; 
import '../../api/user_api.dart'; 
import '../../api/conversation_api.dart'; 
import '../chat/chat_screen.dart';   // <-- ¡CORRECCIÓN! Import faltante

/// Pantalla que muestra una lista de usuarios registrados (excluyendo al actual)
/// y permite iniciar una nueva conversación 1 a 1 con uno de ellos.
class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

/// Estado (lógica) de la pantalla `UserListScreen`.
class _UserListScreenState extends State<UserListScreen> {
  late Future<List<dynamic>> _usersFuture;

  final UserApi _userApi = UserApi();
  final ConversationApi _conversationApi = ConversationApi();

  bool _isCreatingChat = false;

  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  Color _getAvatarColor(int userId) {
    int index = userId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }

  @override
  void initState() {
    super.initState();
    print("UserListScreen [initState]: Cargando lista de usuarios...");
    _loadUsers();
  }

  void _loadUsers() {
    final authService = context.read<AuthService>();
    final token = authService.token; 

    if (token == null) {
      print("UserListScreen [_loadUsers] ERROR: Token nulo.");
      setState(() {
         _usersFuture = Future.error('No autenticado. No se pudo obtener el token.');
      });
      return; 
    }

    setState(() {
      _usersFuture = _userApi.getAllUsers(token); 
    });
  }

  /// Inicia el proceso para crear/obtener una conversación con el usuario seleccionado.
  Future<void> _startChatWithUser(int userId, String username) async {
    if (_isCreatingChat) return;

    print("UserListScreen [_startChatWithUser]: Intentando iniciar chat con usuario ID $userId ($username)...");
    
    setState(() { _isCreatingChat = true; });

    try {
      final authService = context.read<AuthService>();
      final token = authService.token;

      if (token == null) {
        throw Exception('No autenticado. No se pudo obtener el token para crear el chat.');
      }

      print("UserListScreen [_startChatWithUser]: Llamando a ConversationApi.createConversation...");
      final newConversationData = await _conversationApi.createConversation(token, userId);
      print("UserListScreen [_startChatWithUser]: Conversación creada/obtenida: ${newConversationData['id']}");

      if (!mounted) return;

      // ¡Este es el método que daba error!
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: newConversationData),
        ),
      );
      
    } catch (e) {
      print("UserListScreen [_startChatWithUser] ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar el chat: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingChat = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar Chat 1-a-1'),
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
                print("UserListScreen [FutureBuilder] Error: ${snapshot.error}");
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                         const SizedBox(height: 16),
                         Text('Error al cargar usuarios: ${snapshot.error}', textAlign: TextAlign.center),
                         const SizedBox(height: 16),
                         ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text("Reintentar"),
                            onPressed: _loadUsers, 
                         )
                       ],
                    ),
                  )
                );
              }
              
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No se encontraron otros usuarios registrados.'));
              }

              final users = snapshot.data!;
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (ctx, index) {
                  final user = users[index];
                  final userId = (user['id'] as num?)?.toInt();
                  final username = user['username'] as String?;

                  if (userId == null || username == null) {
                     print("UserListScreen [ListView] Warning: Datos inválidos para usuario en índice $index. Saltando.");
                     return const SizedBox.shrink(); 
                  }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getAvatarColor(userId), 
                      foregroundColor: Colors.white, 
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(username),
                    onTap: () {
                      if (!_isCreatingChat) {
                        _startChatWithUser(userId, username);
                      }
                    },
                    enabled: !_isCreatingChat,
                  );
                },
              );
            },
          ), 

          if (_isCreatingChat)
            Container(
              color: Colors.black.withOpacity(0.5), 
              child: const Center(
                child: Column( 
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("Iniciando chat...", style: TextStyle(color: Colors.white))
                   ],
                )
              ),
            ),
        ], 
      ), 
    ); 
  }
}