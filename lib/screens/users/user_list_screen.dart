// lib/screens/users/user_list_screen.dart

import 'dart:math'; // <-- AÑADIDO
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart'; // Para obtener el token
import '../../api/user_api.dart'; // Para obtener la lista de usuarios
import '../../api/conversation_api.dart'; // Para crear la conversación
import '../chat/chat_screen.dart';   // La pantalla a la que navegaremos

/// Pantalla que muestra una lista de usuarios registrados (excluyendo al actual)
/// y permite iniciar una nueva conversación 1 a 1 con uno de ellos.
class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  // Future para cargar la lista de usuarios. 'late' porque se inicializa en initState.
  late Future<List<dynamic>> _usersFuture;

  // Instancias de las APIs que necesitamos
  final UserApi _userApi = UserApi();
  final ConversationApi _conversationApi = ConversationApi();

  // Estado para mostrar un indicador de carga mientras se crea la conversación
  bool _isCreatingChat = false;

  // === AÑADIDO: Lógica de colores para avatares ===
  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  Color _getAvatarColor(int userId) {
    // Usa el ID del usuario para elegir un color de forma determinista
    int index = userId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }
  // === FIN AÑADIDO ===


  @override
  void initState() {
    super.initState();
    print("UserListScreen [initState]: Cargando lista de usuarios...");
    // Iniciamos la carga de usuarios al construir la pantalla
    _loadUsers();
  }

  /// Carga la lista de usuarios desde la API.
  /// Obtiene el token desde AuthService.
  void _loadUsers() {
    // Usamos 'context.read' aquí porque solo necesitamos el AuthService una vez
    // para obtener el token, no necesitamos escuchar cambios.
    final authService = context.read<AuthService>();
    final token = authService.token; // Obtenemos el token actual

    // Validación: Si no hay token, no podemos cargar usuarios.
    if (token == null) {
      print("UserListScreen [_loadUsers] ERROR: Token nulo. No se puede cargar la lista de usuarios.");
      // Asignamos un Future que falla inmediatamente para que FutureBuilder muestre error.
      setState(() {
         _usersFuture = Future.error('No autenticado. No se pudo obtener el token.');
      });
      return; // Detener
    }

    // Si hay token, iniciamos la llamada a la API
    setState(() {
      _usersFuture = _userApi.getAllUsers(token); // Llama a /api/users
    });
  }

  /// Inicia el proceso para crear/obtener una conversación con el usuario seleccionado.
  /// Llama a la API de conversaciones y luego navega a ChatScreen.
  Future<void> _startChatWithUser(int userId, String username) async {
    // Prevenir múltiples clics mientras se procesa
    if (_isCreatingChat) return;

    print("UserListScreen [_startChatWithUser]: Intentando iniciar chat con usuario ID $userId ($username)...");
    setState(() {
      _isCreatingChat = true; // Mostrar indicador de carga
    });

    try {
      final authService = context.read<AuthService>();
      final token = authService.token;

      // Validación de token
      if (token == null) {
        throw Exception('No autenticado. No se pudo obtener el token para crear el chat.');
      }

      // Llamar a la API para crear (o obtener si ya existe) la conversación directa
      print("UserListScreen [_startChatWithUser]: Llamando a ConversationApi.createConversation...");
      final newConversationData = await _conversationApi.createConversation(token, userId);
      print("UserListScreen [_startChatWithUser]: Conversación creada/obtenida: ${newConversationData['id']}");

      // Verificar si el widget sigue montado después de la llamada asíncrona
      if (!mounted) return;

      // Navegar a la pantalla de chat, pasando los datos de la conversación
      // Usamos pushReplacement si queremos que al volver atrás no regrese a la lista de usuarios,
      // o push si queremos poder volver. Usemos push por ahora.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: newConversationData),
        ),
      );
      // Podríamos querer hacer pop() de esta pantalla después de navegar si no queremos volver
      // Navigator.of(context).pop();

    } catch (e) {
      // Manejar errores (red, API, etc.)
      print("UserListScreen [_startChatWithUser] ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar el chat: ${e.toString()}')),
        );
      }
    } finally {
      // Asegurarse de quitar el indicador de carga, incluso si hubo error
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
        title: const Text('Iniciar Nueva Conversación'),
        // Podríamos añadir un botón de refrescar aquí
        // actions: [ IconButton(icon: Icon(Icons.refresh), onPressed: _loadUsers) ],
      ),
      // Usamos Stack para poder mostrar el indicador de carga encima de la lista
      body: Stack(
        children: [
          // FutureBuilder maneja los estados de carga/error/datos de la lista
          FutureBuilder<List<dynamic>>(
            future: _usersFuture, // El Future que estamos esperando
            builder: (context, snapshot) {
              // 1. Estado de Carga
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              // 2. Estado de Error
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
                            onPressed: _loadUsers, // Botón para reintentar
                         )
                       ],
                    ),
                  )
                );
              }
              // 3. Estado sin Datos (o lista vacía)
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No se encontraron otros usuarios registrados.'));
              }

              // 4. Estado con Datos: Mostrar la lista
              final users = snapshot.data!;
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (ctx, index) {
                  final user = users[index];
                  // Extraer datos del usuario (con validación básica)
                  final userId = (user['id'] as num?)?.toInt();
                  final username = user['username'] as String?;

                  // Si falta algún dato esencial, mostrar un elemento inválido o saltarlo
                  if (userId == null || username == null) {
                     print("UserListScreen [ListView] Warning: Datos inválidos para usuario en índice $index. Saltando.");
                     return const SizedBox.shrink(); // No mostrar nada si los datos son incorrectos
                  }

                  // Crear el ListTile para cada usuario
                  return ListTile(
                    // === CAMBIO AQUÍ ===
                    leading: CircleAvatar(
                      backgroundColor: _getAvatarColor(userId), // Aplicar color
                      foregroundColor: Colors.white, // Letra blanca
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // === FIN CAMBIO ===
                    title: Text(username),
                    // subtitle: Text('ID: $userId'), // Opcional: mostrar ID
                    onTap: () {
                      // Acción al tocar: iniciar chat (si no se está creando ya uno)
                      if (!_isCreatingChat) {
                        _startChatWithUser(userId, username);
                      }
                    },
                    // Podríamos deshabilitar el tap si _isCreatingChat es true
                    // enabled: !_isCreatingChat,
                  );
                },
              );
            },
          ), // Fin FutureBuilder

          // Indicador de carga semi-transparente que cubre toda la pantalla
          // Se muestra solo cuando _isCreatingChat es true
          if (_isCreatingChat)
            Container(
              color: Colors.black.withOpacity(0.5), // Fondo oscuro semi-transparente
              child: const Center(
                child: Column( // Añadir texto bajo el indicador
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("Iniciando chat...", style: TextStyle(color: Colors.white))
                   ],
                )
              ),
            ),

        ], // Fin hijos del Stack
      ), // Fin Stack
    ); // Fin Scaffold
  }
} // Fin clase _UserListScreenState