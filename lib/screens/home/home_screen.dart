// lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math'; // Para generar colores aleatorios basados en ID
import '../../services/auth_service.dart';
import '../../api/conversation_api.dart';
import '../users/user_list_screen.dart';
import '../chat/chat_screen.dart';
// Podríamos necesitar un paquete para formatear fechas más adelante
// import 'package:intl/intl.dart';

/// Pantalla principal después del login.
/// Muestra la lista de conversaciones existentes del usuario.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> _conversationsFuture;
  final ConversationApi _conversationApi = ConversationApi();

  // Colores base para generar colores de avatar pseudo-aleatorios
  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    print("HomeScreen [initState]: Cargando lista de conversaciones...");
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final authService = context.read<AuthService>();
    final token = authService.token;

    if (token == null) {
      print("HomeScreen [_loadConversations] ERROR: Token nulo.");
      if (mounted) {
        setState(() {
          _conversationsFuture = Future.error('No autenticado.');
        });
      }
      return;
    }

    if (mounted) {
       setState(() {
         // Aseguramos que se inicie una nueva carga
         _conversationsFuture = _conversationApi.getConversations(token);
       });
    }
  }

  void _navigateToChat(Map<String, dynamic> conversationData) {
     print("HomeScreen [_navigateToChat]: Navegando a ChatScreen para conversación ID ${conversationData['id']}");
     Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => ChatScreen(conversationData: conversationData),
        ),
     ).then((_) {
        // Recargar al volver, por si hay nuevos mensajes (aunque no los mostremos aún)
        print("HomeScreen: Volviendo de ChatScreen. Recargando conversaciones...");
        _loadConversations();
     });
  }

  // --- NUEVO: Función para generar color de avatar ---
  Color _getAvatarColor(int conversationId) {
    // Usa el ID de la conversación para elegir un color de forma determinista
    int index = conversationId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }
  // -------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Chats'),
        actions: [
          IconButton(
             icon: const Icon(Icons.refresh),
             tooltip: "Actualizar conversaciones",
             onPressed: _loadConversations,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: () {
              print("HomeScreen: Botón Logout presionado.");
              authService.logout();
            },
          )
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
             // ... (Widget de error con botón Reintentar - sin cambios) ...
             print("HomeScreen [FutureBuilder] Error: ${snapshot.error}");
            return Center(
               child: Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text('Error al cargar conversaciones: ${snapshot.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                         icon: const Icon(Icons.refresh),
                         label: const Text("Reintentar"),
                         onPressed: _loadConversations,
                      )
                    ],
                 ),
               )
             );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
             // ... (Mensaje de lista vacía - sin cambios) ...
             return const Center(
               child: Padding(
                 padding: EdgeInsets.all(16.0),
                 child: Text(
                    'No tienes conversaciones activas.\nPresiona + para iniciar una nueva.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
               )
             );
          }

          // --- Lista de Conversaciones con Mejoras Visuales ---
          final conversations = snapshot.data!;
          print("HomeScreen [FutureBuilder]: Mostrando ${conversations.length} conversaciones.");

          return ListView.separated( // Usamos separated para añadir divisores
            itemCount: conversations.length,
            separatorBuilder: (context, index) => Divider( // Línea divisoria
              height: 1, // Altura mínima
              thickness: 0.5, // Grosor sutil
              indent: 72, // Indentación para alinear con el texto (avatar + padding)
              endIndent: 16,
            ),
            itemBuilder: (ctx, index) {
              final conversation = conversations[index];
              if (conversation is! Map<String, dynamic> || conversation['id'] == null) {
                  print("HomeScreen [ListView] Warning: Datos de conversación inválidos en índice $index.");
                  return const SizedBox.shrink();
              }

              final conversationId = (conversation['id'] as num).toInt(); // Obtener ID para el color

              // --- Lógica para determinar el título (sin cambios) ---
              String displayTitle = "Conversación $conversationId";
              final explicitTitle = conversation['title'] as String?;
              final participants = conversation['participants'] as List?;
              final currentUserId = authService.userId;
              if (explicitTitle != null && explicitTitle.isNotEmpty) {
                 displayTitle = explicitTitle;
              } else if (participants != null && currentUserId != null) {
                 final otherParticipant = participants.firstWhere(
                    (p) => p is Map && p['userId'] != null && p['userId'] != currentUserId,
                    orElse: () => null,
                 );
                 if (otherParticipant != null) {
                    final username = otherParticipant['username'] as String?;
                    displayTitle = username ?? 'Usuario ${otherParticipant['userId']}';
                 } else if (participants.isNotEmpty && participants.first['userId'] == currentUserId) {
                    displayTitle = 'Chat contigo mismo';
                 }
              }
              // --- Fin Lógica Título ---

              // --- Placeholders para último mensaje y hora ---
              String lastMessageSnippet = "Toca para iniciar el chat..."; // Placeholder inicial
              String lastMessageTime = ""; // Placeholder hora (vacío por ahora)
              // TODO: Reemplazar con datos reales cuando se implemente
              // ---------------------------------------------

              // --- Construcción del ListTile Mejorado ---
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Ajustar padding
                leading: CircleAvatar(
                  backgroundColor: _getAvatarColor(conversationId), // Color basado en ID
                  foregroundColor: Colors.white, // Color de la letra (inicial)
                  child: Text(
                      displayTitle.isNotEmpty ? displayTitle[0].toUpperCase() : 'C',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                   displayTitle,
                   style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), // Estilo título
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis, // Evitar que el título se desborde
                  ),
                subtitle: Text(
                   lastMessageSnippet,
                   style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), // Estilo subtítulo
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis, // Evitar desbordamiento
                  ),
                trailing: Text( // Elemento a la derecha para la hora
                   lastMessageTime,
                   style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey), // Estilo hora
                  ),
                onTap: () {
                  _navigateToChat(conversation);
                },
              );
              // --- Fin ListTile Mejorado ---
            },
          ); // Fin ListView.separated
        },
      ), // Fin FutureBuilder
      floatingActionButton: FloatingActionButton(
        tooltip: "Iniciar nueva conversación",
        child: const Icon(Icons.add_comment_outlined),
        onPressed: () {
          print("HomeScreen: Botón FAB presionado. Navegando a UserListScreen...");
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const UserListScreen()),
          );
        },
      ),
    ); // Fin Scaffold
  }
} // Fin clase _HomeScreenState