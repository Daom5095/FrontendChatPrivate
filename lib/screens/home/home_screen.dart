// lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math'; // Para generar colores aleatorios basados en ID
import 'package:intl/intl.dart'; // Importado para formatear fechas
import '../../services/auth_service.dart';
import '../../api/conversation_api.dart';
import '../users/user_list_screen.dart';
import '../chat/chat_screen.dart';
import '../../services/crypto_service.dart'; 

/// Pantalla principal después del login.
/// Muestra la lista de conversaciones existentes del usuario.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- 1. CAMBIO: Esta variable se inicializa en initState ---
  late Future<List<dynamic>> _conversationsFuture;
  final ConversationApi _conversationApi = ConversationApi();

  final CryptoService _cryptoService = CryptoService();
  String? _privateKeyPem; // Para guardar la clave privada
  
  // --- ELIMINADO: Ya no necesitamos este flag ---
  // bool _isLoadingKey = true; 

  // Colores base para generar colores de avatar pseudo-aleatorios
  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    print("HomeScreen [initState]: Cargando...");
    // --- 2. CAMBIO: Asignamos el Future INMEDIATAMENTE ---
    // De esta forma, _conversationsFuture NUNCA es 'late'
    // El FutureBuilder ahora esperará a que todo este método termine.
    _conversationsFuture = _initializeHomeScreen();
  }

  // --- 3. CAMBIO: El método ahora devuelve el Future que el Builder necesita ---
  Future<List<dynamic>> _initializeHomeScreen() async {
    // Asegurarse de que el widget esté montado antes de usar 'context'
    // Usamos 'findAncestorStateOfType' porque 'context' no está disponible
    // directamente en el flujo de initState.
    if (!mounted) return []; 
    
    final authService = context.read<AuthService>();
    try {
      // Primero, obtenemos la clave privada
      print("HomeScreen [_initializeHomeScreen]: Obteniendo clave privada...");
      _privateKeyPem = await authService.getPrivateKeyForSession();
      if (_privateKeyPem == null) {
        throw Exception("No se pudo obtener la clave privada.");
      }
      print("HomeScreen [_initializeHomeScreen]: Clave privada obtenida.");

      // Si tenemos la clave, cargamos y DEVOLVEMOS las conversaciones
      return _loadConversations(authService.token);
    } catch (e) {
      print("HomeScreen [_initializeHomeScreen] Error: $e");
      // Si falla, lanzamos el error para que el FutureBuilder lo capture
      throw Exception('Error al iniciar: $e');
    }
    // No necesitamos 'finally' para 'isLoadingKey'
  }

  // --- 4. CAMBIO: Este método ahora devuelve el Future, no llama a setState ---
  Future<List<dynamic>> _loadConversations(String? token) async {
    if (token == null) {
      print("HomeScreen [_loadConversations] ERROR: Token nulo.");
      throw Exception('No autenticado.');
    }
    // Simplemente devolvemos el Future de la API.
    // El FutureBuilder se encargará de manejar el estado.
    return _conversationApi.getConversations(token);
  }


  void _navigateToChat(Map<String, dynamic> conversationData) {
     print("HomeScreen [_navigateToChat]: Navegando a ChatScreen para conversación ID ${conversationData['id']}");
     Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: conversationData),
        ),
     ).then((_) {
        print("HomeScreen: Volviendo de ChatScreen. Recargando conversaciones...");
        // Recargamos y actualizamos el Future
        setState(() {
          _conversationsFuture = _loadConversations(context.read<AuthService>().token);
        });
     });
  }

  Color _getAvatarColor(int conversationId) {
    int index = conversationId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToCompare = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToCompare == today) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (dateToCompare == yesterday) {
      return "Ayer";
    } else {
      return DateFormat('dd/MM/yy').format(timestamp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Chats'),
        actions: [
          IconButton(
             icon: const Icon(Icons.refresh),
             tooltip: "Actualizar conversaciones",
             // Ahora llamamos a _loadConversations con el token
             onPressed: () {
                // Actualizamos el Future para que el builder recargue
                setState(() {
                  _conversationsFuture = _loadConversations(authService.token);
                });
             },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: () {
              print("HomeScreen: Botón Logout presionado.");
              authService.logout();
            },
          )
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          // --- 5. CAMBIO: Lógica de carga simplificada ---
          // El builder ahora solo se preocupa del ConnectionState
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // --- FIN CAMBIO ---

          if (snapshot.hasError) {
             print("HomeScreen [FutureBuilder] Error: ${snapshot.error}");
            return Center(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text('Error al cargar conversaciones: ${snapshot.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                         icon: const Icon(Icons.refresh),
                         label: const Text("Reintentar"),
                         onPressed: () {
                            setState(() {
                              _conversationsFuture = _initializeHomeScreen();
                            });
                         }, 
                      )
                    ],
                 ),
               )
             );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
             return Center(
               child: Padding(
                 padding: const EdgeInsets.all(24.0),
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   crossAxisAlignment: CrossAxisAlignment.center,
                   children: [
                     Icon(
                       Icons.chat_bubble_outline_rounded,
                       size: 80,
                       color: Colors.grey[300],
                     ),
                     const SizedBox(height: 16),
                     Text(
                       'No tienes conversaciones activas',
                       textAlign: TextAlign.center,
                       style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                     ),
                     const SizedBox(height: 8),
                     Text(
                       'Presiona + para iniciar una nueva.',
                       textAlign: TextAlign.center,
                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                     ),
                   ],
                 )
               )
             );
          }

          final conversations = snapshot.data!;
          print("HomeScreen [FutureBuilder]: Mostrando ${conversations.length} conversaciones.");

          // --- 6. CAMBIO: Chequeo de clave privada ---
          // Si _privateKeyPem sigue siendo nulo en este punto (aunque no debería si el future tuvo éxito)
          // mostramos un error en lugar de crashear en el _ConversationTile.
          if (_privateKeyPem == null) {
            return const Center(child: Text("Error fatal: No se pudo cargar la clave privada."));
          }

          return ListView.separated( 
            itemCount: conversations.length,
            separatorBuilder: (context, index) => Divider( 
              height: 1, 
              thickness: 0.5, 
              indent: 72, 
              endIndent: 16,
            ),
            itemBuilder: (ctx, index) {
              final conversation = conversations[index];
              if (conversation is! Map<String, dynamic> || conversation['id'] == null) {
                  print("HomeScreen [ListView] Warning: Datos de conversación inválidos en índice $index.");
                  return const SizedBox.shrink();
              }
              
              return _ConversationTile(
                conversation: conversation,
                currentUserId: authService.userId!,
                privateKeyPem: _privateKeyPem!, // Ahora es seguro usar '!'
                cryptoService: _cryptoService, 
                getAvatarColor: _getAvatarColor,
                formatTimestamp: _formatTimestamp,
                onTap: () => _navigateToChat(conversation),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: "Iniciar nueva conversación",
        child: const Icon(Icons.add_comment_rounded),
        onPressed: () {
          print("HomeScreen: Botón FAB presionado. Navegando a UserListScreen...");
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const UserListScreen()),
          );
        },
      ),
    );
  }
} 


// --- _ConversationTile (Widget interno, sin cambios) ---

class _ConversationTile extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final int currentUserId;
  final String privateKeyPem;
  final CryptoService cryptoService;
  final Function(int) getAvatarColor;
  final Function(DateTime) formatTimestamp;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.privateKeyPem,
    required this.cryptoService,
    required this.getAvatarColor,
    required this.formatTimestamp,
    required this.onTap,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  String _displayTitle = "";
  String _snippet = "Toca para iniciar el chat...";
  String _timestamp = "";
  bool _isUnread = false; 

  @override
  void initState() {
    super.initState();
    _processConversationData();
  }

  Future<void> _processConversationData() async {
    // --- 1. Lógica del Título (Movida aquí) ---
    final conversationId = (widget.conversation['id'] as num).toInt();
    String title = "Conversación $conversationId";
    final explicitTitle = widget.conversation['title'] as String?;
    final participants = widget.conversation['participants'] as List?;
    
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
       title = explicitTitle;
    } else if (participants != null) {
       final otherParticipant = participants.firstWhere(
          (p) => p is Map && p['userId'] != null && p['userId'] != widget.currentUserId,
          orElse: () => null,
       );
       if (otherParticipant != null) {
          final username = otherParticipant['username'] as String?;
          title = username ?? 'Usuario ${otherParticipant['userId']}';
       } else if (participants.isNotEmpty && participants.first['userId'] == widget.currentUserId) {
          title = 'Chat contigo mismo';
       }
    }
    
    // --- 2. Lógica del Último Mensaje (Movida aquí) ---
    final lastMessageData = widget.conversation['lastMessage'] as Map<String, dynamic>?;
    String snippet = "Toca para iniciar el chat...";
    String timestamp = "";

    if (lastMessageData != null) {
      final ciphertext = lastMessageData['text'] as String?;
      final encryptedKey = lastMessageData['encryptedKey'] as String?;
      final createdAt = lastMessageData['createdAt'] as String?;

      if (createdAt != null) {
         try {
           final ts = DateTime.parse(createdAt).toLocal();
           timestamp = widget.formatTimestamp(ts);
         } catch (e) { /* ignorar error de fecha */ }
      }

      // --- 3. Lógica de Descifrado ---
      if (ciphertext != null && encryptedKey != null) {
        try {
          final combinedKeyIV = await widget.cryptoService.decryptRSA(encryptedKey, widget.privateKeyPem);
          final aesKeyMap = widget.cryptoService.splitKeyIV(combinedKeyIV);
          final plainText = widget.cryptoService.decryptAES_CBC(
            ciphertext, 
            aesKeyMap['key']!, 
            aesKeyMap['iv']!
          );
          snippet = plainText;
        } catch (e) {
          print("Error al descifrar snippet para conv ${widget.conversation['id']}: $e");
          snippet = "[Mensaje no disponible]";
        }
      } else if (ciphertext != null) {
         snippet = "[Mensaje cifrado]";
      }
      
    }

    // --- 4. Actualizar el estado del widget ---
    if (mounted) {
      setState(() {
        _displayTitle = title;
        _snippet = snippet;
        _timestamp = timestamp;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = (widget.conversation['id'] as num).toInt();

    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _isUnread ? Theme.of(context).primaryColor : Colors.grey[600],
          fontWeight: _isUnread ? FontWeight.bold : FontWeight.normal,
        );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      leading: CircleAvatar(
        backgroundColor: widget.getAvatarColor(conversationId),
        foregroundColor: Colors.white,
        child: Text(
          _displayTitle.isNotEmpty ? _displayTitle[0].toUpperCase() : 'C',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        _displayTitle,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: _isUnread ? FontWeight.bold : FontWeight.w600,
              color: _isUnread ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.titleMedium?.color
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _snippet, 
        style: subtitleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _timestamp, 
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _isUnread ? Theme.of(context).primaryColor : Colors.grey,
              fontWeight: _isUnread ? FontWeight.bold : FontWeight.normal,
            ),
      ),
      onTap: widget.onTap, 
    );
  }
}