// lib/screens/home/home_screen.dart
// lib/screens/home/home_screen.dart

import 'dart:async'; // Corregido (requerido para StreamSubscription)
import 'dart:convert'; // Corregido (requerido para json.decode)
import 'dart:math'; // Corregido (requerido para colores)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../../services/auth_service.dart';
import '../../api/conversation_api.dart';
import '../users/user_list_screen.dart';
import '../chat/chat_screen.dart';
import '../../services/crypto_service.dart';
import '../../services/socket_service.dart';
import '../../services/chat_state_service.dart';



class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> _conversationsFuture;
  final ConversationApi _conversationApi = ConversationApi();
  final CryptoService _cryptoService = CryptoService();
  StreamSubscription? _messageSubscription;
  String? _privateKeyPem; 

  // --- ESTADO PARA MENSAJES NO LEÍDOS ---
  /// Almacena los IDs de las conversaciones que tienen mensajes nuevos
  final Set<int> _unreadConversationIds = {};
  // --- FIN ESTADO ---
  
  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    print("HomeScreen [initState]: Cargando...");
    _conversationsFuture = _initializeHomeScreen();
  }

  Future<List<dynamic>> _initializeHomeScreen() async {
    if (!mounted) return [];
    
    // --- MODIFICACIÓN: LEER ChatStateService ---
    // Lo necesitamos en el listener del socket
    final authService = context.read<AuthService>();
    final chatStateService = context.read<ChatStateService>();
    // --- FIN MODIFICACIÓN ---
    
    try {
      print("HomeScreen [_initializeHomeScreen]: Obteniendo clave privada...");
      _privateKeyPem = await authService.getPrivateKeyForSession();
      
      if (_privateKeyPem == null) {
        throw Exception("No se pudo obtener la clave privada.");
      }
      print("HomeScreen [_initializeHomeScreen]: Clave privada obtenida.");

      if (authService.token != null) {
         print("HomeScreen [_initializeHomeScreen]: Conectando SocketService global...");
         SocketService.instance.connect(authService.token!);
         
         // --- MODIFICACIÓN: Pasar el chatStateService al listener ---
         _setupSocketListener(chatStateService);
         // --- FIN MODIFICACIÓN ---
      }

      return _loadConversations(authService.token);
      
    } catch (e) {
      print("HomeScreen [_initializeHomeScreen] Error: $e");
      throw Exception('Error al iniciar: $e');
    }
  }
  
  /// Configura el listener para el stream de mensajes del SocketService.
  void _setupSocketListener(ChatStateService chatStateService) { // <-- RECIBE EL SERVICIO
    _messageSubscription?.cancel();
    
    _messageSubscription = SocketService.instance.messages.listen((StompFrame frame) {
      print("HomeScreen [SocketListener]: Mensaje STOMP recibido.");
      
      try {
        if (frame.body != null) {
          final decodedBody = json.decode(frame.body!);
          final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
          
          if (conversationId != null) {
            
            // --- LÓGICA DE NO LEÍDOS ---
            // ¿Es este mensaje para un chat que NO está activo?
            if (!chatStateService.isChatActive(conversationId)) {
              print("HomeScreen [SocketListener]: Mensaje para chat inactivo $conversationId. Marcando como no leído.");
              // Si no está activo, añádelo al set de no leídos
              setState(() {
                _unreadConversationIds.add(conversationId);
              });
            } else {
               print("HomeScreen [SocketListener]: Mensaje para chat activo $conversationId. No se marca como no leído.");
            }
            // --- FIN LÓGICA DE NO LEÍDOS ---

            // Refrescar la lista de chats (para el snippet)
            WidgetsBinding.instance.addPostFrameCallback((_) {
               if (mounted) {
                 print("HomeScreen [SocketListener]: Refrescando lista de conversaciones...");
                 setState(() {
                   _conversationsFuture = _loadConversations(context.read<AuthService>().token);
                 });
               }
            });
          }
        }
      } catch (e) {
         print("HomeScreen [SocketListener] Error al procesar frame: $e");
      }
    });
  }

  /// Método helper que llama a la API para obtener la lista de conversaciones.
  Future<List<dynamic>> _loadConversations(String? token) async {
    // ... (sin cambios) ...
    if (token == null) {
      throw Exception('No autenticado.');
    }
    return _conversationApi.getConversations(token);
  }

  @override
  void dispose() {
    print("HomeScreen [dispose]: Cancelando subscripción de mensajes.");
    _messageSubscription?.cancel();
    super.dispose();
  }


  /// Navega a la pantalla de chat (`ChatScreen`) para la conversación seleccionada.
  /// (Este método se moverá dentro del ListView.builder)
  void _navigateToChat(Map<String, dynamic> conversationData) {
     final conversationId = (conversationData['id'] as num).toInt();
     print("HomeScreen [_navigateToChat]: Navegando a ChatScreen para conversación ID $conversationId");
     
     // --- MODIFICACIÓN: Marcar como leído al entrar ---
     // Lo hacemos aquí, en un setState síncrono, para que la UI
     // se actualice *antes* de navegar.
     if (_unreadConversationIds.contains(conversationId)) {
       setState(() {
         _unreadConversationIds.remove(conversationId);
       });
     }
     // --- FIN MODIFICACIÓN ---

     Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: conversationData),
        ),
     ).then((_) {
        print("HomeScreen: Volviendo de ChatScreen. Recargando conversaciones...");
        setState(() {
          _conversationsFuture = _loadConversations(context.read<AuthService>().token);
        });
     });
  }

  // ... (los métodos _getAvatarColor y _formatTimestamp no cambian) ...
  Color _getAvatarColor(int conversationId) {
    // ... (código idéntico) ...
    int index = conversationId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }

  String _formatTimestamp(DateTime timestamp) {
    // ... (código idéntico) ...
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
        // ... (appBar no cambia) ...
        title: const Text('Mis Chats'),
        actions: [
          IconButton(
             icon: const Icon(Icons.refresh),
             tooltip: "Actualizar conversaciones",
             onPressed: () {
                setState(() {
                  _conversationsFuture = _loadConversations(authService.token);
                });
             },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: () {
              authService.logout();
            },
          )
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _conversationsFuture, 
        builder: (context, snapshot) {
          
          // ... (los estados waiting, hasError, y lista vacía no cambian) ...
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
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

          // --- Estado 4: Éxito (Mostrar Lista) ---
          final conversations = snapshot.data!;
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
                  return const SizedBox.shrink();
              }
              
              // --- MODIFICACIÓN: Comprobar estado "no leído" ---
              final int conversationId = (conversation['id'] as num).toInt();
              final bool isUnread = _unreadConversationIds.contains(conversationId);
              // --- FIN MODIFICACIÓN ---

              return _ConversationTile(
                conversation: conversation,
                currentUserId: authService.userId!,
                privateKeyPem: _privateKeyPem!, 
                cryptoService: _cryptoService, 
                getAvatarColor: _getAvatarColor,
                formatTimestamp: _formatTimestamp,
                isUnread: isUnread, // <-- Pasar el estado "no leído"
                onTap: () {
                  // --- MODIFICACIÓN: Lógica de "onTap" ---
                  // Combina la navegación con marcar como leído
                  
                  // 1. Marcar como leído (si es necesario)
                  if (isUnread) {
                    setState(() {
                      _unreadConversationIds.remove(conversationId);
                    });
                  }
                  // 2. Navegar
                  _navigateToChat(conversation);
                  // --- FIN MODIFICACIÓN ---
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        // ... (FAB no cambia) ...
        tooltip: "Iniciar nueva conversación",
        child: const Icon(Icons.add_comment_rounded),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const UserListScreen()),
          );
        },
      ),
    );
  }
} 


// --- Widget Interno _ConversationTile ---
// --- MODIFICACIÓN: Aceptar 'isUnread' como parámetro ---

class _ConversationTile extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final int currentUserId;
  final String privateKeyPem;
  final CryptoService cryptoService;
  final Function(int) getAvatarColor;
  final Function(DateTime) formatTimestamp;
  final VoidCallback onTap;
  final bool isUnread; // <-- PARÁMETRO AÑADIDO

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.privateKeyPem,
    required this.cryptoService,
    required this.getAvatarColor,
    required this.formatTimestamp,
    required this.onTap,
    required this.isUnread, // <-- PARÁMETRO AÑADIDO
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  String _displayTitle = "";
  String _snippet = "Toca para iniciar el chat...";
  String _timestamp = "";
  // bool _isUnread = false; // <-- ESTADO INTERNO ELIMINADO

  @override
  void initState() {
    super.initState();
    _processConversationData();
  }
  
  // --- MODIFICACIÓN: Simplificado para no manejar 'isUnread' ---
  Future<void> _processConversationData() async {
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

    if (mounted) {
      setState(() {
        _displayTitle = title;
        _snippet = snippet;
        _timestamp = timestamp;
        // Ya no se maneja _isUnread aquí
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = (widget.conversation['id'] as num).toInt();
    
    // --- MODIFICACIÓN: Usar widget.isUnread ---
    final bool isUnread = widget.isUnread; 
    
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isUnread ? Theme.of(context).primaryColor : Colors.grey[600],
          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
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
              fontWeight: isUnread ? FontWeight.bold : FontWeight.w600, // <-- Usa isUnread
              color: isUnread ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.titleMedium?.color
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _snippet, 
        style: subtitleStyle, // <-- Usa isUnread
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // --- MODIFICACIÓN: Mostrar un "badge" si no está leído ---
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _timestamp, 
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isUnread ? Theme.of(context).primaryColor : Colors.grey, // <-- Usa isUnread
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          if (isUnread) ...[
            const SizedBox(height: 4), // Espacio si no está leído
            // El "badge"
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
            ),
          ]
        ],
      ),
      // --- FIN MODIFICACIÓN ---
      onTap: widget.onTap,
    );
  }
}