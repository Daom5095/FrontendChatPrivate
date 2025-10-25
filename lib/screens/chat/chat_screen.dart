// lib/screens/chat/chat_screen.dart

// ... (imports sin cambios) ...
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart';
import 'dart:convert';

// ... (Clase ChatMessage sin cambios) ...
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
  // ... (Propiedades _messageController, _messages, _chatTitle, etc. sin cambios) ...
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  String _chatTitle = "Chat";
  final SocketService _socketService = SocketService();
  final CryptoService _cryptoService = CryptoService();
  final ConversationApi _conversationApi = ConversationApi();
  late final int _currentUserId;
  String? _privateKeyPem;
  bool _isLoadingHistory = true;
  bool _hasMissingPrivateKey = false;
  bool _hasInitializationError = false;


  @override
  void initState() {
    super.initState();
    // ... (Validación inicial y _initializeChat sin cambios) ...
    print("ChatScreen [initState]: Iniciando pantalla para conversación ID ${widget.conversationData['id']}");
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.userId == null || authService.token == null) {
       print("ChatScreen [initState] ERROR CRÍTICO: userId o token es null. No se puede continuar.");
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
    print("ChatScreen [initState]: Usuario actual ID: $_currentUserId");
    _setupChatTitle();
    _initializeChat(authService);
  }

  // _setupChatTitle (sin cambios)
  void _setupChatTitle() { /* ... (sin cambios) ... */
    final explicitTitle = widget.conversationData['title'] as String?;
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      _chatTitle = explicitTitle;
      print("ChatScreen [_setupChatTitle]: Usando título explícito: $_chatTitle");
      return;
    }
    final participants = widget.conversationData['participants'] as List?;
    if (participants != null) {
      final otherParticipant = participants.firstWhere(
        (p) => p is Map && p['userId'] != null && p['userId'] != _currentUserId,
        orElse: () => null,
      );
      if (otherParticipant != null) {
        final username = otherParticipant['username'] as String?;
        if (username != null && username.isNotEmpty) {
          _chatTitle = 'Chat con $username';
          print("ChatScreen [_setupChatTitle]: Usando nombre de participante: $_chatTitle");
          return;
        } else {
          final userId = otherParticipant['userId'];
          _chatTitle = 'Chat con Usuario $userId';
           print("ChatScreen [_setupChatTitle]: Usando ID de participante (fallback): $_chatTitle");
          return;
        }
      }
    }
    _chatTitle = 'Conversación ${widget.conversationData['id']}';
    print("ChatScreen [_setupChatTitle]: Usando ID de conversación (fallback): $_chatTitle");
    if (mounted) {
       setState(() {});
    }
  }

  // _initializeChat (sin cambios)
  Future<void> _initializeChat(AuthService authService) async { /* ... (sin cambios) ... */
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
         print("ChatScreen [_initializeChat] ERROR: No se pudo obtener la clave privada desde AuthService.");
         if (mounted) {
           setState(() {
             _hasMissingPrivateKey = true;
             _hasInitializationError = true;
             _isLoadingHistory = false;
           });
         }
         return;
      }
      print("ChatScreen [_initializeChat]: Clave privada obtenida con éxito.");
      final token = authService.token;
      if (token != null) {
        print("ChatScreen [_initializeChat]: Cargando y descifrando historial...");
        await _loadAndDecryptHistory(token);
        print("ChatScreen [_initializeChat]: Historial procesado.");
      } else {
         throw Exception("Token nulo al intentar cargar historial (esto no debería ocurrir).");
      }
       if (token != null) {
         print("ChatScreen [_initializeChat]: Conectando al WebSocket...");
         _socketService.connect(token, _onMessageReceived);
         print("ChatScreen [_initializeChat]: Solicitud de conexión WebSocket enviada.");
       } else {
          throw Exception("Token nulo al intentar conectar al socket (esto no debería ocurrir).");
       }
    } catch (e) {
      print("ChatScreen [_initializeChat] ERROR durante la inicialización: $e");
       if (mounted) {
         setState(() {
           if (!_hasMissingPrivateKey) _hasInitializationError = true;
           _isLoadingHistory = false;
         });
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error al inicializar el chat: ${e.toString()}'))
         );
       }
    } finally {
      if (mounted && _isLoadingHistory) {
        setState(() { _isLoadingHistory = false; });
         print("ChatScreen [_initializeChat]: Carga inicial completada.");
      }
    }
  }


  /// Carga el historial de mensajes y los descifra.
  Future<void> _loadAndDecryptHistory(String token) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) { /* ... (manejo de error) ... */
       throw Exception("ID de conversación inválido en widget.conversationData.");
    }
    if (_privateKeyPem == null) { /* ... (manejo de error) ... */
       throw Exception("Intento de cargar historial sin clave privada disponible.");
    }

    try {
      print("ChatScreen [_loadAndDecryptHistory]: Solicitando historial para conv $conversationId...");
      final historyData = await _conversationApi.getMessages(token, conversationId);
      if (!mounted) return;
      if (historyData.isEmpty) { /* ... (manejo de historial vacío) ... */
        print("ChatScreen [_loadAndDecryptHistory]: Historial vacío para conversación $conversationId.");
        return;
      }

      print("ChatScreen [_loadAndDecryptHistory]: Recibidos ${historyData.length} mensajes. Descifrando...");
      List<ChatMessage> decryptedHistory = [];
      int successCount = 0;
      int errorCount = 0;

      for (var msgData in historyData) {
        if (msgData is! Map<String, dynamic>) { /* ... (manejo de error) ... */
           print("ChatScreen [_loadAndDecryptHistory] Warning: Elemento de historial no es un mapa. Saltando: $msgData");
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
             print("ChatScreen [_loadAndDecryptHistory] Warning: Datos incompletos en mensaje de historial ID $messageId. Saltando.");
             errorCount++;
             continue;
          }

          final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!);
          final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
          final base64AesKey = aesKeyMap['key'];
          final base64AesIV = aesKeyMap['iv'];

          if (base64AesKey == null || base64AesIV == null) {
             print("ChatScreen [_loadAndDecryptHistory] Error: Fallo al separar clave/IV descifrada del historial para mensaje ID $messageId. Saltando.");
             errorCount++;
             continue;
          }

          // --- ACTUALIZADO al método renombrado ---
          final plainText = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
          // ------------------------------------

          final createdAt = DateTime.parse(createdAtStr).toLocal();

          decryptedHistory.add(ChatMessage(
            text: plainText,
            senderId: senderId,
            isMe: senderId == _currentUserId,
            createdAt: createdAt,
          ));
          successCount++;

        } catch (e) { /* ... (manejo de error de descifrado individual) ... */
           errorCount++;
          final messageId = (msgData['messageId'] as num?)?.toInt() ?? 'desconocido';
          print("ChatScreen [_loadAndDecryptHistory] Error al descifrar mensaje del historial ID $messageId: $e");
        }
      } // Fin for

      decryptedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (mounted) {
        setState(() {
          _messages.addAll(decryptedHistory);
        });
        print("ChatScreen [_loadAndDecryptHistory]: Historial procesado. Éxito: $successCount, Errores: $errorCount");
      }

    } catch (apiError) { /* ... (manejo de error de API) ... */
       print("ChatScreen [_loadAndDecryptHistory] ERROR al llamar a la API de mensajes: $apiError");
       if(mounted) {
          setState(() {
             _hasInitializationError = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error al cargar el historial: ${apiError.toString()}'))
          );
       }
    }
  }

  /// Callback para manejar mensajes nuevos de WebSocket.
  Future<void> _onMessageReceived(StompFrame frame) async {
    if (frame.body == null || frame.body!.isEmpty) { /* ... (manejo de error) ... */
       print("ChatScreen [_onMessageReceived]: Mensaje STOMP recibido sin cuerpo o vacío.");
       return;
     }
    if (_privateKeyPem == null) { /* ... (manejo de error) ... */
      print("ChatScreen [_onMessageReceived] ERROR: Recibido mensaje STOMP pero falta clave privada para descifrar.");
      return;
    }

    print("ChatScreen [_onMessageReceived]: Mensaje STOMP recibido: ${frame.body?.substring(0, min(frame.body!.length, 150))}...");

    try {
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);

      final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
      final expectedConversationId = (widget.conversationData['id'] as num?)?.toInt();
      if (conversationId == null || expectedConversationId == null || conversationId != expectedConversationId) {
         print("ChatScreen [_onMessageReceived]: Mensaje STOMP ignorado (ID conversación $conversationId no coincide con el esperado $expectedConversationId o es nulo).");
         return;
      }

      final senderId = (decodedBody['senderId'] as num?)?.toInt();
      if (senderId == null) { /* ... (manejo de error) ... */
         print("ChatScreen [_onMessageReceived] Error: senderId nulo en mensaje STOMP.");
         return;
      }
      if (senderId == _currentUserId) { /* ... (ignorar eco) ... */
         print("ChatScreen [_onMessageReceived]: Mensaje STOMP ignorado (eco del propio mensaje enviado).");
         return;
      }

      final ciphertext = decodedBody['ciphertext'] as String?;
      final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;
      if (ciphertext == null || encryptedKeysMap == null) { /* ... (manejo de error) ... */
         print("ChatScreen [_onMessageReceived] Error: Falta ciphertext o encryptedKeys en mensaje STOMP.");
         return;
      }

      final encryptedCombinedKey = encryptedKeysMap[_currentUserId.toString()] as String?;
      if (encryptedCombinedKey == null) { /* ... (manejo de error) ... */
         print("ChatScreen [_onMessageReceived] Error: No se encontró clave cifrada para mi ID ($_currentUserId) en mensaje STOMP. No puedo descifrar.");
         return;
      }

      final combinedKeyIV = await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final base64AesKey = aesKeyMap['key'];
      final base64AesIV = aesKeyMap['iv'];

      if (base64AesKey == null || base64AesIV == null) { /* ... (manejo de error) ... */
        print("ChatScreen [_onMessageReceived] Error: Fallo al separar clave/IV descifrada de mensaje STOMP.");
        return;
      }

      // --- ACTUALIZADO al método renombrado ---
      final plainTextMessage = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
      // ------------------------------------

      final createdAt = DateTime.now();
      final newMessage = ChatMessage(
        text: plainTextMessage,
        senderId: senderId,
        isMe: false,
        createdAt: createdAt,
      );

      if (mounted) {
        setState(() {
          _messages.add(newMessage);
        });
         print("ChatScreen [_onMessageReceived]: Mensaje STOMP (de $senderId) descifrado y añadido a la UI.");
      }

    } catch (e) { /* ... (manejo de error general) ... */
      print("ChatScreen [_onMessageReceived] ERROR al procesar/descifrar mensaje STOMP: $e");
      print("ChatScreen [_onMessageReceived] Cuerpo del mensaje STOMP con error: ${frame.body}");
    }
  }

  // _sendMessage (sin cambios, ya usa SocketService que fue actualizado)
  Future<void> _sendMessage() async { /* ... (sin cambios) ... */
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) {
       print("ChatScreen [_sendMessage]: Intento de enviar mensaje vacío.");
       return;
     }
    final plainTextMessage = messageText;
    final now = DateTime.now();
    final localMessage = ChatMessage(
      text: plainTextMessage,
      senderId: _currentUserId,
      isMe: true,
      createdAt: now,
    );
    if (mounted) {
      setState(() {
        _messages.add(localMessage);
      });
    }
    _messageController.clear();

    final List<dynamic>? participants = widget.conversationData['participants'];
    final List<int> allParticipantIds = participants
            ?.map<int?>((p) => (p is Map && p['userId'] is num) ? (p['userId'] as num).toInt() : null)
            .where((id) => id != null)
            .cast<int>()
            .toList() ?? [];

     if (allParticipantIds.isEmpty) {
        print("ChatScreen [_sendMessage] ERROR: No se encontraron IDs de participantes válidos en conversationData. No se puede enviar.");
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Error: No se pueden determinar los destinatarios del mensaje.'))
            );
            setState(() { _messages.remove(localMessage); });
         }
        return;
     }
     if (!allParticipantIds.contains(_currentUserId)) {
         allParticipantIds.add(_currentUserId);
          print("ChatScreen [_sendMessage]: Añadido ID propio a la lista de participantes para cifrado.");
     }

    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) {
       print("ChatScreen [_sendMessage] ERROR: ID de conversación nulo. No se puede enviar.");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: ID de conversación inválido.'))
           );
           setState(() { _messages.remove(localMessage); });
        }
       return;
    }

    try {
      print("ChatScreen [_sendMessage]: Enviando mensaje '$plainTextMessage' a SocketService para conv $conversationId, participantes: $allParticipantIds");
      await _socketService.sendMessage(
        conversationId,
        plainTextMessage,
        allParticipantIds,
      );
       print("ChatScreen [_sendMessage]: Llamada a socketService.sendMessage completada.");
    } catch (e) {
      print("ChatScreen [_sendMessage] ERROR al llamar a socketService.sendMessage: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error al enviar mensaje: ${e.toString()}'))
        );
        setState(() {
           _messages.remove(localMessage);
        });
      }
    }
  }


  // dispose (sin cambios)
  @override
  void dispose() { /* ... (sin cambios) ... */
     print("ChatScreen [dispose]: Desconectando socket y liberando recursos...");
    _socketService.disconnect();
    _messageController.dispose();
    super.dispose();
  }

  // build (sin cambios)
  @override
  Widget build(BuildContext context) { /* ... (sin cambios) ... */
     Widget bodyContent;
    if (_isLoadingHistory) {
      bodyContent = const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Cargando chat seguro...")]));
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

  // _buildMissingKeyError (sin cambios)
  Widget _buildMissingKeyError() { /* ... (sin cambios) ... */
     return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.lock_outline, size: 64, color: Colors.orangeAccent), const SizedBox(height: 20), const Text("Clave de Seguridad No Disponible", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text("No se puede acceder a los mensajes cifrados. Asegúrate de haber iniciado sesión correctamente en este dispositivo.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)), const SizedBox(height: 24), ElevatedButton.icon(icon: const Icon(Icons.arrow_back), label: const Text("Volver"), onPressed: () => Navigator.of(context).pop(), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)))])));
  }

  // _buildGenericError (sin cambios)
  Widget _buildGenericError() { /* ... (sin cambios) ... */
    return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, size: 64, color: Colors.redAccent), const SizedBox(height: 20), const Text("Error al Cargar el Chat", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text("No se pudo inicializar la conversación. Por favor, verifica tu conexión o inténtalo más tarde.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)), const SizedBox(height: 24), ElevatedButton.icon(icon: const Icon(Icons.arrow_back), label: const Text("Volver"), onPressed: () => Navigator.of(context).pop(), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)))])));
  }

  // _buildMessagesList (sin cambios)
  Widget _buildMessagesList() { /* ... (sin cambios) ... */
     return ListView.builder(reverse: false, padding: const EdgeInsets.all(8.0), itemCount: _messages.length, itemBuilder: (ctx, index) { final msg = _messages[index]; final alignment = msg.isMe ? Alignment.centerRight : Alignment.centerLeft; final bubbleColor = msg.isMe ? Theme.of(context).primaryColorLight.withOpacity(0.8) : Colors.grey[200]; final textColor = msg.isMe ? Colors.black87 : Colors.black87; final borderRadius = BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: msg.isMe ? const Radius.circular(16) : Radius.zero, bottomRight: msg.isMe ? Radius.zero : const Radius.circular(16)); return Align(alignment: alignment, child: Container(margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), decoration: BoxDecoration(color: bubbleColor, borderRadius: borderRadius, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), spreadRadius: 0.5, blurRadius: 1.5, offset: const Offset(0, 1))]), child: Text(msg.text, style: TextStyle(color: textColor, fontSize: 15)))); });
  }

  // _buildMessageInput (sin cambios)
  Widget _buildMessageInput() { /* ... (sin cambios) ... */
    return Container(decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5))), padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), child: SafeArea(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _messageController, decoration: InputDecoration(hintText: 'Escribe tu mensaje seguro...', filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(25.0), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), isDense: true), textCapitalization: TextCapitalization.sentences, maxLines: 5, minLines: 1)), const SizedBox(width: 8), SizedBox(height: 48, width: 48, child: IconButton.filled(style: IconButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, padding: EdgeInsets.zero, shape: const CircleBorder()), icon: const Icon(Icons.send_rounded, color: Colors.white, size: 24), tooltip: "Enviar mensaje", onPressed: _sendMessage))])));
  }

} // Fin clase _ChatScreenState