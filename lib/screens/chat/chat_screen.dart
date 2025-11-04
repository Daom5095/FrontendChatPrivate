// lib/screens/chat/chat_screen.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:intl/intl.dart'; // Para formatear la hora
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart';
import 'dart:convert'; // Para decodificar el JSON de STOMP

// --- Widget ChatBubble ---

/// Mi widget personalizado para mostrar una burbuja de chat individual.
/// Es `Stateless` porque solo muestra los datos que recibe.
class ChatBubble extends StatelessWidget {
  /// El texto descifrado del mensaje.
  final String text;
  /// `true` si el mensaje es mío (para alinearlo a la derecha y cambiar color).
  final bool isMe;
  /// La fecha y hora de creación para mostrarla.
  final DateTime createdAt; 

  const ChatBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    // Formateo la hora para mostrar solo HH:mm
    final timeFormatter = DateFormat('HH:mm');
    final timeString = timeFormatter.format(createdAt);

    // Determino los colores basados en mi tema (definido en main.dart)
    final bubbleColor = isMe
        ? Theme.of(context).primaryColor // Mi color primario (Azul)
        : Colors.grey[100]; // Un gris claro para los demás
    
    // Texto blanco sobre mi burbuja, texto oscuro sobre la burbuja clara
    final textColor = isMe 
        ? Colors.white 
        : Theme.of(context).textTheme.bodyMedium?.color;
    
    // Alineación a la derecha si es mío, izquierda si es del otro
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      // ClipPath usa mi BubbleClipper para darle la forma con la "colita"
      child: ClipPath(
        clipper: BubbleClipper(isMe: isMe),
        child: Container(
          // Límite para que la burbuja no ocupe toda la pantalla
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          // Padding interno, ajustado para la "colita"
          padding: EdgeInsets.only(
            top: 10,
            bottom: 10,
            left: isMe ? 14 : 22, // Más padding a la izquierda si no es mío
            right: isMe ? 22 : 14, // Más padding a la derecha si es mío
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
             // Una sombra sutil para darle profundidad
             boxShadow: [ 
               BoxShadow(
                 color: Colors.black.withOpacity(0.08),
                 spreadRadius: 0.5,
                 blurRadius: 1.5,
                 offset: const Offset(0, 1),
               ),
             ],
          ),
          // Una columna para poner el texto encima de la hora
          child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             mainAxisSize: MainAxisSize.min, // Que se ajuste al contenido
             children: [
                // El texto del mensaje
                Text(
                  text,
                  style: TextStyle(color: textColor, fontSize: 15.5),
                ),
                const SizedBox(height: 4),
                // La hora, alineada abajo a la derecha de la burbuja
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

/// Mi `CustomClipper` que dibuja la forma de la burbuja de chat.
///
/// Dibuja una caja con bordes redondeados (`cornerRadius`) y añade
/// una "colita" (`nip`) en la esquina inferior izquierda o derecha,
/// dependiendo de `isMe`.
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

    // Lógica de dibujo del Path. Es un poco compleja pero
    // básicamente dibuja líneas y arcos para formar la burbuja.
    if (isMe) {
      // Burbuja mía (colita a la derecha)
      path.moveTo(cornerRadius, 0); 
      path.lineTo(width - cornerRadius - nipWidth, 0); 
      path.arcToPoint(Offset(width - nipWidth, cornerRadius), radius: Radius.circular(cornerRadius)); 
      path.lineTo(width - nipWidth, height - nipHeight - cornerRadius); 
      path.lineTo(width, height - cornerRadius); // La punta de la colita
      path.arcToPoint(Offset(width - nipWidth - cornerRadius, height), radius: Radius.circular(cornerRadius)); 
      path.lineTo(cornerRadius, height); 
      path.arcToPoint(Offset(0, height - cornerRadius), radius: Radius.circular(cornerRadius)); 
      path.lineTo(0, cornerRadius); 
      path.arcToPoint(Offset(cornerRadius, 0), radius: Radius.circular(cornerRadius)); 
    } else {
      // Burbuja del otro (colita a la izquierda)
      path.moveTo(nipWidth + cornerRadius, 0); 
      path.lineTo(width - cornerRadius, 0); 
      path.arcToPoint(Offset(width, cornerRadius), radius: Radius.circular(cornerRadius)); 
      path.lineTo(width, height - cornerRadius); 
      path.arcToPoint(Offset(width - cornerRadius, height), radius: Radius.circular(cornerRadius)); 
      path.lineTo(nipWidth + cornerRadius, height); 
       path.arcToPoint(Offset(nipWidth, height - cornerRadius), radius: Radius.circular(cornerRadius)); 
       path.lineTo(nipWidth, height - cornerRadius - nipHeight); 
       path.lineTo(0, height - cornerRadius); // La punta de la colita
      path.lineTo(nipWidth, cornerRadius); 
      path.arcToPoint(Offset(nipWidth + cornerRadius, 0), radius: Radius.circular(cornerRadius)); 
    }
    path.close();
    return path;
  }

  /// No necesito que se redibuje a menos que cambie `isMe`,
  /// pero como la burbuja no cambia de dueño, devuelvo `false`.
  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// --- Clase Modelo ChatMessage ---

/// Mi clase de modelo (NO es un widget) para almacenar un mensaje *descifrado*.
///
/// Uso esto para guardar los mensajes en la lista `_messages`
/// de una forma estructurada y limpia, listos para pasárselos al
/// widget `ChatBubble`.
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

/// Mi pantalla de chat. Es `Stateful` porque maneja el estado
/// de la lista de mensajes, la conexión WebSocket y el input del usuario.
class ChatScreen extends StatefulWidget {
  /// Los datos de la conversación (ID, participantes) que
  /// recibo de `HomeScreen` o `UserListScreen`.
  final Map<String, dynamic> conversationData;
  
  const ChatScreen({super.key, required this.conversationData});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// El Estado (lógica) de mi `ChatScreen`.
class _ChatScreenState extends State<ChatScreen> {
  // --- Controladores y Estado de UI ---
  final _messageController = TextEditingController(); // Controlador para el campo de texto
  final List<ChatMessage> _messages = []; // La lista de mensajes descifrados
  String _chatTitle = "Chat"; // Título para el AppBar
  final ScrollController _scrollController = ScrollController(); // Para auto-scroll al final

  // --- Servicios y APIs ---
  final SocketService _socketService = SocketService(); // Mi servicio WebSocket/STOMP
  final CryptoService _cryptoService = CryptoService(); // Mi caja de herramientas cripto
  final ConversationApi _conversationApi = ConversationApi(); // Para cargar el historial

  // --- Estado de Cripto y Sesión ---
  late final int _currentUserId; // Mi ID de usuario
  String? _privateKeyPem; // Mi clave privada RSA, la necesito para descifrar

  // --- Flags de Estado ---
  bool _isLoadingHistory = true; // true para mostrar spinner al inicio
  bool _hasMissingPrivateKey = false; // true si no pudimos cargar la clave privada
  bool _hasInitializationError = false; // true si falla la carga del historial o socket

  @override
  void initState() {
    super.initState();
    print("ChatScreen [initState]: Iniciando pantalla para conversación ID ${widget.conversationData['id']}");
    
    // Obtengo el AuthService (sin escuchar cambios) para los datos de sesión
    final authService = Provider.of<AuthService>(context, listen: false);

    // Verificación crítica: si por alguna razón entro aquí sin estar logueado,
    // (ej. token expiró y algo falló), no puedo continuar.
    if (authService.userId == null || authService.token == null) {
       print("ChatScreen [initState] ERROR CRÍTICO: userId o token es null.");
       // Marco los errores y salgo. El `build` mostrará el error.
       WidgetsBinding.instance.addPostFrameCallback((_) { 
         if (mounted) { 
           setState(() { _isLoadingHistory = false; _hasMissingPrivateKey = true; _hasInitializationError = true; }); 
         } 
       });
       return;
    }

    _currentUserId = authService.userId!;
    print("ChatScreen [initState]: Usuario actual ID: $_currentUserId");

    // Configuro el título del chat (ej. "Chat con Juan")
    _setupChatTitle();
    // Inicio la carga asíncrona (clave, historial, socket)
    _initializeChat(authService);
  }

  /// Helper para hacer scroll al final de la lista de mensajes.
  void _scrollToBottom() {
    // Lo hago en el siguiente frame para asegurar que el ListView se haya actualizado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent, // Ir al final
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Configura el título del AppBar.
  /// Intenta usar el título explícito, si no, el nombre del otro participante.
  void _setupChatTitle() {
    final explicitTitle = widget.conversationData['title'] as String?;
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      _chatTitle = explicitTitle;
      print("ChatScreen [_setupChatTitle]: Título explícito encontrado: $_chatTitle");
      return;
    }

    final participants = widget.conversationData['participants'] as List?;
    if (participants != null) {
      // Busco al *otro* participante (que no sea yo)
      final otherParticipant = participants.firstWhere(
        (p) => p is Map && p['userId'] != null && p['userId'] != _currentUserId, 
        orElse: () => null
      );
      
      if (otherParticipant != null) {
        final username = otherParticipant['username'] as String?;
        if (username != null && username.isNotEmpty) {
          _chatTitle = 'Chat con $username';
          print("ChatScreen [_setupChatTitle]: Título generado: $_chatTitle");
          return;
        } else {
          // Fallback si el participante no tiene username (raro)
          final userId = otherParticipant['userId'];
          _chatTitle = 'Chat con Usuario $userId';
          print("ChatScreen [_setupChatTitle]: Título de fallback: $_chatTitle");
          return;
        }
      }
    }
    // Fallback final
    _chatTitle = 'Conversación ${widget.conversationData['id']}';
    print("ChatScreen [_setupChatTitle]: Título de fallback final: $_chatTitle");
    if (mounted) { setState(() {}); }
  }

  /// Orquesta la inicialización asíncrona de la pantalla de chat.
  Future<void> _initializeChat(AuthService authService) async {
    // 1. Poner la UI en modo "Cargando"
      if (mounted) { 
        setState(() { 
          _isLoadingHistory = true; 
          _hasMissingPrivateKey = false; 
          _hasInitializationError = false; 
        }); 
      }
      
    try {
      // 2. Obtener mi clave privada RSA (crítico para descifrar)
      print("ChatScreen [_initializeChat]: Obteniendo clave privada...");
      _privateKeyPem = await authService.getPrivateKeyForSession();
      
      // Si no hay clave, no podemos hacer nada.
      if (_privateKeyPem == null) { 
        print("ChatScreen [_initializeChat] ERROR: No se pudo obtener la clave privada.");
        if (mounted) { 
          setState(() { 
            _hasMissingPrivateKey = true; 
            _hasInitializationError = true; 
            _isLoadingHistory = false; 
          }); 
        } 
        return; // Salir
      }
      print("ChatScreen [_initializeChat]: Clave privada obtenida.");

      // 3. Cargar el historial de mensajes (y descifrarlo)
      final token = authService.token;
      if (token != null) {
        print("ChatScreen [_initializeChat]: Cargando historial de mensajes...");
        await _loadAndDecryptHistory(token);
        print("ChatScreen [_initializeChat]: Historial cargado.");
      } else {
        throw Exception("Token nulo al inicializar chat.");
      }
      
      // 4. Conectar al WebSocket (STOMP) para mensajes en tiempo real
       if (token != null) {
         print("ChatScreen [_initializeChat]: Conectando al WebSocket...");
         _socketService.connect(token, _onMessageReceived); // Pasar el callback
         print("ChatScreen [_initializeChat]: Conexión a WebSocket iniciada.");
       } else {
         throw Exception("Token nulo al conectar socket.");
       }
       
    } catch (e) {
      // Manejar cualquier error durante la inicialización
      print("ChatScreen [_initializeChat] ERROR: $e");
      if (mounted) { 
        setState(() { 
          if (!_hasMissingPrivateKey) _hasInitializationError = true; // No sobrescribir el error de clave
          _isLoadingHistory = false; 
        }); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al inicializar: ${e.toString()}'))); 
      }
    } finally {
      // 5. Quitar el indicador de carga
      if (mounted && _isLoadingHistory) { 
        setState(() { _isLoadingHistory = false; }); 
        print("ChatScreen [_initializeChat]: Inicialización finalizada.");
      }
    }
  }

  /// Carga el historial de mensajes desde la API y los descifra.
  Future<void> _loadAndDecryptHistory(String token) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) { throw Exception("ID de conversación inválido."); }
    if (_privateKeyPem == null) { throw Exception("Clave privada nula, no se puede descifrar historial."); }

    try {
      // 1. Llamar a la API para obtener mensajes CIFRADOS
      print("ChatScreen [_loadAndDecryptHistory]: Solicitando historial para conv $conversationId...");
      final historyData = await _conversationApi.getMessages(token, conversationId);
      if (!mounted) return;
      if (historyData.isEmpty) { 
        print("ChatScreen [_loadAndDecryptHistory]: El historial está vacío.");
        return;
      }

      // 2. Iterar y descifrar cada mensaje
      print("ChatScreen [_loadAndDecryptHistory]: Descifrando ${historyData.length} mensajes del historial...");
      List<ChatMessage> decryptedHistory = [];
      int successCount = 0;
      int errorCount = 0;
      
      for (var msgData in historyData) {
        if (msgData is! Map<String, dynamic>) { 
          print("ChatScreen [_loadAndDecryptHistory] Warning: Item de historial no es un mapa. Saltando.");
          errorCount++; 
          continue; 
        }
        
        try {
          // 2a. Parsear datos del JSON (MessageHistoryDto)
          final messageId = (msgData['messageId'] as num?)?.toInt();
          final ciphertext = msgData['ciphertext'] as String?;
          final encryptedKey = msgData['encryptedKey'] as String?; // Esta es la clave AES+IV cifrada con MI RSA
          final senderId = (msgData['senderId'] as num?)?.toInt();
          final createdAtStr = msgData['createdAt'] as String?;

          if (ciphertext == null || encryptedKey == null || createdAtStr == null || senderId == null) {
            print("ChatScreen [_loadAndDecryptHistory] Warning: Datos incompletos para msg $messageId. Saltando.");
            errorCount++;
            continue;
          }

          // 2b. Descifrar la clave del mensaje (AES+IV) usando mi clave privada RSA
          final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!);
          // 2c. Separar la clave AES y el IV
          final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
          final base64AesKey = aesKeyMap['key'];
          final base64AesIV = aesKeyMap['iv'];

          if (base64AesKey == null || base64AesIV == null) {
            print("ChatScreen [_loadAndDecryptHistory] Error: Fallo al separar clave/IV para msg $messageId.");
            errorCount++;
            continue;
          }

          // 2d. Descifrar el texto del mensaje usando la clave AES
          final plainText = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);
          
          // 2e. Crear el objeto ChatMessage
          final createdAt = DateTime.parse(createdAtStr).toLocal();
          decryptedHistory.add(ChatMessage(
            text: plainText,
            senderId: senderId,
            isMe: senderId == _currentUserId,
            createdAt: createdAt,
          ));
          successCount++;
        } catch (e) {
          // Si un mensaje falla, lo registro pero continúo con los demás
          errorCount++;
          final messageId = (msgData['messageId'] as num?)?.toInt() ?? 'desconocido';
          print("ChatScreen [_loadAndDecryptHistory] ERROR al descifrar msg $messageId: $e");
        }
      } // Fin del bucle for

      // 3. Ordenar y actualizar la UI
      decryptedHistory.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      if (mounted) {
        setState(() {
          _messages.addAll(decryptedHistory);
        });
        _scrollToBottom(); // Hacer scroll al final después de cargar
        print("ChatScreen [_loadAndDecryptHistory]: Historial procesado. Éxito: $successCount, Errores: $errorCount");
      }
    } catch (apiError) {
      print("ChatScreen [_loadAndDecryptHistory] ERROR API: $apiError");
      if(mounted) { 
        setState(() { _hasInitializationError = true; }); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar historial: ${apiError.toString()}'))); 
      }
    }
  }


  /// Callback que se ejecuta cuando llega un mensaje del WebSocket (STOMP).
  Future<void> _onMessageReceived(StompFrame frame) async {
     if (frame.body == null || frame.body!.isEmpty) { 
       print("ChatScreen [_onMessageReceived]: Mensaje STOMP vacío recibido.");
       return; 
     }
     if (_privateKeyPem == null) {
       print("ChatScreen [_onMessageReceived] ERROR: Clave privada nula. No se puede descifrar mensaje STOMP.");
       return;
     }
     
    print("ChatScreen [_onMessageReceived]: Mensaje STOMP recibido: ${frame.body?.substring(0, min(frame.body!.length, 150))}...");
    
    try {
      // 1. Parsear el cuerpo JSON (StompMessagePayload)
      final Map<String, dynamic> decodedBody = json.decode(frame.body!);
      
      // 2. Validar si es para esta conversación
      final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
      final expectedConversationId = (widget.conversationData['id'] as num?)?.toInt();
      if (conversationId == null || expectedConversationId == null || conversationId != expectedConversationId) {
        print("ChatScreen [_onMessageReceived]: Mensaje ignorado (ID de conversación no coincide).");
        return;
      }

      // 3. Validar si es un eco (un mensaje que yo mismo envié)
      final senderId = (decodedBody['senderId'] as num?)?.toInt();
      if (senderId == null) { 
        print("ChatScreen [_onMessageReceived] Error: senderId nulo en mensaje STOMP.");
        return;
      }
      if (senderId == _currentUserId) {
        print("ChatScreen [_onMessageReceived]: Mensaje ignorado (es un eco mío).");
        return;
      }

      // 4. Extraer datos para el descifrado
      final ciphertext = decodedBody['ciphertext'] as String?;
      final encryptedKeysMap = decodedBody['encryptedKeys'] as Map<String, dynamic>?;
      if (ciphertext == null || encryptedKeysMap == null) {
        print("ChatScreen [_onMessageReceived] Error: Falta ciphertext o encryptedKeys.");
        return;
      }

      // 5. Obtener MI clave cifrada del mapa
      // (El backend envía un mapa de claves, una para cada participante)
      final encryptedCombinedKey = encryptedKeysMap[_currentUserId.toString()] as String?;
      if (encryptedCombinedKey == null) {
        print("ChatScreen [_onMessageReceived] Error: No se encontró clave cifrada para mi ID ($_currentUserId).");
        return;
      }

      // 6. Descifrar E2EE (igual que en el historial)
      // 6a. Descifrar clave AES+IV (con RSA)
      final combinedKeyIV = await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      // 6b. Separar clave y IV
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final base64AesKey = aesKeyMap['key'];
      final base64AesIV = aesKeyMap['iv'];
      if (base64AesKey == null || base64AesIV == null) {
        print("ChatScreen [_onMessageReceived] Error: Fallo al separar clave/IV de STOMP.");
        return;
      }
      // 6c. Descifrar texto (con AES)
      final plainTextMessage = _cryptoService.decryptAES_CBC(ciphertext, base64AesKey, base64AesIV);

      // 7. Crear el ChatMessage y actualizar la UI
      final createdAt = DateTime.now(); // Usar la hora de recepción
      final newMessage = ChatMessage(
        text: plainTextMessage,
        senderId: senderId,
        isMe: false, // Ya comprobamos que no es un eco
        createdAt: createdAt
      );
      
      if (mounted) {
        setState(() {
          _messages.add(newMessage);
        });
        _scrollToBottom(); // Scroll al recibir
         print("ChatScreen [_onMessageReceived]: Mensaje STOMP (de $senderId) añadido a UI.");
      }
    } catch (e) {
      print("ChatScreen [_onMessageReceived] ERROR procesando STOMP: $e");
      print("ChatScreen [_onMessageReceived]: Cuerpo con error: ${frame.body}");
    }
  }

  /// Envía un nuevo mensaje.
  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) { 
      print("ChatScreen [_sendMessage]: Intento de enviar mensaje vacío. Ignorando.");
      return; 
    }
    
    final plainTextMessage = messageText;
    final now = DateTime.now();

    // 1. Optimistic UI: Añadir el mensaje a la lista local *antes* de enviarlo.
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

     // 2. Preparar datos para el envío
     // Obtengo la lista de *todos* los IDs de participantes (incluyéndome)
     final List<dynamic>? participants = widget.conversationData['participants'];
     final List<int> allParticipantIds = participants
        ?.map<int?>((p) => (p is Map && p['userId'] is num) ? (p['userId'] as num).toInt() : null)
        .where((id) => id != null)
        .cast<int>()
        .toList() ?? [];

     if (allParticipantIds.isEmpty) {
       print("ChatScreen [_sendMessage] ERROR: No hay participantes en la conversación.");
       if (mounted) { 
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Sin destinatarios.')));
         // Deshacer el optimistic UI
         setState(() { _messages.remove(localMessage); }); 
       }
       return;
     }
     
     // Mi lógica de backend espera que yo esté en la lista para cifrar mi propia copia
     if (!allParticipantIds.contains(_currentUserId)) {
       allParticipantIds.add(_currentUserId);
       print("ChatScreen [_sendMessage]: Añadido mi propio ID a la lista de participantes.");
     }
     
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) {
      print("ChatScreen [_sendMessage] ERROR: ID de conversación nulo.");
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: ID de conversación inválido.')));
        setState(() { _messages.remove(localMessage); }); 
      }
      return;
    }

    try {
      // 3. Llamar al SocketService para cifrar E2EE y enviar
      print("ChatScreen [_sendMessage]: Enviando a SocketService...");
      await _socketService.sendMessage(
        conversationId,
        plainTextMessage,
        allParticipantIds
      );
      print("ChatScreen [_sendMessage]: Llamada a SocketService completada.");
      // El mensaje ya está en la UI, no necesito hacer más.
    } catch (e) {
      // 4. Manejar error de envío
      print("ChatScreen [_sendMessage] ERROR al enviar: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: ${e.toString()}')));
        // Deshacer el optimistic UI si falla el envío
        setState(() { _messages.remove(localMessage); });
      }
    }
  }

  /// Limpieza al salir de la pantalla.
  @override
  void dispose() {
    print("ChatScreen [dispose]: Desconectando y liberando...");
    // MUY IMPORTANTE: Desconectar el WebSocket para no seguir recibiendo mensajes.
    _socketService.disconnect();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Construye la UI principal de la pantalla.
  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    // Decido qué mostrar en el cuerpo basado en los flags de estado
    if (_isLoadingHistory) {
      // 1. Cargando
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
      // 2. Error: Falta clave privada
      bodyContent = _buildMissingKeyError();
    } else if (_hasInitializationError) {
      // 3. Error: Genérico (historial, socket)
      bodyContent = _buildGenericError();
    } else {
      // 4. Éxito: Mostrar lista de mensajes
      bodyContent = _buildMessagesList();
    } 

    // Devuelvo el Scaffold
    return Scaffold(
      appBar: AppBar(title: Text(_chatTitle)),
      body: Column(
        children: [
          // El cuerpo (lista, error o loading)
          Expanded(child: bodyContent),
          // Solo muestro la barra de input si todo cargó correctamente
          if (!_isLoadingHistory && !_hasMissingPrivateKey && !_hasInitializationError)
             _buildMessageInput(),
        ],
      ),
    );
  }

  /// Widget de helper para el error de clave privada.
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

  /// Widget de helper para errores genéricos.
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

  /// Widget de helper para construir la lista de mensajes.
  Widget _buildMessagesList() { 
    return ListView.builder(
      controller: _scrollController, // Asocio mi scroll controller
      padding: const EdgeInsets.all(8.0),
      itemCount: _messages.length,
      itemBuilder: (ctx, index) {
        final msg = _messages[index];
        // Renderizo una burbuja por cada mensaje en mi lista de estado
        return Padding(
           padding: const EdgeInsets.symmetric(vertical: 4.0), // Espacio entre burbujas
           child: ChatBubble(
             text: msg.text,
             isMe: msg.isMe,
             createdAt: msg.createdAt,
           ),
        );
      },
    );
  }

  /// Widget de helper para construir la barra de input de texto.
  Widget _buildMessageInput() {
    return Container(
        // Fondo gris claro para la barra
        decoration: BoxDecoration(
            color: Colors.grey[50], 
            border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1.0))),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: SafeArea( // SafeArea para evitar el "notch" o la barra inferior
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [ // CrossAxisAlignment.end para que el botón se alinee abajo si el textfield crece
          Expanded(
              child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                      hintText: 'Escribe tu mensaje seguro...',
                      hintStyle: Theme.of(context).inputDecorationTheme.hintStyle, 
                      filled: true,
                      fillColor: Colors.white, // Campo de texto blanco
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
                  maxLines: 5, // Permitir que crezca hasta 5 líneas
                  minLines: 1)),
          const SizedBox(width: 8),
          // Botón de enviar
          SizedBox(
              height: 48,
              width: 48,
              child: IconButton.filled(
                  style: IconButton.styleFrom(
                      // Uso mi color de acento
                      backgroundColor: Theme.of(context).hintColor, 
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder()),
                  icon: Icon(
                      Icons.send_rounded,
                      // Icono oscuro sobre botón claro
                      color: Theme.of(context).primaryColorDark, 
                      size: 24),
                  tooltip: "Enviar mensaje",
                  onPressed: _sendMessage)) // Llama a mi función de envío
        ])));
  }

} 