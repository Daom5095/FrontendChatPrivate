// lib/services/chat_state_service.dart

import 'package:flutter/material.dart';

/// Un simple [ChangeNotifier] para rastrear qué conversación
/// está activa actualmente en la pantalla.
///
/// - HomeScreen escuchará esto para saber si un mensaje entrante
///   es para un chat "inactivo".
/// - ChatScreen establecerá el ID activo en [initState] y lo pondrá
///   en null en [dispose].
class ChatStateService with ChangeNotifier {
  
  int? _activeConversationId;

  /// El ID de la conversación que está abierta actualmente.
  /// `null` si ninguna está abierta (ej. el usuario está en HomeScreen).
  int? get activeConversationId => _activeConversationId;

  /// Llama a esto para establecer la conversación activa.
  void setActiveChat(int? conversationId) {
    if (_activeConversationId != conversationId) {
      _activeConversationId = conversationId;
      // No necesitamos notificar a los listeners,
      // esto es solo para consulta.
    }
  }

  /// Comprueba si un ID de conversación es el que está activo.
  bool isChatActive(int conversationId) {
    return _activeConversationId == conversationId;
  }
}