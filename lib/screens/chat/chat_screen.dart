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
  final Map<String, dynamic> conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _socketService = SocketService();
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  late final int currentUserId; // <-- ID DEL USUARIO ACTUAL

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Obtenemos el ID del usuario actual desde el servicio
    currentUserId = authService.userId!;
    
    // Conectamos al socket y le decimos qué hacer cuando llega un mensaje
    _socketService.connect(authService.token!, (frame) {
      if (frame.body != null) {
        final decodedBody = json.decode(frame.body!);
        
        // Solo añadimos mensajes que pertenecen a esta conversación
        if (decodedBody['conversationId'] == widget.conversation['id']) {
          if (mounted) {
            setState(() {
              _messages.add(
                ChatMessage(
                  text: decodedBody['ciphertext'], // Por ahora es texto plano
                  senderId: decodedBody['senderId'],
                  isMe: decodedBody['senderId'] == currentUserId, // <-- LÓGICA CORREGIDA
                ),
              );
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _socketService.disconnect();
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    
    // Creamos el mensaje en la UI inmediatamente para una mejor experiencia de usuario
    setState(() {
      _messages.add(
        ChatMessage(
          text: _messageController.text.trim(),
          senderId: currentUserId,
          isMe: true,
        ),
      );
    });

    // Enviamos el mensaje a través del socket
    _socketService.sendMessage(
      widget.conversation['id'],
      _messageController.text.trim(),
    );
    
    // Limpiamos el campo de texto
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat con ${widget.conversation['id']}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
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
                      color: msg.isMe ? Colors.blue[200] : Colors.grey[300],
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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Escribe un mensaje...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20))
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}