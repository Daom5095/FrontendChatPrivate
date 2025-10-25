// lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart'; // Para logout y obtener token
import '../../api/conversation_api.dart'; // ¡Necesitamos esto para cargar las conversaciones!
import '../users/user_list_screen.dart'; // Para el botón de nuevo chat
import '../chat/chat_screen.dart'; // Para navegar al chat existente

/// Pantalla principal después del login.
/// Muestra la lista de conversaciones existentes del usuario.
class HomeScreen extends StatefulWidget {
  // Convertido a StatefulWidget para manejar la carga de conversaciones
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Future para cargar la lista de conversaciones
  late Future<List<dynamic>> _conversationsFuture;

  // Instancia de la API de conversaciones
  final ConversationApi _conversationApi = ConversationApi();

  @override
  void initState() {
    super.initState();
    print("HomeScreen [initState]: Cargando lista de conversaciones...");
    // Iniciar la carga de conversaciones al construir la pantalla
    _loadConversations();
  }

  /// Carga la lista de conversaciones del usuario desde la API del backend.
  Future<void> _loadConversations() async {
    // Usar context.read para obtener AuthService sin escuchar cambios
    final authService = context.read<AuthService>();
    final token = authService.token;

    // Validación: Si no hay token, no podemos cargar nada.
    if (token == null) {
      print("HomeScreen [_loadConversations] ERROR: Token nulo. No se pueden cargar conversaciones.");
      // Asignar un Future que falle para que FutureBuilder lo muestre
      if (mounted) { // Verificar si el widget sigue montado antes de llamar a setState
        setState(() {
          _conversationsFuture = Future.error('No autenticado. No se pudo obtener el token.');
        });
      }
      return; // Detener
    }

    // Si hay token, iniciamos la llamada a la API
    // Asegurarse de que la llamada a setState ocurra solo si el widget está montado
    if (mounted) {
       setState(() {
         // Llamamos al nuevo método `getConversations` que añadiremos a ConversationApi
         _conversationsFuture = _conversationApi.getConversations(token); // Llama a GET /api/conversations
       });
    }
  }

  /// Navega a la pantalla de chat para una conversación específica.
  void _navigateToChat(Map<String, dynamic> conversationData) {
     print("HomeScreen [_navigateToChat]: Navegando a ChatScreen para conversación ID ${conversationData['id']}");
     Navigator.of(context).push(
        MaterialPageRoute(
          // Pasamos los datos completos de la conversación a ChatScreen
          builder: (ctx) => ChatScreen(conversationData: conversationData),
        ),
     ).then((_) {
        // Opcional: Recargar la lista de conversaciones cuando volvemos de un chat
        // Esto podría ser útil si implementamos "último mensaje" o "no leídos"
        print("HomeScreen: Volviendo de ChatScreen. Recargando conversaciones...");
        _loadConversations();
     });
  }

  @override
  Widget build(BuildContext context) {
    // Usamos context.watch aquí si quisiéramos reaccionar a cambios en AuthService (ej. logout)
    // Pero para logout, el botón ya lo maneja explícitamente.
    // Para el token en _loadConversations, usamos context.read.
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Chats'), // Título más específico
        actions: [
          // Botón para refrescar la lista de conversaciones
          IconButton(
             icon: const Icon(Icons.refresh),
             tooltip: "Actualizar conversaciones",
             onPressed: _loadConversations, // Llama al método de carga
          ),
          // Botón de Logout
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: () {
              print("HomeScreen: Botón Logout presionado.");
              authService.logout();
              // AuthService notificará a los listeners (como en main.dart)
              // y la navegación a LoginScreen ocurrirá automáticamente.
            },
          )
        ],
      ),
      // Cuerpo principal: Usamos FutureBuilder para manejar la carga de conversaciones
      body: FutureBuilder<List<dynamic>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          // 1. Estado de Carga
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // 2. Estado de Error
          if (snapshot.hasError) {
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
                         onPressed: _loadConversations, // Botón para reintentar
                      )
                    ],
                 ),
               )
             );
          }
          // 3. Estado sin Datos (lista vacía)
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
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

          // 4. Estado con Datos: Mostrar la lista de conversaciones
          final conversations = snapshot.data!;
          print("HomeScreen [FutureBuilder]: Mostrando ${conversations.length} conversaciones.");

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (ctx, index) {
              final conversation = conversations[index];
              // Validar que la conversación es un mapa y tiene ID
              if (conversation is! Map<String, dynamic> || conversation['id'] == null) {
                  print("HomeScreen [ListView] Warning: Datos de conversación inválidos en índice $index. Saltando.");
                  return const SizedBox.shrink(); // No mostrar si los datos son incorrectos
              }

              // Determinar el título a mostrar para esta conversación
              String displayTitle = "Conversación ${conversation['id']}"; // Fallback
              String? lastMessage = "Inicia la conversación..."; // Placeholder
              DateTime? lastMessageTime; // Placeholder

              // Intentar obtener un título más descriptivo (similar a ChatScreen)
              final explicitTitle = conversation['title'] as String?;
              final participants = conversation['participants'] as List?;
              final currentUserId = authService.userId; // Obtener ID actual

              if (explicitTitle != null && explicitTitle.isNotEmpty) {
                 displayTitle = explicitTitle;
              } else if (participants != null && currentUserId != null) {
                 // Buscar al otro participante en chats directos
                 final otherParticipant = participants.firstWhere(
                    (p) => p is Map && p['userId'] != null && p['userId'] != currentUserId,
                    orElse: () => null,
                 );
                 if (otherParticipant != null) {
                    final username = otherParticipant['username'] as String?;
                    displayTitle = username ?? 'Usuario ${otherParticipant['userId']}';
                 } else if (participants.isNotEmpty && participants.first['userId'] == currentUserId) {
                    // Caso raro: chat solo conmigo mismo? O error en datos.
                    displayTitle = 'Chat contigo mismo';
                 }
              }

              // TODO: Aquí iría la lógica para obtener y mostrar el último mensaje y su hora

              // Construir el ListTile para esta conversación
              return ListTile(
                leading: CircleAvatar(
                   // Usar inicial del título o un icono de chat
                  child: Text(displayTitle.isNotEmpty ? displayTitle[0].toUpperCase() : 'C'),
                ),
                title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(lastMessage ?? ''), // Mostrar último mensaje (placeholder)
                // trailing: Text(lastMessageTime != null ? /* formatear hora */ : ''), // Mostrar hora (placeholder)
                onTap: () {
                  // Navegar a la pantalla de chat al tocar
                  _navigateToChat(conversation);
                },
              );
            },
          ); // Fin ListView.builder
        },
      ), // Fin FutureBuilder

      // Botón flotante para iniciar nueva conversación (sin cambios)
      floatingActionButton: FloatingActionButton(
        tooltip: "Iniciar nueva conversación",
        child: const Icon(Icons.add_comment_outlined), // Icono más descriptivo
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