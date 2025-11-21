// lib/screens/groups/select_group_members_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../api/user_api.dart';
import 'create_group_screen.dart'; 

/// Pantalla para seleccionar miembros para un nuevo grupo.
class SelectGroupMembersScreen extends StatefulWidget {
  const SelectGroupMembersScreen({super.key});

  @override
  State<SelectGroupMembersScreen> createState() =>
      _SelectGroupMembersScreenState();
}

class _SelectGroupMembersScreenState extends State<SelectGroupMembersScreen> {
  final UserApi _userApi = UserApi();
  late Future<List<dynamic>> _usersFuture;
  
  final Set<int> _selectedUserIds = {};
  final Map<int, String> _selectedUserDetails = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() {
    final token = context.read<AuthService>().token;
    if (token == null) {
      _usersFuture = Future.error('No autenticado');
      return;
    }
    _usersFuture = _userApi.getAllUsers(token);
  }

  void _toggleUserSelection(int userId, String username, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedUserIds.add(userId);
        _selectedUserDetails[userId] = username;
      } else {
        _selectedUserIds.remove(userId);
        _selectedUserDetails.remove(userId);
      }
    });
  }

  void _navigateToCreateGroupScreen() {
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar al menos un miembro.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CreateGroupScreen(
          memberIds: _selectedUserIds.toList(),
          memberDetails: _selectedUserDetails,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Nuevo Grupo'),
        
        backgroundColor: Theme.of(context).primaryColor, 
        foregroundColor: Colors.white, 
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'Selecciona los miembros (${_selectedUserIds.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white.withOpacity(0.8)),
            ),
          ),
        ),
        
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
            return const Center(child: Text('No se encontraron otros usuarios.'));
          }

          final users = snapshot.data!;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (ctx, index) {
              final user = users[index];
              final userId = (user['id'] as num?)?.toInt();
              final username = user['username'] as String?;

              if (userId == null || username == null) {
                return const SizedBox.shrink();
              }

              final isSelected = _selectedUserIds.contains(userId);

              return CheckboxListTile(
                title: Text(username),
                value: isSelected,
                onChanged: (bool? value) {
                  if (value != null) {
                    _toggleUserSelection(userId, username, value);
                  }
                },
                secondary: CircleAvatar(
                  child: Text(username[0].toUpperCase()),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _selectedUserIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _navigateToCreateGroupScreen,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Siguiente'),
            )
          : null,
    );
  }
}