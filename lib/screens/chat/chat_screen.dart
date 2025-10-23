// lib/screens/chat/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart'; // <-- IMPORTACIÓN AÑADIDA
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../services/secure_storage.dart';
import '../../api/conversation_api.dart';
import 'dart:convert';

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

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> conversationData;
  const ChatScreen({super.key, required this.conversationData});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _socketService = SocketService();
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  late final int currentUserId;
  String chatTitle = "Chat";

  final CryptoService _cryptoService = CryptoService();
  final SecureStorageService _storageService = SecureStorageService();
  final ConversationApi _conversationApi = ConversationApi();
  String? _privateKeyPem;

  bool _isLoadingHistory = true;
  bool _hasErrorLoading = false;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    // Asegurarse que userId no sea null antes de usarlo
    if (authService.userId == null) {
       // Manejar el caso de error - quizás volver al login
       print("Error crítico: userId es null en initState de ChatScreen.");
       setState(() {
         _isLoadingHistory = false;
         _hasErrorLoading = true;
       });
       // Podrías navegar hacia atrás: Navigator.of(context).pop();
       return;
    }
    currentUserId = authService.userId!;
    _setupChatTitle();
    _initializeChat(authService.token!);
  }

  Future<void> _initializeChat(String token) async {
    setState(() {
      _isLoadingHistory = true;
      _hasErrorLoading = false;
    });
    try {
      await _loadPrivateKey();
      if (_privateKeyPem != null) {
        await _loadAndDecryptHistory(token);
        _socketService.connect(token, _onMessageReceived);
      } else {
         throw Exception("No se pudo cargar la clave privada.");
      }
    } catch (e) {
      print("Error inicializando el chat: $e");
      setState(() { _hasErrorLoading = true; });
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar el chat: $e'))
        );
       }
    } finally {
      if (mounted) {
        setState(() { _isLoadingHistory = false; });
      }
    }
  }

  Future<void> _loadPrivateKey() async {
    _privateKeyPem = await _storageService.getPrivateKey();
    if (_privateKeyPem == null) {
      print("¡Error crítico! No se pudo cargar la clave privada.");
    }
  }

  Future<void> _loadAndDecryptHistory(String token) async {
    print("Cargando historial...");
    final conversationId = (widget.conversationData['id'] as num).toInt();
    final historyData = await _conversationApi.getMessages(token, conversationId);

    if (historyData.isEmpty) {
      print("Historial vacío.");
      return;
    }

    List<ChatMessage> decryptedHistory = [];
    for (var msgData in historyData) {
      try {
        final ciphertext = msgData['ciphertext'] as String?;
        final encryptedKey = msgData['encryptedKey'] as String?;
        final senderId = (msgData['senderId'] as num?)?.toInt(); // Manejar posible null
        final createdAtStr = msgData['createdAt'] as String?;

        if (ciphertext == null || encryptedKey == null || createdAtStr == null || senderId == null) {
          print("Datos incompletos en mensaje de historial: ${msgData['messageId']}");
          continue;
        }

        final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!);
        final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
        final base64AesKey = aesKeyMap['key'];
        final base64AesIV = aesKeyMap['iv'];

        if (base64AesKey == null || base64AesIV == null) {
          print("Error al separar clave/IV del historial para mensaje ${msgData['messageId']}");
          continue;
        }

        final plainText = _cryptoService.decryptAES(ciphertext, base64AesKey, base64AesIV);
        final createdAt = DateTime.parse(createdAtStr).toLocal();

        decryptedHistory.add(ChatMessage(
          text: plainText,
          senderId: senderId,
          isMe: senderId == currentUserId,
          createdAt: createdAt,
        ));

      } catch (e) {
        print("Error al descifrar mensaje del historial ${msgData['messageId']}: $e");
      }
    }

    decryptedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (mounted) {
      setState(() {
        _messages.addAll(decryptedHistory);
      });
      print("Historial cargado y descifrado con ${decryptedHistory.length} mensajes.");
    }
  }

  Future<void> _onMessageReceived(StompFrame frame) async {
     if (frame.body == null || _privateKeyPem == null) {
      print("Mensaje recibido vacío o clave privada no disponible.");
      return;
    }
     try {
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);
      final conversationId = decodedBody['conversationId'];
      if (conversationId == null || conversationId != widget.conversationData['id']) return;
      final senderId = (decodedBody['senderId'] as num?)?.toInt(); // Manejar posible null

      // Validar senderId antes de usarlo
      if (senderId == null) {
        print("Error: senderId es null en el mensaje recibido.");
        return;
      }

      if (senderId == currentUserId) return;

      final ciphertext = decodedBody['ciphertext'] as String?;
      final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;

      if (ciphertext == null || encryptedKeysMap == null) {
         print("Error: Falta ciphertext o encryptedKeys en el mensaje recibido.");
         return;
      }

      final encryptedCombinedKey = encryptedKeysMap[currentUserId.toString()] as String?;
      if (encryptedCombinedKey == null) {
         print("Error: No se encontró la clave cifrada para el usuario actual (ID: $currentUserId) en el mensaje.");
         return;
      }

      final combinedKeyIV = await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final base64AesKey = aesKeyMap['key'];
      final base64AesIV = aesKeyMap['iv'];

      if (base64AesKey == null || base64AesIV == null) {
        print("Error al separar la clave AES y el IV descifrados.");
        return;
      }
      final plainTextMessage = _cryptoService.decryptAES(ciphertext, base64AesKey, base64AesIV);
      final createdAt = DateTime.now();

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: plainTextMessage,
              senderId: senderId,
              isMe: false,
              createdAt: createdAt,
            ),
          );
        });
      }
     } catch (e) {
       print("Error decodificando o DESCIFRANDO mensaje recibido: $e");
       print("Cuerpo del mensaje: ${frame.body}");
     }
  }

  void _setupChatTitle() {
    // ... (sin cambios)
     if (widget.conversationData['title'] != null && widget.conversationData['title'].isNotEmpty) {
      chatTitle = widget.conversationData['title'];
    } else {
      final participants = widget.conversationData['participants'] as List?;
      final otherParticipant = participants?.firstWhere(
        (p) => p['userId'] != currentUserId,
        orElse: () => null,
      );
      if (otherParticipant != null) {
        final username = otherParticipant['username'] ?? 'Usuario ${otherParticipant['userId']}';
        chatTitle = 'Chat con $username';
      } else {
        chatTitle = 'Chat ${widget.conversationData['id']}';
      }
    }
  }

  @override
  void dispose() {
    _socketService.disconnect(); // Llamada correcta
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    // ... (sin cambios)
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    final plainTextMessage = messageText;
    final now = DateTime.now();

    setState(() {
      _messages.add(
        ChatMessage(
          text: plainTextMessage,
          senderId: currentUserId,
          isMe: true,
          createdAt: now,
        ),
      );
    });
    _messageController.clear();

    final List<dynamic>? participants = widget.conversationData['participants'];
    final List<int> allParticipantIds = participants
            ?.map<int>((p) => (p['userId'] as num).toInt())
            .toList() ??
            [];

    try {
      await _socketService.sendMessage(
        (widget.conversationData['id'] as num).toInt(),
        plainTextMessage,
        allParticipantIds,
      );
    } catch (e) {
      print("Error al enviar mensaje desde ChatScreen: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error al enviar mensaje: $e'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (sin cambios)
    Widget bodyContent;
    if (_isLoadingHistory) {
      bodyContent = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text("Cargando historial...")
          ],
        )
      );
    } else if (_hasErrorLoading) {
      bodyContent = const Center(
        child: Text("Error al cargar el chat. Verifica tu conexión e inténtalo de nuevo.", textAlign: TextAlign.center),
      );
    } else if (_privateKeyPem == null) {
       bodyContent = const Center(
         child: Text("Error crítico: No se pudo cargar la clave segura.", textAlign: TextAlign.center),
       );
    }
     else {
      bodyContent = ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _messages.length,
        itemBuilder: (ctx, index) {
          final msg = _messages[index];
          return Align(
            alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: msg.isMe ? Colors.deepPurple[100] : Colors.grey[300],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: msg.isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: msg.isMe ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Text(msg.text),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(chatTitle),
      ),
      body: Column(
        children: [
          Expanded(child: bodyContent),
          if (!_hasErrorLoading && _privateKeyPem != null) _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    // ... (sin cambios)
     return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      color: Theme.of(context).cardColor,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25.0),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.all(12),
              ),
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}