// lib/screens/chat/chat_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:uuid/uuid.dart';

import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/crypto_service.dart';
import '../../api/conversation_api.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> conversationData;
  const ChatScreen({super.key, required this.conversationData});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<types.Message> _messages = [];
  late final types.User _user;
  final Map<int, types.User> _participantUserMap = {};

  String _chatTitle = "Chat";
  final SocketService _socketService = SocketService();
  final CryptoService _cryptoService = CryptoService();
  final ConversationApi _conversationApi = ConversationApi();
  late final int _currentUserId;
  String? _privateKeyPem;

  bool _isLoadingHistory = true;
  bool _hasMissingPrivateKey = false;
  bool _hasInitializationError = false;

  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    print("ChatScreen [initState]: Iniciando conversación ID ${widget.conversationData['id']}");

    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.userId == null || authService.token == null || authService.username == null) {
      print("ChatScreen [initState] ERROR: Faltan datos de autenticación.");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isLoadingHistory = false;
            _hasInitializationError = true;
          });
        }
      });
      return;
    }

    _currentUserId = authService.userId!;
    _user = types.User(id: _currentUserId.toString(), firstName: authService.username);

    final participants = widget.conversationData['participants'] as List?;
    if (participants != null) {
      for (var p in participants) {
        if (p is Map && p['userId'] != null) {
          final int userId = (p['userId'] as num).toInt();
          _participantUserMap[userId] = types.User(
            id: userId.toString(),
            firstName: p['username'] as String? ?? 'Usuario $userId',
          );
        }
      }
    }
    _participantUserMap[_currentUserId] = _user;

    _setupChatTitle();
    _initializeChat(authService);
  }

  types.User _getAuthor(int senderId) {
    return _participantUserMap[senderId] ??
        types.User(id: senderId.toString(), firstName: 'Usuario $senderId');
  }

  void _setupChatTitle() {
    final explicitTitle = widget.conversationData['title'] as String?;
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      _chatTitle = explicitTitle;
    } else {
      final otherParticipant = _participantUserMap.values.firstWhere(
        (u) => u.id != _currentUserId.toString(),
        orElse: () => _user,
      );
      _chatTitle = otherParticipant.id == _user.id
          ? 'Chat contigo mismo'
          : 'Chat con ${otherParticipant.firstName ?? 'Usuario'}';
    }
    if (mounted) setState(() {});
  }

  Future<void> _initializeChat(AuthService authService) async {
    try {
      _privateKeyPem = await authService.getPrivateKeyForSession();
      if (_privateKeyPem == null) {
        setState(() {
          _hasMissingPrivateKey = true;
          _hasInitializationError = true;
          _isLoadingHistory = false;
        });
        return;
      }

      final token = authService.token;
      if (token != null) {
        await _loadAndDecryptHistory(token);
        _socketService.connect(token, _onMessageReceived);
      } else {
        throw Exception("Token nulo durante la inicialización.");
      }
    } catch (e) {
      print("ChatScreen [initializeChat] ERROR: $e");
      if (mounted) {
        setState(() {
          _hasInitializationError = true;
          _isLoadingHistory = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _loadAndDecryptHistory(String token) async {
    final conversationId = (widget.conversationData['id'] as num?)?.toInt();
    if (conversationId == null) return;

    try {
      final historyData = await _conversationApi.getMessages(token, conversationId);
      if (historyData.isEmpty) return;

      List<types.Message> decryptedHistory = [];
      for (var msgData in historyData) {
        try {
          final ciphertext = msgData['ciphertext'];
          final encryptedKey = msgData['encryptedKey'];
          final senderId = (msgData['senderId'] as num?)?.toInt();
          final createdAtStr = msgData['createdAt'];

          if (ciphertext == null || encryptedKey == null || senderId == null || createdAtStr == null) continue;

          final combinedKeyIV = await _cryptoService.decryptRSA(encryptedKey, _privateKeyPem!);
          final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
          final plainText = _cryptoService.decryptAES_CBC(
              ciphertext, aesKeyMap['key']!, aesKeyMap['iv']!);

          final message = types.TextMessage(
            author: _getAuthor(senderId),
            id: _uuid.v4(),
            text: plainText,
            createdAt: DateTime.parse(createdAtStr).millisecondsSinceEpoch,
          );
          decryptedHistory.add(message);
        } catch (e) {
          print("Error descifrando mensaje: $e");
        }
      }

      decryptedHistory.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

      if (mounted) {
        setState(() => _messages.addAll(decryptedHistory));
      }
    } catch (e) {
      print("ChatScreen [_loadAndDecryptHistory] ERROR: $e");
    }
  }

  Future<void> _onMessageReceived(StompFrame frame) async {
    if (frame.body == null) return;
    if (_privateKeyPem == null) return;

    try {
      final decodedBody = json.decode(frame.body!);
      final conversationId = (decodedBody['conversationId'] as num?)?.toInt();
      final expectedConversationId = (widget.conversationData['id'] as num?)?.toInt();

      if (conversationId != expectedConversationId) return;

      final senderId = (decodedBody['senderId'] as num?)?.toInt();
      if (senderId == null || senderId == _currentUserId) return;

      final ciphertext = decodedBody['ciphertext'];
      final encryptedKeys = decodedBody['encryptedKeys'] as Map<String, dynamic>?;
      final encryptedCombinedKey = encryptedKeys?[_currentUserId.toString()];
      if (ciphertext == null || encryptedCombinedKey == null) return;

      final combinedKeyIV =
          await _cryptoService.decryptRSA(encryptedCombinedKey, _privateKeyPem!);
      final aesKeyMap = _cryptoService.splitKeyIV(combinedKeyIV);
      final plainText =
          _cryptoService.decryptAES_CBC(ciphertext, aesKeyMap['key']!, aesKeyMap['iv']!);

      final newMessage = types.TextMessage(
        author: _getAuthor(senderId),
        id: _uuid.v4(),
        text: plainText,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      if (mounted) setState(() => _messages.insert(0, newMessage));
    } catch (e) {
      print("Error procesando mensaje STOMP: $e");
    }
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    final plainText = message.text.trim();
    if (plainText.isEmpty) return;

    final optimisticMessage = types.TextMessage(
      author: _user,
      id: _uuid.v4(),
      text: plainText,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() => _messages.insert(0, optimisticMessage));

    try {
      final participants = widget.conversationData['participants'] as List?;
      final participantIds = participants
              ?.map((p) => (p['userId'] as num?)?.toInt())
              .whereType<int>()
              .toList() ??
          [];

      if (!participantIds.contains(_currentUserId)) {
        participantIds.add(_currentUserId);
      }

      final conversationId = (widget.conversationData['id'] as num?)?.toInt();
      await _socketService.sendMessage(conversationId!, plainText, participantIds);
    } catch (e) {
      print("Error enviando mensaje: $e");
      setState(() => _messages.removeWhere((m) => m.id == optimisticMessage.id));
    }
  }

  @override
  void dispose() {
    _socketService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_isLoadingHistory) {
      body = const Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text("Cargando chat seguro...")
        ],
      ));
    } else if (_hasInitializationError) {
      body = _buildError();
    } else {
      body = Chat(
        messages: _messages,
        onSendPressed: _handleSendPressed,
        user: _user,
        showUserNames: true,
        showUserAvatars: true,
        theme: DefaultChatTheme(
          backgroundColor: theme.scaffoldBackgroundColor,
          primaryColor: theme.primaryColor,
          secondaryColor: theme.cardColor,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_chatTitle),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.verified_user_outlined, color: Colors.white70),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildError() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
          SizedBox(height: 16),
          Text("Error al cargar el chat"),
        ],
      ),
    );
  }
}
