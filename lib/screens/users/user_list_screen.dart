// lib/screens/users/user_list_screen.dart

import 'dart.math'; // Para la lógica de colores aleatorios
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart'; // Para obtener el token
import '../../api/user_api.dart'; // Para obtener la lista de usuarios
import '../../api/conversation_api.dart'; // Para crear la conversación
import '../chat/chat_screen.dart';   // La pantalla a la que navegaremos

/// Pantalla que muestra una lista de usuarios registrados (excluyendo al actual)
/// y permite iniciar una nueva conversación 1 a 1 con uno de ellos.
///
/// Se accede a esta pantalla desde el `FloatingActionButton` de `HomeScreen`.
class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

/// Estado (lógica) de la pantalla `UserListScreen`.
class _UserListScreenState extends State<UserListScreen> {
  /// El Future que usará mi `FutureBuilder` para mostrar la lista.
  /// Se inicializa en `initState` llamando a `_loadUsers()`.
  late Future<List<dynamic>> _usersFuture;

  // Instancias de las APIs que necesito
  final UserApi _userApi = UserApi();
  final ConversationApi _conversationApi = ConversationApi();

  /// Estado para mostrar un indicador de carga *encima* de la lista.
  /// Se activa cuando el usuario toca un nombre y se está creando
  /// la conversación (antes de navegar a `ChatScreen`).
  bool _isCreatingChat = false;

  // --- Lógica de colores para avatares ---
  /// Lista de colores base para los avatares.
  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  /// Obtiene un color determinista basado en el ID del usuario.
  Color _getAvatarColor(int userId) {
    // Uso el ID del usuario para elegir un color
    int index = userId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }
  // --- Fin Lógica de Avatares ---

  @override
  void initState() {
    super.initState();
    print("UserListScreen [initState]: Cargando lista de usuarios...");
    // Iniciamos la carga de usuarios inmediatamente
    _loadUsers();
  }

  /// Carga la lista de usuarios desde la API.
  /// Obtiene el token desde AuthService y asigna el Future
  /// a la variable de estado `_usersFuture`.
  void _loadUsers() {
    // Uso `context.read` porque solo necesito el token una vez.
    final authService = context.read<AuthService>();
    final token = authService.token; // Obtengo el token actual

    // Validación: Si no hay token, no puedo cargar nada.
    if (token == null) {
      print("UserListScreen [_loadUsers] ERROR: Token nulo. No se puede cargar la lista de usuarios.");
      // Asigno un Future que falla inmediatamente.
      // Mi `FutureBuilder` verá este error y mostrará un mensaje.
      setState(() {
         _usersFuture = Future.error('No autenticado. No se pudo obtener el token.');
      });
      return; // Detener
    }

    // Si hay token, llamo a la API y asigno el Future resultante
    // a mi variable de estado. El `FutureBuilder` reaccionará a esto.
    setState(() {
      _usersFuture = _userApi.getAllUsers(token); // Llama a GET /api/users
    });
  }

  /// Inicia el proceso para crear/obtener una conversación con el usuario seleccionado.
  /// Llama a la API de conversaciones y luego navega a `ChatScreen`.
  Future<void> _startChatWithUser(int userId, String username) async {
    // Prevenir múltiples clics si ya estoy creando un chat
    if (_isCreatingChat) return;

    print("UserListScreen [_startChatWithUser]: Intentando iniciar chat con usuario ID $userId ($username)...");
    
    // 1. Mostrar el indicador de carga (cubre toda la pantalla)
    setState(() {
      _isCreatingChat = true;
    });

    try {
      final authService = context.read<AuthService>();
      final token = authService.token;

      if (token == null) {
        throw Exception('No autenticado. No se pudo obtener el token para crear el chat.');
      }

      // 2. Llamar a la API para crear (o obtener si ya existe) la conversación
      print("UserListScreen [_startChatWithUser]: Llamando a ConversationApi.createConversation...");
      // Mi backend es inteligente: si ya existe un chat 1-a-1, lo devuelve.
      // Si no, lo crea y lo devuelve.
      final newConversationData = await _conversationApi.createConversation(token, userId);
      print("UserListScreen [_startChatWithUser]: Conversación creada/obtenida: ${newConversationData['id']}");

      if (!mounted) return; // Comprobar si sigo en pantalla

      // 3. Navegar a la pantalla de chat
      // Uso `push` normal para que el usuario pueda "volver"
      // desde el chat a esta lista de usuarios.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: newConversationData),
        ),
      );
      
      // NOTA: Podría usar `pushReplacement` si quisiera que esta
      // pantalla desaparezca de la pila al entrar al chat,
      // o `pop` si quisiera cerrar esta pantalla después de navegar.
      // Por ahora, `push` está bien.

    } catch (e) {
      // 4. Manejar errores
      print("UserListScreen [_startChatWithUser] ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar el chat: ${e.toString()}')),
        );
      }
    } finally {
      // 5. Ocultar el indicador de carga, pase lo que pase.
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
        // Podría añadir un botón de refrescar aquí si quisiera
        // actions: [ IconButton(icon: Icon(Icons.refresh), onPressed: _loadUsers) ],
      ),
      // Uso un Stack para poder poner el overlay de carga
      // encima de la lista de usuarios.
      body: Stack(
        children: [
          // El FutureBuilder maneja la carga inicial de la lista
          FutureBuilder<List<dynamic>>(
            future: _usersFuture, // 1. El Future que estamos esperando
            builder: (context, snapshot) {
              
              // --- Estado 1: Cargando lista ---
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              // --- Estado 2: Error al cargar lista ---
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
              
              // --- Estado 3: Lista vacía ---
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No se encontraron otros usuarios registrados.'));
              }

              // --- Estado 4: Éxito (Mostrar lista) ---
              final users = snapshot.data!;
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (ctx, index) {
                  final user = users[index];
                  // Parseo los datos del usuario
                  final userId = (user['id'] as num?)?.toInt();
                  final username = user['username'] as String?;

                  // Si el backend me manda datos raros, mejor no lo muestro
                  if (userId == null || username == null) {
                     print("UserListScreen [ListView] Warning: Datos inválidos para usuario en índice $index. Saltando.");
                     return const SizedBox.shrink(); // No mostrar nada
                  }

                  // Renderizo la fila (ListTile) para este usuario
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getAvatarColor(userId), // Color determinista
                      foregroundColor: Colors.white, // Letra blanca
                      child: Text(
                        // Muestro la primera letra del nombre
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(username),
                    // subtitle: Text('ID: $userId'), // Podría mostrar el ID para debug
                    onTap: () {
                      // Al tocar, llamo a mi función para iniciar el chat
                      if (!_isCreatingChat) {
                        _startChatWithUser(userId, username);
                      }
                    },
                    // Deshabilito el tap si ya estoy creando un chat
                    enabled: !_isCreatingChat,
                  );
                },
              );
            },
          ), 

          // --- Overlay de Carga ---
          // Este widget se pone encima de todo si `_isCreatingChat` es true.
          if (_isCreatingChat)
            Container(
              // Fondo oscuro semitransparente
              color: Colors.black.withOpacity(0.5), 
              child: const Center(
                child: Column( // Muestro un spinner y texto
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