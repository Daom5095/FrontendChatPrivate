// lib/screens/home/home_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
import '../groups/select_group_members_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;
  final ConversationApi _conversationApi = ConversationApi();
  final CryptoService _cryptoService = CryptoService();
  StreamSubscription? _messageSubscription;
  String? _privateKeyPem;
  int? _currentUserId;

  final Set<int> _unreadConversationIds = {};

  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    print("HomeScreen [initState]: Cargando...");
    _initializeHomeScreen();
  }

  Future<void> _initializeHomeScreen() async {
    if (mounted) setState(() { _isLoading = true; });

    final authService = context.read<AuthService>();
    final chatStateService = context.read<ChatStateService>();

    try {
      _currentUserId = authService.userId;
      if (_currentUserId == null) {
        throw Exception("Usuario no autenticado (userId es nulo)");
      }

      print("HomeScreen [_initializeHomeScreen]: Obteniendo clave privada...");
      _privateKeyPem = await authService.getPrivateKeyForSession();

      if (_privateKeyPem == null) {
        throw Exception("No se pudo obtener la clave privada.");
      }
      print("HomeScreen [_initializeHomeScreen]: Clave privada obtenida.");

      if (authService.token != null) {
        print(
            "HomeScreen [_initializeHomeScreen]: Conectando SocketService global...");
        SocketService.instance.connect(authService.token!);

        _setupSocketListener(chatStateService);
      }

      final loadedConversations = await _loadConversations(authService.token);
      
      if (mounted) {
        setState(() {
          _conversations = loadedConversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("HomeScreen [_initializeHomeScreen] Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false; 
        });
      }
      if (e.toString().contains('401') || e.toString().contains('403')) {
        authService.logout();
      }
    }
  }

  void _setupSocketListener(ChatStateService chatStateService) {
    _messageSubscription?.cancel();
    _messageSubscription =
        SocketService.instance.messages.listen((StompFrame frame) {
      print("HomeScreen [SocketListener]: Mensaje STOMP recibido.");

      try {
        if (frame.body != null) {
          final decodedBody = json.decode(frame.body!);
          final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
          final senderId = (decodedBody['senderId'] as num?)?.toInt();

          if (conversationId != null && senderId != null && senderId != _currentUserId) {
            
            print(
                "HomeScreen [SocketListener]: Mensaje de TERCEROS para conv $conversationId. Marcando como no leído y refrescando.");
            _updateConversationListLocally(conversationId, senderId, decodedBody);
          
          } else {
             print("HomeScreen [SocketListener]: Mensaje ignorado (es un eco propio o senderId nulo).");
          }
        }
      } catch (e) {
        print("HomeScreen [SocketListener] Error al procesar frame: $e");
      }
    });
  }
  
  Future<void> _updateConversationListLocally(
      int conversationId, int senderId, Map<String, dynamic> decodedBody) async {
    if (!mounted || _privateKeyPem == null) return;

    int index = _conversations.indexWhere((c) => c['id'] == conversationId);

    if (index == -1) {
      print("HomeScreen [LocalUpdate]: Chat $conversationId no encontrado. Refrescando todo.");
      final loadedConversations = await _loadConversations(context.read<AuthService>().token);
      setState(() {
         _conversations = loadedConversations;
         if (senderId != _currentUserId) {
            _unreadConversationIds.add(conversationId);
         }
      });
      return;
    }

    var conversationToUpdate = _conversations[index];

    String snippet = "[Mensaje cifrado]";
    String? encryptedKeyForMe;
    try {
      final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;
      encryptedKeyForMe = encryptedKeysMap?[_currentUserId.toString()] as String?;
      final ciphertext = decodedBody['ciphertext'] as String?;

      if (ciphertext != null && encryptedKeyForMe != null) {
         final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKeyForMe, _privateKeyPem!);
         final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
         snippet = _cryptoService.decryptAES_CBC(
           ciphertext, 
           aesKeyMap['key']!, 
           aesKeyMap['iv']!
         );
      }
    } catch (e) {
      print("HomeScreen [LocalUpdate]: Error al descifrar snippet: $e");
      snippet = "[Mensaje no disponible]";
    }

    final newLastMessage = {
      'text': decodedBody['ciphertext'], 
      'createdAt': DateTime.now().toIso8601String(),
      'encryptedKey': encryptedKeyForMe 
    };

    conversationToUpdate['lastMessage'] = newLastMessage;
    conversationToUpdate['snippet'] = snippet; 

    final updatedConversation = _conversations.removeAt(index);
    _conversations.insert(0, updatedConversation);

    bool markedUnread = false;
    if (senderId != _currentUserId) {
      _unreadConversationIds.add(conversationId);
      markedUnread = true;
    }

    setState(() {
      // El estado ya fue mutado, solo disparamos rebuild
    });
  }

  Future<List<dynamic>> _loadConversations(String? token) async {
    if (token == null) {
      throw Exception('No autenticado.');
    }
    return _conversationApi.getConversations(token);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _navigateToChat(Map<String, dynamic> conversationData) {
     final conversationId = (conversationData['id'] as num).toInt();
     if (_unreadConversationIds.contains(conversationId)) {
       setState(() {
         _unreadConversationIds.remove(conversationId);
       });
     }
     Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: conversationData),
        ),
     ).then((_) {
        _initializeHomeScreen();
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
    final dateToCompare =
        DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (dateToCompare == today) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (dateToCompare == yesterday) {
      return "Ayer";
    } else {
      return DateFormat('dd/MM/yy').format(timestamp);
    }
  }
  
  Widget _buildBody(BuildContext context, AuthService authService) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_privateKeyPem == null || _currentUserId == null) {
       return const Center(child: Text("Error fatal de autenticación."));
    }
    
    if (_conversations.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No tienes conversaciones activas',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Presiona + para iniciar una nueva.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
          ],
        ),
      ));
    }

    return ListView.separated(
      itemCount: _conversations.length,
      separatorBuilder: (context, index) => Divider(height: 1, thickness: 0.5, indent: 72, endIndent: 16),
      itemBuilder: (ctx, index) {
        final conversation = _conversations[index];
        if (conversation is! Map<String, dynamic> || conversation['id'] == null) {
          return const SizedBox.shrink();
        }
        final int conversationId = (conversation['id'] as num).toInt();
        final bool isUnread = _unreadConversationIds.contains(conversationId);
        return _ConversationTile(
          conversation: conversation,
          currentUserId: _currentUserId!,
          privateKeyPem: _privateKeyPem!,
          cryptoService: _cryptoService,
          getAvatarColor: _getAvatarColor,
          formatTimestamp: _formatTimestamp,
          isUnread: isUnread,
          localSnippet: conversation['snippet'] as String?,
          onTap: () {
            _navigateToChat(conversation);
          },
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Chats'),
        actions: [
          IconButton(
             icon: const Icon(Icons.group_add_outlined),
             tooltip: "Crear nuevo grupo",
             onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const SelectGroupMembersScreen()),
                ).then((_) {
                  _initializeHomeScreen();
                });
             },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Actualizar conversaciones",
            onPressed: () {
              _initializeHomeScreen();
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
      body: _buildBody(context, authService),
      floatingActionButton: FloatingActionButton(
        // --- ¡AQUÍ ESTÁ EL CAMBIO! ---
        tooltip: "Nuevo chat", 
        // --- FIN DEL CAMBIO ---
        child: const Icon(Icons.person_add_alt_1_rounded), 
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const UserListScreen()),
          ).then((_) {
             _initializeHomeScreen();
          });
        },
      ),
    );
  }
}



class _ConversationTile extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final int currentUserId;
  final String privateKeyPem;
  final CryptoService cryptoService;
  final Function(int) getAvatarColor;
  final Function(DateTime) formatTimestamp;
  final VoidCallback onTap;
  final bool isUnread;
  final String? localSnippet; 

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.privateKeyPem,
    required this.cryptoService,
    required this.getAvatarColor,
    required this.formatTimestamp,
    required this.onTap,
    required this.isUnread,
    this.localSnippet,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  String _displayTitle = "";
  String _snippet = "Toca para iniciar el chat...";
  String _timestamp = "";
  bool _isProcessing = true;

  @override
  void initState() {
    super.initState();
    _processConversationData();
  }

  @override
  void didUpdateWidget(covariant _ConversationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation != widget.conversation ||
        oldWidget.isUnread != widget.isUnread) {
      _processConversationData();
    }
  }

  Future<void> _processConversationData() async {
    if (mounted) setState(() { _isProcessing = true; });

    final conversationId = (widget.conversation['id'] as num).toInt();
    String title = "Conversación $conversationId";
    
    final String? conversationType = widget.conversation['type'] as String?;
    final String? explicitTitle = widget.conversation['title'] as String?;
    
    if (conversationType == 'group' && explicitTitle != null && explicitTitle.isNotEmpty) {
      title = explicitTitle;
    } else {
      final participants = widget.conversation['participants'] as List?;
      if (participants != null) {
        final otherParticipant = participants.firstWhere(
            (p) =>
                p is Map &&
                p['userId'] != null &&
                p['userId'] != widget.currentUserId,
            orElse: () => null);
        
        if (otherParticipant != null) {
          final username = otherParticipant['username'] as String?;
          title = username ?? 'Usuario ${otherParticipant['userId']}';
        } else if (participants.isNotEmpty &&
            participants.length == 1 &&
            participants.first['userId'] == widget.currentUserId) {
          title = 'Chat contigo mismo';
        } else {
          title = explicitTitle ?? "Grupo $conversationId";
        }
      }
    }

    final lastMessageData =
        widget.conversation['lastMessage'] as Map<String, dynamic>?;
    String snippet = "Toca para iniciar el chat...";
    String timestamp = "";

    if (lastMessageData != null) {
      final createdAt = lastMessageData['createdAt'] as String?;
      if (createdAt != null) {
        try {
          final ts = DateTime.parse(createdAt).toLocal();
          timestamp = widget.formatTimestamp(ts);
        } catch (e) { /* ignorar */ }
      }

      if (widget.localSnippet != null) {
        snippet = widget.localSnippet!;
      } else {
        final ciphertext = lastMessageData['text'] as String?;
        final encryptedKey = lastMessageData['encryptedKey'] as String?;
        if (ciphertext != null && encryptedKey != null) {
          try {
            final combinedKeyIV = await widget.cryptoService
                .decryptRSA(encryptedKey, widget.privateKeyPem);
            final aesKeyMap = widget.cryptoService.splitKeyIV(combinedKeyIV);
            snippet = widget.cryptoService.decryptAES_CBC(
                ciphertext, aesKeyMap['key']!, aesKeyMap['iv']!);
          } catch (e) {
            snippet = "[Mensaje no disponible]";
          }
        } else if (ciphertext != null) {
          snippet = "[Mensaje cifrado]";
        }
      }
    }

    if (mounted) {
      setState(() {
        _displayTitle = title;
        _snippet = snippet;
        _timestamp = timestamp;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = (widget.conversation['id'] as num).toInt();
    final bool isUnread = widget.isUnread;
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isUnread ? Theme.of(context).primaryColor : Colors.grey[600],
          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
        );

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
            color: isUnread
                ? Theme.of(context).textTheme.bodyLarge?.color
                : Theme.of(context).textTheme.titleMedium?.color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _isProcessing ? "..." : _snippet,
        style: subtitleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _timestamp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isUnread ? Theme.of(context).primaryColor : Colors.grey,
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          if (isUnread) ...[
            const SizedBox(height: 4),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ]
        ],
      ),
      onTap: widget.onTap,
    );
  }
}