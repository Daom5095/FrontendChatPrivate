// lib/screens/chat/chat_screen.dart

import 'dart:async'; // Corregido (requerido para StreamSubscription)
import 'dart:math'; // Corregido (requerido para min())
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart';
import '../../services/chat_state_service.dart';
import 'dart:convert'; // Corregido (requerido para json.decode)

// ... (El resto de la clase ChatScreen y sus widgets internos no cambian) ...
// ... (El widget ChatBubble y BubbleClipper no cambian) ...
// --- Widget ChatBubble ---
class ChatBubble extends StatelessWidget {
// ... (código idéntico) ...
  final String text;
  final bool isMe;
  final DateTime createdAt; 

  const ChatBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormatter = DateFormat('HH:mm');
    final timeString = timeFormatter.format(createdAt);
    final bubbleColor = isMe
        ? Theme.of(context).primaryColor
        : Colors.grey[100];
    final textColor = isMe 
        ? Colors.white 
        : Theme.of(context).textTheme.bodyMedium?.color;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;

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

// --- Widget BubbleClipper ---
class BubbleClipper extends CustomClipper<Path> {
// ... (código idéntico) ...
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
      path.arcToPoint(Offset(width - nipWidth, cornerRadius), radius: Radius.circular(cornerRadius)); 
      path.lineTo(width - nipWidth, height - nipHeight - cornerRadius); 
      path.lineTo(width, height - cornerRadius);
      path.arcToPoint(Offset(width - nipWidth - cornerRadius, height), radius: Radius.circular(cornerRadius)); 
      path.lineTo(cornerRadius, height); 
      path.arcToPoint(Offset(0, height - cornerRadius), radius: Radius.circular(cornerRadius)); 
      path.lineTo(0, cornerRadius); 
      path.arcToPoint(Offset(cornerRadius, 0), radius: Radius.circular(cornerRadius)); 
    } else {
      path.moveTo(nipWidth + cornerRadius, 0); 
      path.lineTo(width - cornerRadius, 0); 
      path.arcToPoint(Offset(width, cornerRadius), radius: Radius.circular(cornerRadius)); 
      path.lineTo(width, height - cornerRadius); 
      path.arcToPoint(Offset(width - cornerRadius, height), radius: Radius.circular(cornerRadius)); 
      path.lineTo(nipWidth + cornerRadius, height); 
       path.arcToPoint(Offset(nipWidth, height - cornerRadius), radius: Radius.circular(cornerRadius)); 
       path.lineTo(nipWidth, height - cornerRadius - nipHeight); 
       path.lineTo(0, height - cornerRadius);
      path.lineTo(nipWidth, cornerRadius); 
      path.arcToPoint(Offset(nipWidth + cornerRadius, 0), radius: Radius.circular(cornerRadius)); 
    }
    path.close();
    return path;
  }
  
  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ... (El modelo ChatMessage no cambia) ...
class ChatMessage {
// ... (código idéntico) ...
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
  // ... (controladores, listas y servicios no cambian) ...
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

  @override
  void initState() {
    super.initState();
    print("ChatScreen [initState]: Iniciando pantalla para conversación ID ${widget.conversationData['id']}");
    
    final authService = Provider.of<AuthService>(context, listen: false);
    // --- MODIFICACIÓN: LEER ChatStateService ---
    final chatStateService = context.read<ChatStateService>();
    // --- FIN MODIFICACIÓN ---

    if (authService.userId == null || authService.token == null) {
       print("ChatScreen [initState] ERROR CRÍTICO: userId o token es null.");
       // ... (lógica de error no cambia) ...
       WidgetsBinding.instance.addPostFrameCallback((_) { 
         if (mounted) { 
           setState(() { _isLoadingHistory = false; _hasMissingPrivateKey = true; _hasInitializationError = true; }); 
         } 
       });
       return;
    }

    _currentUserId = authService.userId!;
    print("ChatScreen [initState]: Usuario actual ID: $_currentUserId");

    _setupChatTitle();
    _initializeChat(authService);
    
    // --- MODIFICACIÓN: NOTIFICAR AL SERVICIO DE ESTADO ---
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId != null) {
      print("ChatScreen [initState]: Estableciendo chat activo: $conversationId");
      chatStateService.setActiveChat(conversationId);
    }
    // --- FIN MODIFICACIÓN ---

    _setupSocketListener();
  }

  // ... (los métodos _scrollToBottom, _setupChatTitle, _initializeChat, _loadAndDecryptHistory
  //     y _setupSocketListener no cambian) ...
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setupChatTitle() {
    final explicitTitle = widget.conversationData['title'] as String?;
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      _chatTitle = explicitTitle;
      return;
    }
    final participants = widget.conversationData['participants'] as List?;
    if (participants != null) {
      final otherParticipant = participants.firstWhere(
        (p) => p is Map && p['userId'] != null && p['userId'] != _currentUserId, 
        orElse: () => null
      );
      if (otherParticipant != null) {
        final username = otherParticipant['username'] as String?;
        if (username != null && username.isNotEmpty) {
          _chatTitle = 'Chat con $username';
          return;
        } else {
          final userId = otherParticipant['userId'];
          _chatTitle = 'Chat con Usuario $userId';
          return;
        }
      }
    }
    _chatTitle = 'Conversación ${widget.conversationData['id']}';
    if (mounted) { setState(() {}); }
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
      print("ChatScreen [_initializeChat]: Obteniendo clave privada...");
      _privateKeyPem = await authService.getPrivateKeyForSession();
      
      if (_privateKeyPem == null) { 
        print("ChatScreen [_initializeChat] ERROR: No se pudo obtener la clave privada.");
        if (mounted) { 
          setState(() { 
            _hasMissingPrivateKey = true; 
            _hasInitializationError = true; 
            _isLoadingHistory = false; 
          }); 
        } 
        return;
      }
      print("ChatScreen [_initializeChat]: Clave privada obtenida.");

      final token = authService.token;
      if (token != null) {
        print("ChatScreen [_initializeChat]: Cargando historial de mensajes...");
        await _loadAndDecryptHistory(token);
        print("ChatScreen [_initializeChat]: Historial cargado.");
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al inicializar: ${e.toString()}'))); 
      }
    } finally {
      if (mounted && _isLoadingHistory) { 
        setState(() { _isLoadingHistory = false; }); 
        print("ChatScreen [_initializeChat]: Inicialización finalizada.");
      }
    }
  }

  Future<void> _loadAndDecryptHistory(String token) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) { throw Exception("ID de conversación inválido."); }
    if (_privateKeyPem == null) { throw Exception("Clave privada nula, no se puede descifrar historial."); }

    try {
      final historyData = await _conversationApi.getMessages(token, conversationId);
      if (!mounted) return;
      if (historyData.isEmpty) { 
        return;
      }
      
      List<ChatMessage> decryptedHistory = [];
      int successCount = 0;
      int errorCount = 0;
      
      for (var msgData in historyData) {
        if (msgData is! Map<String, dynamic>) { 
          errorCount++; 
          continue; 
        }
        
        try {
          final messageId = (msgData['messageId'] as num?)?.toInt();
          final ciphertext = msgData['ciphertext'] as String?;
          final encryptedKey = msgData['encryptedKey'] as String?;
          final senderId = (msgData['senderId'] as num?)?.toInt();
          final createdAtStr = msgData['createdAt'] as String?;

          if (ciphertext == null || encryptedKey == null || createdAtStr == null || senderId == null) {
            errorCount++;
            continue;
          }

          final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!);
          final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
          final base64AesKey = aesKeyMap['key'];
          final base64AesIV = aesKeyMap['iv'];

          if (base64AesKey == null || base64AesIV == null) {
            errorCount++;
            continue;
          }

          final plainText = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
          
          final createdAt = DateTime.parse(createdAtStr).toLocal();
          decryptedHistory.add(ChatMessage(
            text: plainText,
            senderId: senderId,
            isMe: senderId == _currentUserId,
            createdAt: createdAt,
          ));
          successCount++;
        } catch (e) {
          errorCount++;
          final messageId = (msgData['messageId'] as num?)?.toInt() ?? 'desconocido';
          print("ChatScreen [_loadAndDecryptHistory] ERROR al descifrar msg $messageId: $e");
        }
      } 

      decryptedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      if (mounted) {
        setState(() {
          _messages.addAll(decryptedHistory);
        });
        _scrollToBottom();
      }
    } catch (apiError) {
      print("ChatScreen [_loadAndDecryptHistory] ERROR API: $apiError");
      if(mounted) { 
        setState(() { _hasInitializationError = true; }); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar historial: ${apiError.toString()}'))); 
      }
    }
  }

  void _setupSocketListener() {
    print("ChatScreen [_setupSocketListener]: Escuchando el stream global de mensajes...");
    _messageSubscription = SocketService.instance.messages.listen((StompFrame frame) {
      _onMessageReceived(frame);
    });
  }

  /// Callback que se ejecuta cuando llega un mensaje del Stream.
  Future<void> _onMessageReceived(StompFrame frame) async {
     // ... (la lógica de _onMessageReceived no cambia) ...
     if (frame.body == null || frame.body!.isEmpty) { 
       return; 
     }
     if (_privateKeyPem == null) {
       return;
     }
     
    print("ChatScreen [_onMessageReceived]: Mensaje STOMP recibido: ${frame.body?.substring(0, min(frame.body!.length, 150))}...");
    
    try {
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);
      
      final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
      final expectedConversationId = (widget.conversationData['id'] as num?)?.toInt();
      if (conversationId == null || expectedConversationId == null || conversationId != expectedConversationId) {
        print("ChatScreen [_onMessageReceived]: Mensaje ignorado (ID de conversación no coincide $conversationId != $expectedConversationId).");
        return;
      }

      final senderId = (decodedBody['senderId'] as num?)?.toInt();
      if (senderId == null) { 
        return;
      }
      final isMe = senderId == _currentUserId;
      
      final ciphertext = decodedBody['ciphertext'] as String?;
      final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;
      if (ciphertext == null || encryptedKeysMap == null) {
        return;
      }

      final encryptedCombinedKey = encryptedKeysMap[_currentUserId.toString()] as String?;
      if (encryptedCombinedKey == null) {
        return;
      }

      final combinedKeyIV = await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final base64AesKey = aesKeyMap['key'];
      final base64AesIV = aesKeyMap['iv'];
      if (base64AesKey == null || base64AesIV == null) {
        return;
      }
      final plainTextMessage = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);

      if (isMe) {
        final alreadyExists = _messages.any((msg) => msg.isMe && msg.text == plainTextMessage);
        if (alreadyExists) {
          print("ChatScreen [_onMessageReceived]: Mensaje ignorado (eco de Optimistic UI ya mostrado).");
          return;
        }
        print("ChatScreen [_onMessageReceived]: Procesando eco (Optimistic UI falló o fue lento).");
      }

      final createdAt = DateTime.now();
      final newMessage = ChatMessage(
        text: plainTextMessage,
        senderId: senderId,
        isMe: isMe,
        createdAt: createdAt
      );
      
      if (mounted) {
        setState(() {
          _messages.add(newMessage);
        });
        _scrollToBottom();
         print("ChatScreen [_onMessageReceived]: Mensaje STOMP (de $senderId) añadido a UI.");
      }
    } catch (e) {
      print("ChatScreen [_onMessageReceived] ERROR procesando STOMP: $e");
      print("ChatScreen [_onMessageReceived]: Cuerpo con error: ${frame.body}");
    }
  }

  /// Envía un nuevo mensaje. (No cambia)
  Future<void> _sendMessage() async {
    // ... (sin cambios en este método) ...
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
      createdAt: now
    );
    
    if (mounted) { 
      setState(() { _messages.add(localMessage); }); 
    }
     _messageController.clear();
     _scrollToBottom(); 

     final List<dynamic>? participants = widget.conversationData['participants'];
     final List<int> allParticipantIds = participants
        ?.map<int?>((p) => (p is Map && p['userId'] is num) ? (p['userId'] as num).toInt() : null)
        .where((id) => id != null)
        .cast<int>()
        .toList() ?? [];

     if (allParticipantIds.isEmpty) {
       if (mounted) { 
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Sin destinatarios.')));
         setState(() { _messages.remove(localMessage); }); 
       }
       return;
     }
     
     if (!allParticipantIds.contains(_currentUserId)) {
       allParticipantIds.add(_currentUserId);
     }
     
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) {
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: ID de conversación inválido.')));
        setState(() { _messages.remove(localMessage); }); 
      }
      return;
    }

    try {
      await SocketService.instance.sendMessage(
        conversationId,
        plainTextMessage,
        allParticipantIds
      );
    } catch (e) {
      print("ChatScreen [_sendMessage] ERROR al enviar: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: ${e.toString()}')));
        setState(() { _messages.remove(localMessage); });
      }
    }
  }

  /// Limpieza al salir de la pantalla.
  @override
  void dispose() {
    print("ChatScreen [dispose]: Cancelando subscripción y liberando...");
    
    // --- MODIFICACIÓN: NOTIFICAR AL SERVICIO DE ESTADO ---
    // Le decimos al servicio que ya no estamos viendo ningún chat
    context.read<ChatStateService>().setActiveChat(null);
    print("ChatScreen [dispose]: Chat activo establecido en null.");
    // --- FIN MODIFICACIÓN ---

    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ... (El método build() y sus helpers (_buildMissingKeyError, _buildGenericError,
  // _buildMessagesList, _buildMessageInput) no cambian en absoluto) ...
  @override
  Widget build(BuildContext context) {
    // ... (código idéntico) ...
    Widget bodyContent;
    if (_isLoadingHistory) {
      bodyContent = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Cargando chat seguro...")
          ]
        )
      );
    } else if (_hasMissingPrivateKey) {
      bodyContent = _buildMissingKeyError();
    } else if (_hasInitializationError) {
      bodyContent = _buildGenericError();
    } else {
      bodyContent = _buildMessagesList();
    } 

    return Scaffold(
      appBar: AppBar(title: Text(_chatTitle)),
      body: Column(
        children: [
          Expanded(child: bodyContent),
          if (!_isLoadingHistory && !_hasMissingPrivateKey && !_hasInitializationError)
             _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMissingKeyError() { 
    // ... (código idéntico) ...
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
    // ... (código idéntico) ...
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
    // ... (código idéntico) ...
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      itemCount: _messages.length,
      itemBuilder: (ctx, index) {
        final msg = _messages[index];
        return Padding(
           padding: const EdgeInsets.symmetric(vertical: 4.0),
           child: ChatBubble(
             text: msg.text,
             isMe: msg.isMe,
             createdAt: msg.createdAt,
           ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    // ... (código idéntico) ...
    return Container(
        decoration: BoxDecoration(
            color: Colors.grey[50], 
            border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1.0))),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: SafeArea(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                      hintText: 'Escribe tu mensaje seguro...',
                      hintStyle: Theme.of(context).inputDecorationTheme.hintStyle, 
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide(color: Theme.of(context).dividerColor)
                      ),
                      focusedBorder: OutlineInputBorder( 
                          borderRadius: BorderRadius.circular(25.0),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5)
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  icon: Icon(
                      Icons.send_rounded,
                      color: Theme.of(context).primaryColorDark, 
                      size: 24),
                  tooltip: "Enviar mensaje",
                  onPressed: _sendMessage))
        ])));
  }
}