// lib/screens/chat/chat_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:intl/intl.dart'; 
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart';
import 'dart:convert';

// --- Widget ChatBubble (ACTUALIZADO CON NUEVA PALETA) ---
class ChatBubble extends StatelessWidget {
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

    // === CAMBIO DE PALETA ===
    final bubbleColor = isMe
        ? Theme.of(context).primaryColor // Azul primario (#23518C)
        : Colors.grey[100]; // Un gris neutro muy claro (#F5F5F5)
    
    final textColor = isMe 
        ? Colors.white 
        : Theme.of(context).textTheme.bodyMedium?.color; // Texto casi negro (#0D1826)
    // === FIN CAMBIO ===

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
                      // Color de hora (blanco en burbuja oscura, gris-azulado en burbuja clara)
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

// --- Widget BubbleClipper (sin cambios) ---
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

// --- Clase ChatMessage (sin cambios) ---
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

// --- Clase ChatScreen (sin cambios) ---
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
  final SocketService _socketService = SocketService();
  final CryptoService _cryptoService = CryptoService();
  final ConversationApi _conversationApi = ConversationApi();
  late final int _currentUserId;
  String? _privateKeyPem;
  bool _isLoadingHistory = true;
  bool _hasMissingPrivateKey = false;
  bool _hasInitializationError = false;

  final ScrollController _scrollController = ScrollController();


  @override
  void initState() {
    super.initState();
    print("ChatScreen [initState]: Iniciando pantalla para conversación ID ${widget.conversationData['id']}");
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.userId == null || authService.token == null) {
       print("ChatScreen [initState] ERROR CRÍTICO: userId o token es null.");
       WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { setState(() { _isLoadingHistory = false; _hasMissingPrivateKey = true; _hasInitializationError = true; }); } });
       return;
    }
    _currentUserId = authService.userId!;
    print("ChatScreen [initState]: Usuario actual ID: $_currentUserId");
    _setupChatTitle();
    _initializeChat(authService);
  }

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
    if (explicitTitle != null && explicitTitle.isNotEmpty) { _chatTitle = explicitTitle; print("..."); return; }
    final participants = widget.conversationData['participants'] as List?;
    if (participants != null) {
      final otherParticipant = participants.firstWhere((p) => p is Map && p['userId'] != null && p['userId'] != _currentUserId, orElse: () => null);
      if (otherParticipant != null) {
        final username = otherParticipant['username'] as String?;
        if (username != null && username.isNotEmpty) { _chatTitle = 'Chat con $username'; print("..."); return; }
        else { final userId = otherParticipant['userId']; _chatTitle = 'Chat con Usuario $userId'; print("..."); return; }
      }
    }
    _chatTitle = 'Conversación ${widget.conversationData['id']}'; print("...");
    if (mounted) { setState(() {}); }
  }

  Future<void> _initializeChat(AuthService authService) async {
      if (mounted) { setState(() { _isLoadingHistory = true; _hasMissingPrivateKey = false; _hasInitializationError = false; }); }
    try {
      print("..."); _privateKeyPem = await authService.getPrivateKeyForSession();
      if (_privateKeyPem == null) { print("..."); if (mounted) { setState(() { _hasMissingPrivateKey = true; _hasInitializationError = true; _isLoadingHistory = false; }); } return; }
      print("...");
      final token = authService.token;
      if (token != null) { print("..."); await _loadAndDecryptHistory(token); print("..."); }
      else { throw Exception("Token nulo..."); }
       if (token != null) { print("..."); _socketService.connect(token, _onMessageReceived); print("..."); }
       else { throw Exception("Token nulo..."); }
    } catch (e) { print("... ERROR: $e"); if (mounted) { setState(() { if (!_hasMissingPrivateKey) _hasInitializationError = true; _isLoadingHistory = false; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'))); }
    } finally { if (mounted && _isLoadingHistory) { setState(() { _isLoadingHistory = false; }); print("..."); } }
  }

  Future<void> _loadAndDecryptHistory(String token) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) { throw Exception("ID inválido."); }
    if (_privateKeyPem == null) { throw Exception("Clave privada nula."); }
    try {
      print("... Solicitando historial..."); final historyData = await _conversationApi.getMessages(token, conversationId);
      if (!mounted) return; if (historyData.isEmpty) { print("... Historial vacío."); return; }
      print("... Descifrando ${historyData.length} mensajes..."); List<ChatMessage> decryptedHistory = []; int successCount = 0; int errorCount = 0;
      for (var msgData in historyData) {
        if (msgData is! Map<String, dynamic>) { print("... Warning: Item no es mapa."); errorCount++; continue; }
        try {
          final messageId = (msgData['messageId'] as num?)?.toInt(); final ciphertext = msgData['ciphertext'] as String?; final encryptedKey = msgData['encryptedKey'] as String?; final senderId = (msgData['senderId'] as num?)?.toInt(); final createdAtStr = msgData['createdAt'] as String?;
          if (ciphertext == null || encryptedKey == null || createdAtStr == null || senderId == null) { print("... Warning: Datos incompletos $messageId."); errorCount++; continue; }
          final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!); final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV); final base64AesKey = aesKeyMap['key']; final base64AesIV = aesKeyMap['iv'];
          if (base64AesKey == null || base64AesIV == null) { print("... Error: Fallo al separar clave/IV $messageId."); errorCount++; continue; }
          final plainText = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
          final createdAt = DateTime.parse(createdAtStr).toLocal();
          decryptedHistory.add(ChatMessage(text: plainText, senderId: senderId, isMe: senderId == _currentUserId, createdAt: createdAt)); successCount++;
        } catch (e) { errorCount++; final messageId = (msgData['messageId'] as num?)?.toInt() ?? 'desc.'; print("... Error al descifrar $messageId: $e"); }
      }
      decryptedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (mounted) {
        setState(() { _messages.addAll(decryptedHistory); });
        _scrollToBottom(); 
        print("... Historial procesado. Éxito: $successCount, Errores: $errorCount");
      }
    } catch (apiError) { print("... ERROR API: $apiError"); if(mounted) { setState(() { _hasInitializationError = true; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error historial: ${apiError.toString()}'))); } }
  }


  Future<void> _onMessageReceived(StompFrame frame) async {
     if (frame.body == null || frame.body!.isEmpty) { print("..."); return; }
     if (_privateKeyPem == null) { print("... ERROR: Falta clave privada."); return; }
    print("... Mensaje STOMP recibido: ${frame.body?.substring(0, min(frame.body!.length, 150))}...");
    try {
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);
      final conversationId = (decodedBody['conversationId'] as num?)?.toInt(); final expectedConversationId = (widget.conversationData['id'] as num?)?.toInt();
      if (conversationId == null || expectedConversationId == null || conversationId != expectedConversationId) { print("... Mensaje ignorado (ID conv no coincide)."); return; }
      final senderId = (decodedBody['senderId'] as num?)?.toInt();
      if (senderId == null) { print("... Error: senderId nulo."); return; }
      if (senderId == _currentUserId) { print("... Mensaje ignorado (eco)."); return; }
      final ciphertext = decodedBody['ciphertext'] as String?; final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;
      if (ciphertext == null || encryptedKeysMap == null) { print("... Error: Falta ciphertext o keys."); return; }
      final encryptedCombinedKey = encryptedKeysMap[_currentUserId.toString()] as String?;
      if (encryptedCombinedKey == null) { print("... Error: No se encontró clave para mi ID."); return; }
      final combinedKeyIV = await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!); final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV); final base64AesKey = aesKeyMap['key']; final base64AesIV = aesKeyMap['iv'];
      if (base64AesKey == null || base64AesIV == null) { print("... Error: Fallo al separar clave/IV."); return; }
      final plainTextMessage = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
      final createdAt = DateTime.now(); final newMessage = ChatMessage(text: plainTextMessage, senderId: senderId, isMe: false, createdAt: createdAt);
      if (mounted) {
        setState(() { _messages.add(newMessage); });
        _scrollToBottom();
         print("... Mensaje STOMP (de $senderId) añadido a UI.");
      }
    } catch (e) { print("... ERROR procesando STOMP: $e"); print("... Cuerpo con error: ${frame.body}"); }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) { print("..."); return; }
    final plainTextMessage = messageText; final now = DateTime.now();
    final localMessage = ChatMessage(text: plainTextMessage, senderId: _currentUserId, isMe: true, createdAt: now);
    if (mounted) { setState(() { _messages.add(localMessage); }); }
     _messageController.clear();
     _scrollToBottom(); 

     final List<dynamic>? participants = widget.conversationData['participants'];
    final List<int> allParticipantIds = participants?.map<int?>((p) => (p is Map && p['userId'] is num) ? (p['userId'] as num).toInt() : null).where((id) => id != null).cast<int>().toList() ?? [];
     if (allParticipantIds.isEmpty) { print("... ERROR: No hay participantes."); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Sin destinatarios.'))); setState(() { _messages.remove(localMessage); }); } return; }
     if (!allParticipantIds.contains(_currentUserId)) { allParticipantIds.add(_currentUserId); print("... Añadido ID propio."); }
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) { print("... ERROR: ID conv nulo."); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: ID conv inválido.'))); setState(() { _messages.remove(localMessage); }); } return; }

    try {
      print("... Enviando a SocketService...");
      await _socketService.sendMessage(conversationId, plainTextMessage, allParticipantIds);
      print("... Llamada a SocketService completada.");
    } catch (e) {
      print("... ERROR al enviar: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: ${e.toString()}')));
        setState(() { _messages.remove(localMessage); }); // Quitar si falló
      }
    }
  }

  @override
  void dispose() {
    print("ChatScreen [dispose]: Desconectando y liberando...");
    _socketService.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    if (_isLoadingHistory) { bodyContent = const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Cargando chat seguro...")])); }
    else if (_hasMissingPrivateKey) { bodyContent = _buildMissingKeyError(); }
    else if (_hasInitializationError) { bodyContent = _buildGenericError(); }
    else { bodyContent = _buildMessagesList(); } 

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

  Widget _buildMissingKeyError() { /* ... (sin cambios) ... */
    return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.lock_outline, size: 64, color: Colors.orangeAccent), const SizedBox(height: 20), const Text("Clave de Seguridad No Disponible", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text("No se puede acceder a los mensajes cifrados. Asegúrate de haber iniciado sesión correctamente en este dispositivo.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)), const SizedBox(height: 24), ElevatedButton.icon(icon: const Icon(Icons.arrow_back), label: const Text("Volver"), onPressed: () => Navigator.of(context).pop(), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)))])));
  }

  Widget _buildGenericError() { /* ... (sin cambios) ... */
    return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, size: 64, color: Colors.redAccent), const SizedBox(height: 20), const Text("Error al Cargar el Chat", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 12), const Text("No se pudo inicializar la conversación. Por favor, verifica tu conexión o inténtalo más tarde.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)), const SizedBox(height: 24), ElevatedButton.icon(icon: const Icon(Icons.arrow_back), label: const Text("Volver"), onPressed: () => Navigator.of(context).pop(), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)))])));
  }


  Widget _buildMessagesList() { /* ... (sin cambios) ... */
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

  // --- Método _buildMessageInput (ACTUALIZADO) ---
  Widget _buildMessageInput() {
    return Container(
        // Fondo gris muy claro para separar la barra
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
                      // Usar el hintStyle del Tema
                      hintStyle: Theme.of(context).inputDecorationTheme.hintStyle, 
                      filled: true,
                      fillColor: Colors.white, // Campo de texto blanco
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25.0),
                          // Usar el color de borde del Tema
                          borderSide: BorderSide(color: Theme.of(context).dividerColor)
                      ),
                      focusedBorder: OutlineInputBorder( 
                          borderRadius: BorderRadius.circular(25.0),
                          // Usar el color primario del Tema
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
                      // Usar el color de acento del Tema (Azul Pálido)
                      backgroundColor: Theme.of(context).hintColor, 
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder()),
                  // === CAMBIO DE PALETA ===
                  icon: Icon(
                      Icons.send_rounded,
                      // Usar el color primario oscuro (casi negro) sobre el acento (claro)
                      color: Theme.of(context).primaryColorDark, 
                      size: 24),
                  // === FIN CAMBIO ===
                  tooltip: "Enviar mensaje",
                  onPressed: _sendMessage))
        ])));
  }

} // Fin clase _ChatScreenState