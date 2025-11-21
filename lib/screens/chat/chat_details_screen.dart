// lib/screens/chat/chat_details_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/conversation_api.dart';
import '../../services/auth_service.dart';
import '../groups/add_participant_screen.dart'; 

class ChatDetailsScreen extends StatefulWidget {
  // Recibimos los datos iniciales de la pantalla de chat
  final Map<String, dynamic> conversationData;

  const ChatDetailsScreen({
    super.key,
    required this.conversationData,
  });

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  final ConversationApi _conversationApi = ConversationApi();
  
  // Usamos un Future para la lista de participantes,
  // así podemos recargarla fácilmente
  late Future<List<dynamic>> _participantsFuture;
  
  late int _conversationId;
  late String _chatTitle;
  late bool _isGroupChat;
  late int _currentUserId;
  late String _myRole;
  bool _isOwner = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _token = context.read<AuthService>().token;
    _currentUserId = context.read<AuthService>().userId!;
    
    _conversationId = (widget.conversationData['id'] as num).toInt();
    _chatTitle = widget.conversationData['title'] ?? 'Chat';
    _isGroupChat = widget.conversationData['type'] == 'group';

    // Cargamos los participantes iniciales y buscamos nuestro rol
    _loadInitialParticipants();
  }

  /// Carga la lista inicial de participantes y determina el rol del usuario
  void _loadInitialParticipants() {
    final List<dynamic> initialParticipants = 
        widget.conversationData['participants'] ?? [];
    
    // Buscamos nuestro rol
    final myParticipantData = initialParticipants.firstWhere(
      (p) => p['userId'] == _currentUserId,
      orElse: () => null,
    );
    _myRole = myParticipantData?['role'] ?? 'member';
    _isOwner = (_myRole == 'owner');

    // Asignamos el Future inicial
    _participantsFuture = Future.value(initialParticipants);
  }

  /// Llama a la API para refrescar la lista de participantes
  void _refreshParticipants() {
    if (_token == null) return;
    setState(() {
      // Disparamos una nueva llamada a la API y el FutureBuilder reaccionará
      _participantsFuture = _conversationApi.getParticipants(_token!, _conversationId);
    });
  }

  /// Navega a la pantalla de "Añadir Participante"
  void _navigateToAddParticipant(List<dynamic> currentParticipants) {
    // Creamos un Set de IDs para pasarlo a la siguiente pantalla
    final currentIds = currentParticipants.map((p) => (p['userId'] as num).toInt()).toSet();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => AddParticipantScreen(
          conversationId: _conversationId,
          currentMemberIds: currentIds,
        ),
      ),
    ).then((didAddUser) {
      // Si `didAddUser` es true, refrescamos la lista
      if (didAddUser == true) {
        _refreshParticipants();
      }
    });
  }

  /// Llama a la API para eliminar un participante
  Future<void> _removeParticipant(int userIdToRemove, String username) async {
    if (_token == null) return;

    // Lógica de confirmación
    final bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar a $username'),
        content: Text('¿Estás seguro de que quieres eliminar a $username de este grupo?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _conversationApi.removeParticipant(_token!, _conversationId, userIdToRemove);
      // Éxito: refrescamos la lista
      _refreshParticipants();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: ${e.toString()}'))
        );
      }
    }
  }

  /// Llama a la API para que el usuario actual abandone el grupo
  Future<void> _leaveGroup() async {
    if (_token == null) return;
    
    final bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonar Grupo'),
        content: const Text('¿Estás seguro de que quieres abandonar este grupo?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Abandonar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _conversationApi.removeParticipant(_token!, _conversationId, _currentUserId);
      
      if (!mounted) return;
      // Éxito: Volvemos a la pantalla de Home (borrando el historial de chat)
      Navigator.of(context).popUntil((route) => route.isFirst);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abandonar el grupo: ${e.toString()}'))
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_chatTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar lista',
            onPressed: _refreshParticipants,
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _participantsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No se encontraron participantes.'));
          }

          final participants = snapshot.data!;
          
          return ListView(
            children: [
              // --- Sección de Añadir Participante (solo para owners) ---
              if (_isOwner)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_add)),
                  title: const Text('Añadir Participante'),
                  onTap: () => _navigateToAddParticipant(participants),
                ),
              if (_isOwner) const Divider(),
              
             
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Participantes (${participants.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // --- Lista de Participantes ---
              ...participants.map((p) {
                final String username = p['username'] ?? 'Usuario';
                final String role = p['role'] ?? 'member';
                final int pUserId = (p['userId'] as num).toInt();

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(username[0].toUpperCase()),
                  ),
                  title: Text(username),
                  subtitle: Text(role == 'owner' ? 'Propietario' : 'Miembro'),
                  // --- Lógica del botón de eliminar ---
                  trailing: (_isOwner && pUserId != _currentUserId)
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          tooltip: 'Eliminar del grupo',
                          onPressed: () => _removeParticipant(pUserId, username),
                        )
                      : null,
                );
              }).toList(),

              const Divider(height: 32, thickness: 1),

              // --- Botón de Salir del Grupo ---
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.exit_to_app),
                ),
                title: const Text('Abandonar Grupo'),
                textColor: Colors.red,
                onTap: _leaveGroup,
              ),
            ],
          );
        },
      ),
    );
  }
}