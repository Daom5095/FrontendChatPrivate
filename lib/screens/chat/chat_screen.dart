// lib/screens/chat/chat_screen.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart';
import '../../services/chat_state_service.dart';
import 'dart:convert';
import 'chat_details_screen.dart';

// --- Widget ChatBubble (Sin cambios) ---
class ChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final DateTime createdAt;
  final String? senderName;
  final bool isGroupChat;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.createdAt,
    this.senderName,
    this.isGroupChat = false,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormatter = DateFormat('HH:mm');
    final timeString = timeFormatter.format(createdAt);
    final bubbleColor = isMe ? Theme.of(context).primaryColor : Colors.grey[100];
    final textColor =
        isMe ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    
    final senderColor = isMe || senderName == null
        ? Colors.transparent
        : Colors.accents[senderName.hashCode % Colors.accents.length].shade700;

    return Align(
      alignment: alignment,
      child: ClipPath(
        clipper: BubbleClipper(isMe: isMe),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: EdgeInsets.only(
            top: 10,
            bottom: 10,
            left: isMe ? 14 : 22,
            right: isMe ? 22 : 14,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                spreadRadius: 0.5,
                blurRadius: 1.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isGroupChat && !isMe && senderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    senderName!,
                    style: TextStyle(
                      color: senderColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              Text(
                text,
                style: TextStyle(color: textColor, fontSize: 15.5),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  timeString,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : const Color(0xFF8F9FBF),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Widget BubbleClipper (Sin cambios) ---
class BubbleClipper extends CustomClipper<Path> {
  final bool isMe;
  final double nipHeight = 10.0;
  final double nipWidth = 12.0;
  final double cornerRadius = 20.0;

  BubbleClipper({required this.isMe});

  @override
  Path getClip(Size size) {
    final path = Path();
    final double width = size.width;
    final double height = size.height;

    if (isMe) {
      path.moveTo(cornerRadius, 0);
      path.lineTo(width - cornerRadius - nipWidth, 0);
      path.arcToPoint(Offset(width - nipWidth, cornerRadius),
          radius: Radius.circular(cornerRadius));
      path.lineTo(width - nipWidth, height - nipHeight - cornerRadius);
      path.lineTo(width, height - cornerRadius);
      path.arcToPoint(Offset(width - nipWidth - cornerRadius, height),
          radius: Radius.circular(cornerRadius));
      path.lineTo(cornerRadius, height);
      path.arcToPoint(Offset(0, height - cornerRadius),
          radius: Radius.circular(cornerRadius));
      path.lineTo(0, cornerRadius);
      path.arcToPoint(Offset(cornerRadius, 0),
          radius: Radius.circular(cornerRadius));
    } else {
      path.moveTo(nipWidth + cornerRadius, 0);
      path.lineTo(width - cornerRadius, 0);
      path.arcToPoint(Offset(width, cornerRadius),
          radius: Radius.circular(cornerRadius));
      path.lineTo(width, height - cornerRadius);
      path.arcToPoint(Offset(width - cornerRadius, height),
          radius: Radius.circular(cornerRadius));
      path.lineTo(nipWidth + cornerRadius, height);
      path.arcToPoint(Offset(nipWidth, height - cornerRadius),
          radius: Radius.circular(cornerRadius));
      path.lineTo(nipWidth, height - cornerRadius - nipHeight);
      path.lineTo(0, height - cornerRadius);
      path.lineTo(nipWidth, cornerRadius);
      path.arcToPoint(Offset(nipWidth + cornerRadius, 0),
          radius: Radius.circular(cornerRadius));
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// --- Modelo ChatMessage (Sin cambios) ---
class ChatMessage {
  final String text;
  final int senderId;
  final bool isMe;
  final DateTime createdAt;

  ChatMessage({
    required this.text,
    required this.senderId,
    required this.isMe,
    required this.createdAt,
  });
}

// --- Pantalla Principal ChatScreen ---
class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> conversationData;
  const ChatScreen({super.key, required this.conversationData});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  String _chatTitle = "Chat";
  final ScrollController _scrollController = ScrollController();
  final CryptoService _cryptoService = CryptoService();
  final ConversationApi _conversationApi = ConversationApi();
  StreamSubscription? _messageSubscription;
  late final int _currentUserId;
  String? _privateKeyPem;
  bool _isLoadingHistory = true;
  bool _hasMissingPrivateKey = false;
  bool _hasInitializationError = false;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  static const int _pageSize = 30;
  bool _isGroupChat = false;
  Map<int, String> _participantNames = {};

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    final chatStateService = context.read<ChatStateService>();

    if (authService.userId == null || authService.token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isLoadingHistory = false;
            _hasMissingPrivateKey = true;
            _hasInitializationError = true;
          });
        }
      });
      return;
    }
    _currentUserId = authService.userId!;
    _setupConversationDetails();
    _initializeChat(authService);
    _setupSocketListener();
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId != null) {
      chatStateService.setActiveChat(conversationId);
    }
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
              _scrollController.position.maxScrollExtent &&
          !_isLoadingMore &&
          _hasMoreMessages) {
        _loadMoreMessages();
      }
    });
  }
  
  Future<void> _refreshParticipantsFromApi() async {
    print("ChatScreen: Refrescando participantes desde la API...");
    try {
      final token = context.read<AuthService>().token;
      if (token == null) throw Exception("No autenticado");

      final conversationId = (widget.conversationData['id'] as num).toInt();
      final List<dynamic> participantsList = 
          await _conversationApi.getParticipants(token, conversationId);

      if (!mounted) return;

      final newParticipantNames = <int, String>{};
      for (var p in participantsList) {
        if (p is Map) {
          final userId = (p['userId'] as num?)?.toInt();
          final username = p['username'] as String?;
          if (userId != null && username != null) {
            newParticipantNames[userId] = username;
          }
        }
      }

      setState(() {
        _participantNames = newParticipantNames;
        widget.conversationData['participants'] = participantsList;
        _setupConversationDetails(); 
      });
      print("ChatScreen: Participantes actualizados. Total: ${_participantNames.length}");
    } catch (e) {
      print("ChatScreen [_refreshParticipantsFromApi] ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al refrescar participantes: ${e.toString()}'))
        );
      }
    }
  }
  
  void _setupConversationDetails() {
    final String? type = widget.conversationData['type'] as String?;
    _isGroupChat = (type == 'group');
    final List? participants = widget.conversationData['participants'] as List?;
    if (participants != null) {
      _participantNames.clear(); 
      for (var p in participants) {
        if (p is Map) {
          final userId = (p['userId'] as num?)?.toInt();
          final username = p['username'] as String?;
          if (userId != null && username != null) {
            _participantNames[userId] = username;
          }
        }
      }
    }
    final explicitTitle = widget.conversationData['title'] as String?;
    if (_isGroupChat && explicitTitle != null && explicitTitle.isNotEmpty) {
      _chatTitle = explicitTitle;
    } else {
      final otherParticipant = participants?.firstWhere(
          (p) => p is Map && p['userId'] != null && p['userId'] != _currentUserId,
          orElse: () => null);
      if (otherParticipant != null) {
        _chatTitle = otherParticipant['username'] ?? 'Usuario ${otherParticipant['userId']}';
      } else {
        _chatTitle = explicitTitle ?? 'Conversación ${widget.conversationData['id']}';
      }
    }
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  Future<void> _initializeChat(AuthService authService) async {
    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
        _hasMissingPrivateKey = false;
        _hasInitializationError = false;
      });
    }
    try {
      _privateKeyPem = await authService.getPrivateKeyForSession();
      if (_privateKeyPem == null) {
        if (mounted) {
          setState(() {
            _hasMissingPrivateKey = true;
            _hasInitializationError = true;
            _isLoadingHistory = false;
          });
        }
        return;
      }
      final token = authService.token;
      if (token != null) {
        await _loadAndDecryptHistory(token, page: 0);
      } else {
        throw Exception("Token nulo al inicializar chat.");
      }
    } catch (e) {
      print("ChatScreen [_initializeChat] ERROR: $e");
      if (mounted) {
        setState(() {
          if (!_hasMissingPrivateKey) _hasInitializationError = true;
          _isLoadingHistory = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al inicializar: ${e.toString()}')));
      }
    } finally {
      if (mounted && _isLoadingHistory) {
        setState(() { _isLoadingHistory = false; });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;
    setState(() { _isLoadingMore = true; });
    try {
      final token = context.read<AuthService>().token;
      if (token == null) throw Exception("No autenticado");
      await _loadAndDecryptHistory(token, page: _currentPage + 1);
    } catch (e) {
      print("ChatScreen [_loadMoreMessages] ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar más mensajes: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() { _isLoadingMore = false; });
      }
    }
  }

  Future<void> _loadAndDecryptHistory(String token, {required int page}) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) throw Exception("ID de conversación inválido.");
    if (_privateKeyPem == null) {
      throw Exception(
          "Clave privada nula, no se puede descifrar historial.");
    }
    try {
      final pagedData = await _conversationApi.getMessagesPaged(
          token, conversationId, page, _pageSize);
      if (!mounted) return;
      setState(() {
        _hasMoreMessages = !(pagedData['last'] as bool? ?? true);
        _currentPage = pagedData['number'] as int? ?? 0;
        _totalPages = pagedData['totalPages'] as int? ?? 0;
      });
      final List historyData = pagedData['content'] as List? ?? [];
      if (historyData.isEmpty) {
        return;
      }
      List<ChatMessage> decryptedPage = [];
      for (var msgData in historyData) {
        if (msgData is! Map<String, dynamic>) {
          continue;
        }
        final ChatMessage? msg = await _decryptMessagePayload(msgData);
        if (msg != null) {
          decryptedPage.add(msg);
        }
      }
      if (mounted) {
        setState(() {
          _messages.insertAll(0, decryptedPage);
        });
        if (page == 0) {
          _scrollToBottom();
        }
      }
    } catch (apiError) {
      print("ChatScreen [_loadAndDecryptHistory] ERROR API: $apiError");
      if (mounted) {
        setState(() { _hasInitializationError = true; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al cargar historial: ${apiError.toString()}')));
      }
    }
  }

  Future<ChatMessage?> _decryptMessagePayload(
      Map<String, dynamic> msgData) async {
    if (_privateKeyPem == null) return null;
    try {
      final ciphertext = msgData['ciphertext'] as String?;
      final senderId = (msgData['senderId'] as num?)?.toInt();
      final createdAtStr = msgData['createdAt'] as String?;
      String? encryptedCombinedKey;
      if (msgData.containsKey('encryptedKey')) {
        encryptedCombinedKey = msgData['encryptedKey'] as String?;
      } else if (msgData.containsKey('encryptedKeys')) {
        final encryptedKeysMap =
            msgData['encryptedKeys'] as Map<String, dynamic>?;
        encryptedCombinedKey =
            encryptedKeysMap?[_currentUserId.toString()] as String?;
      }
      if (ciphertext == null ||
          encryptedCombinedKey == null ||
          senderId == null) {
        return null;
      }
      final combinedKeyIV =
          await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final base64AesKey = aesKeyMap['key'];
      final base64AesIV = aesKeyMap['iv'];
      if (base64AesKey == null || base64AesIV == null) {
        return null;
      }
      final plainText =
          _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
      final createdAt =
          DateTime.tryParse(createdAtStr ?? '')?.toLocal() ?? DateTime.now();
      return ChatMessage(
        text: plainText,
        senderId: senderId,
        isMe: senderId == _currentUserId,
        createdAt: createdAt,
      );
    } catch (e) {
      print("ChatScreen [_decryptMessagePayload] ERROR: $e");
      return null;
    }
  }
  
  void _setupSocketListener() {
    _messageSubscription =
        SocketService.instance.messages.listen((StompFrame frame) {
      _onMessageReceived(frame);
    });
  }

  Future<void> _onMessageReceived(StompFrame frame) async {
    if (frame.body == null || frame.body!.isEmpty || _privateKeyPem == null) {
      return;
    }
    try {
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);
      final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
      final expectedConversationId =
          (widget.conversationData['id'] as num?)?.toInt();
      if (conversationId == null ||
          expectedConversationId == null ||
          conversationId != expectedConversationId) {
        return;
      }
      final ChatMessage? newMessage = await _decryptMessagePayload(decodedBody);
      if (newMessage == null) {
        return;
      }
      if (newMessage.isMe) {
        final alreadyExists = _messages.any(
            (msg) => msg.isMe && msg.text == newMessage.text);
        if (alreadyExists) {
          return;
        }
      }
      if (mounted) {
        setState(() {
          _messages.insert(0, newMessage);
        });
        _scrollToBottom();
      }
    } catch (e) {
      print("ChatScreen [_onMessageReceived] ERROR procesando STOMP: $e");
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) {
      return;
    }
    final plainTextMessage = messageText;
    final now = DateTime.now();
    final localMessage = ChatMessage(
        text: plainTextMessage,
        senderId: _currentUserId,
        isMe: true,
        createdAt: now);
    if (mounted) {
      setState(() {
        _messages.insert(0, localMessage);
      });
    }
    _messageController.clear();
    _scrollToBottom();
    
    final List<int> allParticipantIds = _participantNames.keys.toList();

    if (allParticipantIds.isEmpty) {
      await _refreshParticipantsFromApi();
      final refreshedParticipantIds = _participantNames.keys.toList();
      
      if (refreshedParticipantIds.isEmpty) {
          if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Error: Sin destinatarios.')));
          setState(() {
            _messages.remove(localMessage);
          });
        }
        return;
      }
      
      if (!refreshedParticipantIds.contains(_currentUserId)) {
         refreshedParticipantIds.add(_currentUserId);
      }
       await _sendEncryptedMessage(plainTextMessage, refreshedParticipantIds);

    } else {
      if (!allParticipantIds.contains(_currentUserId)) {
        allParticipantIds.add(_currentUserId);
      }
       await _sendEncryptedMessage(plainTextMessage, allParticipantIds);
    }
  }

  Future<void> _sendEncryptedMessage(String plainTextMessage, List<int> participantIds) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: ID de conversación inválido.')));
      }
      return;
    }
    try {
      await SocketService.instance.sendMessage(
          conversationId, plainTextMessage, participantIds);
    } catch (e) {
      print("ChatScreen [_sendMessage] ERROR al enviar: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al enviar: ${e.toString()}')));
      }
    }
  }

  @override
  void dispose() {
    print("ChatScreen [dispose]: Cancelando subscripción y liberando...");
    context.read<ChatStateService>().setActiveChat(null);
    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    if (_isLoadingHistory) {
      bodyContent = const Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Cargando chat seguro...")
          ]));
    } else if (_hasMissingPrivateKey) {
      bodyContent = _buildMissingKeyError();
    } else if (_hasInitializationError) {
      bodyContent = _buildGenericError(); 
    } else {
      bodyContent = _buildMessagesList(); 
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_chatTitle),
        actions: [
          if (_isGroupChat)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Detalles del grupo',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => ChatDetailsScreen(
                      conversationData: widget.conversationData,
                    ),
                  ),
                ).then((_) {
                  _refreshParticipantsFromApi();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: bodyContent),
          if (!_isLoadingHistory &&
              !_hasMissingPrivateKey &&
              !_hasInitializationError)
            _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMissingKeyError() { 
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 20),
            const Text("Clave de Seguridad No Disponible", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("No se puede acceder a los mensajes cifrados. Asegúrate de haber iniciado sesión correctamente en este dispositivo.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text("Volver"),
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))
            )
          ]
        )
      )
    );
  }
  
  Widget _buildGenericError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 20),
            const Text("Error al Cargar el Chat", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text("No se pudo inicializar la conversación. Por favor, verifica tu conexión o inténtalo más tarde.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text("Volver"),
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12))
            )
          ]
        )
      )
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(8.0),
      itemCount: _messages.length + 1,
      itemBuilder: (ctx, index) {
        if (index == _messages.length) {
          return _buildLoadingMoreIndicator();
        }
        final msg = _messages[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: ChatBubble(
            text: msg.text,
            isMe: msg.isMe,
            createdAt: msg.createdAt,
            isGroupChat: _isGroupChat,
            senderName: _participantNames[msg.senderId],
          ),
        );
      },
    );
  }

  Widget _buildLoadingMoreIndicator() {
    if (!_hasMoreMessages) return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Center(
        child: _isLoadingMore
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
        decoration: BoxDecoration(
            color: Colors.grey[50],
            border:
                Border(top: BorderSide(color: Colors.grey[200]!, width: 1.0))),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: SafeArea(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: TextField(
                  controller: _messageController,
                  // --- ¡AQUÍ ESTÁ EL CAMBIO! ---
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) {
                    if (_messageController.text.trim().isNotEmpty) {
                      _sendMessage();
                    }
                  },
                  // --- FIN DEL CAMBIO ---
                  decoration: InputDecoration(
                      hintText: 'Escribe tu mensaje seguro...',
                      hintStyle:
                          Theme.of(context).inputDecorationTheme.hintStyle,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide:
                              BorderSide(color: Theme.of(context).dividerColor)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide(
                              color: Theme.of(context).primaryColor,
                              width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      isDense: true),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 5,
                  minLines: 1)),
          const SizedBox(width: 8),
          SizedBox(
              height: 48,
              width: 48,
              child: IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).hintColor,
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder()),
                  icon: Icon(Icons.send_rounded,
                      color: Theme.of(context).primaryColorDark, size: 24),
                  tooltip: "Enviar mensaje",
                  onPressed: _sendMessage))
        ])));
  }
}