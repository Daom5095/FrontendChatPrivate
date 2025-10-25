// lib/screens/chat/chat_screen.dart


import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart'; // Asegúrate que esta importación esté presente
import '../../services/auth_service.dart'; // Necesario para obtener clave
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart'; // Necesario para historial
import 'dart:convert';

// Modelo simple para representar un mensaje en la UI
class ChatMessage {
  final String text;
  final int senderId;
  final bool isMe;
  final DateTime createdAt; // Añadido para ordenar historial

  ChatMessage({
    required this.text,
    required this.senderId,
    required this.isMe,
    required this.createdAt, // Añadido al constructor
  });
}

class ChatScreen extends StatefulWidget {
  // Esperamos un Map<String, dynamic> con los datos de la conversación
  final Map<String, dynamic> conversationData;

  const ChatScreen({super.key, required this.conversationData});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _socketService = SocketService();
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  late final int currentUserId; // ID del usuario actual
  String chatTitle = "Chat"; // Título por defecto

  // Servicios necesarios
  final CryptoService _cryptoService = CryptoService();
  final ConversationApi _conversationApi = ConversationApi();

  // Clave privada para la sesión actual (se obtiene de AuthService)
  String? _privateKeyPem;

  // Estados de la UI
  bool _isLoadingHistory = true; // Para mostrar carga inicial
  bool _hasMissingPrivateKey = false; // Para mostrar error si falta la clave

  @override
  void initState() {
    super.initState();
    // Obtener AuthService una vez
    final authService = Provider.of<AuthService>(context, listen: false);

    // Validar datos de autenticación antes de proceder
    if (authService.userId == null || authService.token == null) {
       print("ChatScreen Error Crítico: userId o token es null en initState.");
       // Marcar error y detener carga si falta información esencial
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           setState(() {
             _isLoadingHistory = false;
             _hasMissingPrivateKey = true; // Indicar error fundamental
           });
         }
       });
       return; // No continuar si falta user id o token
    }

    currentUserId = authService.userId!;
    _setupChatTitle(); // Configurar título inicial
    _initializeChat(authService); // Iniciar carga de clave, historial y conexión
  }

  /// Configura el título del chat basado en los datos de la conversación.
  void _setupChatTitle() {
    // Si la conversación tiene un título explícito (chats grupales futuros)
    if (widget.conversationData['title'] != null && widget.conversationData['title'].isNotEmpty) {
      chatTitle = widget.conversationData['title'];
    } else {
      // Si es un chat directo, intenta encontrar el nombre del otro participante
      final participants = widget.conversationData['participants'] as List?;
      final otherParticipant = participants?.firstWhere(
        (p) => p['userId'] != currentUserId,
        orElse: () => null, // Devuelve null si no hay otro participante
      );

      if (otherParticipant != null && otherParticipant['username'] != null) {
        // Usa el 'username' si está disponible
        chatTitle = 'Chat con ${otherParticipant['username']}';
      } else if (otherParticipant != null) {
         chatTitle = 'Chat con Usuario ${otherParticipant['userId']}'; // Fallback con ID
      }
       else {
        // Fallback si algo va mal
        chatTitle = 'Chat ${widget.conversationData['id']}';
      }
    }
  }

  /// Orquesta la carga de la clave privada, el historial y la conexión al socket.
  Future<void> _initializeChat(AuthService authService) async {
    // Asegurarse de que el estado inicial sea de carga y sin error de clave
    if (mounted) {
      setState(() {
        _isLoadingHistory = true;
        _hasMissingPrivateKey = false;
      });
    }

    try {
      // 1. Obtener la clave privada para esta sesión desde AuthService
      print("ChatScreen: Obteniendo clave privada para la sesión...");
      _privateKeyPem = await authService.getPrivateKeyForSession();

      // 2. Verificar si la clave se obtuvo
      if (_privateKeyPem == null) {
         print("ChatScreen Error: No se pudo obtener la clave privada desde AuthService.");
         // Marcar el estado de error específico y detener
         if (mounted) {
           setState(() {
             _hasMissingPrivateKey = true;
             _isLoadingHistory = false; // Detener la carga
           });
         }
         return; // No continuar sin clave
      }
      print("ChatScreen: Clave privada obtenida.");

      // 3. Cargar y descifrar el historial (asegurarse de que el token no sea null)
      if (authService.token != null) {
        print("ChatScreen: Cargando historial...");
        await _loadAndDecryptHistory(authService.token!);
        print("ChatScreen: Historial procesado.");
      } else {
         throw Exception("Token nulo al intentar cargar historial.");
      }


      // 4. Conectar al WebSocket (asegurarse de que el token no sea null)
       if (authService.token != null) {
         print("ChatScreen: Conectando al WebSocket...");
         _socketService.connect(authService.token!, _onMessageReceived);
       } else {
          throw Exception("Token nulo al intentar conectar al socket.");
       }


    } catch (e) {
      print("ChatScreen Error durante la inicialización: $e");
      // Marcar error genérico o específico si es posible
       if (mounted) {
         setState(() {
           // Si el error no fue específicamente la clave perdida, podríamos
           // mostrar un error genérico, pero el de clave perdida es más informativo
           // si _privateKeyPem sigue siendo null.
           if (_privateKeyPem == null) _hasMissingPrivateKey = true;
           // Considera añadir otro estado bool _hasGenericError = true;
           _isLoadingHistory = false; // Detener la carga en cualquier caso de error
         });
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error al inicializar el chat: ${e.toString()}'))
         );
       }
    } finally {
      // Asegurarse de quitar el indicador de carga si aún está montado
      if (mounted && _isLoadingHistory) {
        setState(() { _isLoadingHistory = false; });
      }
    }
  }

  /// Carga el historial de mensajes desde la API y los descifra.
  Future<void> _loadAndDecryptHistory(String token) async {
    final conversationId = (widget.conversationData['id'] as num).toInt();

    if (_privateKeyPem == null) {
      throw Exception("Intento de cargar historial sin clave privada disponible.");
    }

    final historyData = await _conversationApi.getMessages(token, conversationId);

    if (historyData.isEmpty) {
      print("ChatScreen: Historial vacío para conversación $conversationId.");
      return; // No hay nada que hacer si no hay historial
    }

    print("ChatScreen: Descifrando ${historyData.length} mensajes del historial...");
    List<ChatMessage> decryptedHistory = [];
    int successCount = 0;
    int errorCount = 0;

    for (var msgData in historyData) {
      try {
        final ciphertext = msgData['ciphertext'] as String?;
        final encryptedKey = msgData['encryptedKey'] as String?; // Clave específica para el usuario
        final senderId = (msgData['senderId'] as num?)?.toInt();
        final createdAtStr = msgData['createdAt'] as String?;

        if (ciphertext == null || encryptedKey == null || createdAtStr == null || senderId == null) {
          print("ChatScreen Warning: Datos incompletos en mensaje de historial ID ${msgData['messageId']}. Saltando.");
          errorCount++;
          continue;
        }

        // Descifrar clave AES+IV usando la clave privada de la sesión
        final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!);
        final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
        final base64AesKey = aesKeyMap['key'];
        final base64AesIV = aesKeyMap['iv'];

        if (base64AesKey == null || base64AesIV == null) {
          print("ChatScreen Error: Fallo al separar clave/IV del historial para mensaje ID ${msgData['messageId']}. Saltando.");
          errorCount++;
          continue;
        }

        // Descifrar mensaje usando AES (asumimos CBC para mensajes como antes)
        final plainText = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);

        // Convertir timestamp String a DateTime y a hora local
        final createdAt = DateTime.parse(createdAtStr).toLocal();

        decryptedHistory.add(ChatMessage(
          text: plainText,
          senderId: senderId,
          isMe: senderId == currentUserId,
          createdAt: createdAt,
        ));
        successCount++;

      } catch (e) {
        errorCount++;
        print("ChatScreen Error al descifrar mensaje del historial ID ${msgData['messageId']}: $e");
        // Opcional: Añadir un marcador de error a la lista en lugar del mensaje
        // final createdAt = msgData['createdAt'] != null ? DateTime.parse(msgData['createdAt']).toLocal() : DateTime.now();
        // final senderId = (msgData['senderId'] as num?)?.toInt() ?? 0;
        // decryptedHistory.add(ChatMessage(text: "[Mensaje no descifrable]", senderId: senderId, isMe: senderId == currentUserId, createdAt: createdAt));
      }
    }

    // Ordenar por fecha (más antiguo primero)
    decryptedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Añadir historial descifrado a la lista principal si el widget sigue montado
    if (mounted) {
      setState(() {
        _messages.addAll(decryptedHistory);
      });
      print("ChatScreen: Historial procesado. Éxito: $successCount, Errores: $errorCount");
    }
  }

  /// Callback para manejar y descifrar mensajes nuevos recibidos por WebSocket.
  Future<void> _onMessageReceived(StompFrame frame) async {
    if (frame.body == null) {
       print("ChatScreen: Mensaje STOMP recibido sin cuerpo.");
       return;
     }
    if (_privateKeyPem == null) {
      print("ChatScreen Error: Recibido mensaje STOMP pero falta clave privada para descifrar.");
      return; // No podemos descifrar
    }

    print("ChatScreen: Mensaje STOMP recibido: ${frame.body?.substring(0, min(frame.body!.length, 100))}..."); // Log inicial del cuerpo

    try {
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);

      final conversationId = decodedBody['conversationId'];
      // Validar si es para esta conversación
      if (conversationId == null || conversationId != widget.conversationData['id']) {
         print("ChatScreen: Mensaje STOMP ignorado (ID conversación no coincide o nulo).");
         return;
      }

      final senderId = (decodedBody['senderId'] as num?)?.toInt();
      // Validar senderId y si es mensaje propio (eco)
      if (senderId == null) {
         print("ChatScreen Error: senderId nulo en mensaje STOMP.");
         return;
      }
      if (senderId == currentUserId) {
         print("ChatScreen: Mensaje STOMP ignorado (eco del propio mensaje).");
         return; // Ignorar eco
      }


      final ciphertext = decodedBody['ciphertext'] as String?;
      final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;

      if (ciphertext == null || encryptedKeysMap == null) {
         print("ChatScreen Error: Falta ciphertext o encryptedKeys en mensaje STOMP.");
         return;
      }

      // Buscar la clave AES cifrada específica para el usuario actual
      final encryptedCombinedKey = encryptedKeysMap[currentUserId.toString()] as String?;
      if (encryptedCombinedKey == null) {
         print("ChatScreen Error: No se encontró clave cifrada para el usuario $currentUserId en mensaje STOMP.");
         return; // No podemos descifrar
      }

      // Descifrar Clave AES+IV (RSA)
      final combinedKeyIV = await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final base64AesKey = aesKeyMap['key'];
      final base64AesIV = aesKeyMap['iv'];

      if (base64AesKey == null || base64AesIV == null) {
        print("ChatScreen Error: Fallo al separar clave/IV descifrada de mensaje STOMP.");
        return;
      }

      // Descifrar Mensaje (AES)
      final plainTextMessage = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV); // Usando CBC

      // Usar hora actual para mensajes nuevos
      final createdAt = DateTime.now();

      // Añadir a la UI si el widget sigue montado
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: plainTextMessage,
              senderId: senderId,
              isMe: false, // Sabemos que no es nuestro por el filtro anterior
              createdAt: createdAt,
            ),
          );
        });
         print("ChatScreen: Mensaje STOMP descifrado y añadido a la UI.");
      }

    } catch (e) {
      print("ChatScreen Error al procesar/descifrar mensaje STOMP: $e");
      print("Cuerpo del mensaje STOMP: ${frame.body}");
      // Considera añadir un marcador de error a la lista _messages
    }
  }

  /// Envía un mensaje de texto plano (que será cifrado por SocketService).
  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    final plainTextMessage = messageText;
    final now = DateTime.now();

    // Añadir mensaje (plano) a la UI local inmediatamente
    if (mounted) {
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
    }
    _messageController.clear(); // Limpiar input

    // Obtener IDs de todos los participantes para el cifrado
    final List<dynamic>? participants = widget.conversationData['participants'];
    final List<int> allParticipantIds = participants
            ?.map<int>((p) => (p['userId'] as num).toInt())
            .where((id) => id != 0) // Filtrar IDs inválidos si los hubiera
            .toList() ??
            []; // Si participants es null, lista vacía

     if (allParticipantIds.isEmpty) {
        print("ChatScreen Error: No se encontraron IDs de participantes válidos para enviar mensaje.");
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Error: No se pueden determinar los destinatarios.'))
            );
         }
        // Opcional: quitar el mensaje local añadido si falla aquí
        // setState(() { _messages.removeLast(); });
        return;
     }

    // Enviar a través del SocketService (que se encargará del cifrado)
    try {
      print("ChatScreen: Enviando mensaje a SocketService...");
      await _socketService.sendMessage(
        (widget.conversationData['id'] as num).toInt(),
        plainTextMessage,
        allParticipantIds,
      );
       print("ChatScreen: Mensaje enviado a SocketService con éxito.");
    } catch (e) {
      print("ChatScreen Error al llamar a socketService.sendMessage: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error al enviar mensaje: ${e.toString()}'))
        );
        // Opcional: quitar mensaje local o marcarlo como no enviado
        // setState(() { _messages.removeLast(); });
      }
    }
  }

  @override
  void dispose() {
    print("ChatScreen: Disposing...");
    _socketService.disconnect();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (_isLoadingHistory) {
      // Estado de carga inicial
      bodyContent = const Center(
         child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Cargando chat seguro...")
          ],
        )
      );
    } else if (_hasMissingPrivateKey) {
      // Estado de error: Falta clave privada
       bodyContent = Center(
         child: Padding(
           padding: const EdgeInsets.all(24.0), // Más padding
           child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               const Icon(Icons.lock_person_outlined, size: 64, color: Colors.orangeAccent),
               const SizedBox(height: 20),
               const Text(
                 "Clave de Seguridad No Encontrada",
                 textAlign: TextAlign.center,
                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
               ),
               const SizedBox(height: 12),
               const Text(
                 "No se puede acceder a los mensajes cifrados porque la clave privada no está en este dispositivo. Esto puede suceder al usar un dispositivo nuevo o si se borraron los datos de la aplicación.",
                 textAlign: TextAlign.center,
                 style: TextStyle(fontSize: 14, color: Colors.grey),
               ),
               const SizedBox(height: 24),
               ElevatedButton.icon(
                 icon: const Icon(Icons.arrow_back),
                 label: const Text("Volver"),
                 onPressed: () => Navigator.of(context).pop(),
                 style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
               ),
               // TextButton(onPressed: () { /* Lógica futura de reseteo */ }, child: Text("Resetear Claves (Perder Historial)"))
             ],
           ),
         ),
       );
    } else {
      // Estado normal: Mostrar lista de mensajes
      bodyContent = ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _messages.length,
        itemBuilder: (ctx, index) {
          final msg = _messages[index];
          // Construir la burbuja del mensaje (sin cambios)
          return Align(
            alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), // Ancho máximo
              decoration: BoxDecoration(
                color: msg.isMe ? Theme.of(context).primaryColorLight : Colors.grey[200], // Colores ajustados
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: msg.isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: msg.isMe ? Radius.zero : const Radius.circular(16),
                ),
                boxShadow: [ // Sombra sutil
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                 msg.text,
                 style: TextStyle(color: msg.isMe ? Colors.black87 : Colors.black87), // Asegurar texto legible
                ),
            ),
          );
        },
      );
    }

    // Scaffold principal
    return Scaffold(
      appBar: AppBar(
        title: Text(chatTitle), // Título dinámico
      ),
      body: Column(
        children: [
          Expanded(child: bodyContent), // Contenido principal (carga, error o lista)
          // Solo mostrar input si NO está cargando y NO falta la clave
          if (!_isLoadingHistory && !_hasMissingPrivateKey) _buildMessageInput(),
        ],
      ),
    );
  }

  /// Construye la UI para la entrada de mensajes (sin cambios).
  Widget _buildMessageInput() {
     return Container(
      decoration: BoxDecoration( // Añadir borde superior
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), // Ajustar padding
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end, // Alinear al fondo
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
                  isDense: true, // Hacerlo un poco más compacto
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5, // Permitir múltiples líneas
                minLines: 1,
                // Quitar onSubmitted si queremos que solo funcione el botón
                // onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            // Usar un botón con tamaño fijo para mejor apariencia
            SizedBox(
              height: 48, // Altura similar al TextField
              width: 48,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  padding: EdgeInsets.zero, // Padding cero para centrar ícono
                  shape: const CircleBorder(), // Hacerlo circular
                ),
                icon: const Icon(Icons.send, color: Colors.white, size: 24), // Ajustar tamaño ícono
                tooltip: "Enviar mensaje", // Añadir tooltip
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}