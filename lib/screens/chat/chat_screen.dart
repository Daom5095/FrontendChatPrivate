// lib/screens/chat/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import 'dart:convert';

// Modelo simple para representar un mensaje en la UI
class ChatMessage {
  final String text;
  final int senderId;
  final bool isMe;

  ChatMessage({required this.text, required this.senderId, required this.isMe});
}

class ChatScreen extends StatefulWidget {
  // Ahora esperamos un Map<String, dynamic> más completo
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
  String chatTitle = "Chat"; // Título por defecto

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);

    // Obtenemos el ID del usuario actual desde el servicio de autenticación
    currentUserId = authService.userId!;

    // Configura el título inicial del chat
    _setupChatTitle();

    // Conectamos al socket y definimos qué hacer al recibir un mensaje
    _socketService.connect(authService.token!, (frame) {
      if (frame.body != null) {
        try {
          final decodedBody = json.decode(frame.body!);

          // Ignora mensajes que no sean para esta conversación
          if (decodedBody['conversationId'] != widget.conversationData['id']) return;

          // ¡IMPORTANTE! Evita mostrar el "eco" de tu propio mensaje
          if (decodedBody['senderId'] == currentUserId) return;

          // Si es un mensaje de otro usuario para esta conversación, lo muestra
          if (mounted) { // Verifica si el widget todavía está en el árbol
            setState(() {
              _messages.add(
                ChatMessage(
                  text: decodedBody['ciphertext'], // Aún texto plano
                  senderId: decodedBody['senderId'],
                  isMe: false, // Sabemos que no es nuestro por el filtro anterior
                ),
              );
            });
          }
        } catch (e) {
          print("Error decodificando o procesando mensaje recibido: $e");
          print("Cuerpo del mensaje: ${frame.body}");
        }
      }
    });
  }

  // Configura el título basado en los datos de la conversación
  void _setupChatTitle() {
    // Si la conversación tiene un título explícito (chats grupales futuros)
    if (widget.conversationData['title'] != null && widget.conversationData['title'].isNotEmpty) {
      chatTitle = widget.conversationData['title'];
    } else {
      // Si es un chat directo, intenta encontrar el nombre del otro participante
      final participants = widget.conversationData['participants'] as List?;
      final otherParticipant = participants?.firstWhere(
        (p) => p['userId'] != currentUserId,
        orElse: () => null, // Devuelve null si no hay otro participante (raro)
      );

      if (otherParticipant != null) {
        // Intenta obtener el 'username' si está disponible
        // (Requerirá que el backend lo incluya en la respuesta)
        final username = otherParticipant['username'] ?? 'Usuario ${otherParticipant['userId']}';
        chatTitle = 'Chat con $username';
      } else {
        // Fallback si algo va mal
        chatTitle = 'Chat ${widget.conversationData['id']}';
      }
    }
    // Llama a setState si _setupChatTitle se llama fuera de initState
    // if (mounted) setState(() {});
  }


  @override
  void dispose() {
    _socketService.disconnect();
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Añade el mensaje a la UI localmente de inmediato
    setState(() {
      _messages.add(
        ChatMessage(
          text: messageText,
          senderId: currentUserId,
          isMe: true,
        ),
      );
    });

    // --- LÓGICA DE ENVÍO CORREGIDA ---
    // Obtenemos los IDs de TODOS los participantes de la conversación
    final List<dynamic>? participants = widget.conversationData['participants'];
    final List<int> allParticipantIds = participants
            ?.map<int>((p) => p['userId'] as int)
            .toList() ?? // Si participants es null, envía una lista vacía
            [];

    // Enviamos el mensaje junto con la lista de todos los participantes
    _socketService.sendMessage(
      widget.conversationData['id'],
      messageText,
      allParticipantIds, // Lista de IDs para el mapa `encryptedKeys`
    );

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(chatTitle), // Usa la variable de estado para el título
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true, // Para que los mensajes nuevos aparezcan abajo
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (ctx, index) {
                // Invertimos el orden para mostrar desde el más reciente
                final msg = _messages[_messages.length - 1 - index];
                return Align(
                  alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: msg.isMe ? Colors.deepPurple[100] : Colors.grey[300], // Color ajustado
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: msg.isMe ? const Radius.circular(16) : const Radius.circular(0),
                        bottomRight: msg.isMe ? const Radius.circular(0) : const Radius.circular(16),
                      ),
                    ),
                    child: Text(msg.text),
                  ),
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container( // Añadido Container para padding y posible fondo
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      color: Theme.of(context).cardColor, // Fondo sutil
      child: SafeArea( // Asegura que no se solape con elementos del OS
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  filled: true, // Para que el fondo sea visible
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25.0),
                    borderSide: BorderSide.none, // Sin borde
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled( // Estilo de botón actualizado
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor, // Color primario
                padding: const EdgeInsets.all(12),
              ),
              icon: const Icon(Icons.send, color: Colors.white), // Ícono blanco
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}