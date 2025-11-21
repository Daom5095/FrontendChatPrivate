// lib/screens/groups/create_group_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/conversation_api.dart';
import '../../services/auth_service.dart';
import '../chat/chat_screen.dart';
import '../home/home_screen.dart'; 

/// Pantalla final para poner nombre al grupo y crearlo.
class CreateGroupScreen extends StatefulWidget {
  final List<int> memberIds;
  final Map<int, String> memberDetails;

  const CreateGroupScreen({
    super.key,
    required this.memberIds,
    required this.memberDetails,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final ConversationApi _conversationApi = ConversationApi();
  bool _isLoading = false;

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    final title = _titleController.text.trim();
    final token = context.read<AuthService>().token;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de autenticación.'))
      );
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final newConversationData = await _conversationApi.createGroupConversation(
        token,
        title,
        widget.memberIds,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (ctx) => const HomeScreen(), 
        ),
        (route) => route.isFirst, 
      );
      Navigator.of(context).push(
         MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: newConversationData), 
        ),
      );


    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear el grupo: ${e.toString()}'))
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nombre del Grupo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Miembros (${widget.memberDetails.length}):',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: widget.memberDetails.values.map((username) => Chip(
                label: Text(username),
                avatar: CircleAvatar(child: Text(username[0].toUpperCase())),
              )).toList(),
            ),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del grupo',
                  prefixIcon: Icon(Icons.group_work),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre del grupo es obligatorio';
                  }
                  return null;
                },
              ),
            ),
            const Spacer(), 
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.check),
                label: const Text('Crear Grupo'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)
                ),
              ),
          ],
        ),
      ),
    );
  }
}