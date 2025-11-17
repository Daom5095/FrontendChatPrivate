// lib/screens/groups/add_participant_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/user_api.dart';
import '../../api/conversation_api.dart';
import '../../services/auth_service.dart';

class AddParticipantScreen extends StatefulWidget {
  final int conversationId;
  // Recibimos los IDs de los miembros actuales para no volver a mostrarlos
  final Set<int> currentMemberIds;

  const AddParticipantScreen({
    super.key,
    required this.conversationId,
    required this.currentMemberIds,
  });

  @override
  State<AddParticipantScreen> createState() => _AddParticipantScreenState();
}

class _AddParticipantScreenState extends State<AddParticipantScreen> {
  final UserApi _userApi = UserApi();
  final ConversationApi _conversationApi = ConversationApi();
  late Future<List<dynamic>> _usersFuture;
  
  // Guardamos el token para no tener que buscarlo en cada tap
  String? _token;

  @override
  void initState() {
    super.initState();
    _token = context.read<AuthService>().token;
    _loadAvailableUsers();
  }

  void _loadAvailableUsers() {
    if (_token == null) {
      _usersFuture = Future.error('No autenticado');
      return;
    }
    // Cargamos TODOS los usuarios
    _usersFuture = _userApi.getAllUsers(_token!);
  }

  /// Llama a la API para añadir el usuario y vuelve atrás
  Future<void> _addParticipant(int userId, String username) async {
    if (_token == null) return;

    // Mostramos un diálogo de confirmación
    final bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Añadir a $username'),
        content: Text('¿Estás seguro de que quieres añadir a $username a este grupo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _conversationApi.addParticipant(
        _token!,
        widget.conversationId,
        userId,
      );

      if (!mounted) return;
      // Si tiene éxito, cerramos esta pantalla y devolvemos 'true'
      // para que la pantalla anterior sepa que debe refrescar
      Navigator.of(context).pop(true);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al añadir: ${e.toString()}'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir Participante'),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar usuarios: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No se encontraron usuarios.'));
          }

          // Filtramos la lista:
          // Solo mostramos usuarios que NO estén ya en el grupo
          final availableUsers = snapshot.data!.where((user) {
            final userId = (user['id'] as num?)?.toInt();
            return userId != null && !widget.currentMemberIds.contains(userId);
          }).toList();
          
          if (availableUsers.isEmpty) {
            return const Center(child: Text('No hay más usuarios para añadir.'));
          }

          return ListView.builder(
            itemCount: availableUsers.length,
            itemBuilder: (ctx, index) {
              final user = availableUsers[index];
              final userId = (user['id'] as num).toInt();
              final username = user['username'] as String;

              return ListTile(
                title: Text(username),
                leading: CircleAvatar(
                  child: Text(username[0].toUpperCase()),
                ),
                onTap: () => _addParticipant(userId, username),
              );
            },
          );
        },
      ),
    );
  }
}