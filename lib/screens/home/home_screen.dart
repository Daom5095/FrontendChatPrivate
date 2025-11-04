// lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math'; // Para generar colores aleatorios basados en ID
import 'package:intl/intl.dart'; // Importado para formatear fechas
import '../../services/auth_service.dart';
import '../../api/conversation_api.dart';
import '../users/user_list_screen.dart';
import '../chat/chat_screen.dart';
import '../../services/crypto_service.dart'; 

/// Pantalla principal después del login.
/// Muestra la lista de conversaciones existentes del usuario.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Estado (lógica) de la pantalla principal.
class _HomeScreenState extends State<HomeScreen> {
  /// El Future que usará mi `FutureBuilder` para renderizar la UI.
  /// Se inicializa en `initState` y contendrá la lista de conversaciones.
  late Future<List<dynamic>> _conversationsFuture;

  // --- Dependencias de Servicios y APIs ---
  /// Mi API para llamar a /api/conversations
  final ConversationApi _conversationApi = ConversationApi();
  /// Mi caja de herramientas de criptografía (para descifrar snippets)
  final CryptoService _cryptoService = CryptoService();
  
  /// Aquí guardo mi clave privada RSA (PEM) en memoria.
  /// La necesito para poder descifrar el último mensaje de cada conversación.
  String? _privateKeyPem; 

  /// Lista de colores base para los avatares.
  /// Los elijo de forma determinista usando el ID de la conversación.
  final List<Color> _avatarBaseColors = [
    Colors.blue, Colors.green, Colors.red, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    print("HomeScreen [initState]: Cargando...");
    
    // Asigno el Future INMEDIATAMENTE al método de inicialización.
    // Mi `FutureBuilder` en el `build()` se enganchará a este future.
    _conversationsFuture = _initializeHomeScreen();
  }

  /// Orquesta la carga de datos necesarios para esta pantalla.
  ///
  /// Este método es llamado por `initState` y es el `Future`
  /// que mi `FutureBuilder` principal va a esperar.
  ///
  /// Flujo:
  /// 1. Obtiene la clave privada (fundamental) desde `AuthService`.
  /// 2. Si tiene la clave, llama a `_loadConversations` para obtener los chats.
  /// 3. Devuelve el `Future` de la lista de chats.
  /// 4. Si algo falla (ej. clave no encontrada), lanza una excepción
  ///    que será capturada por el `FutureBuilder` (en `snapshot.hasError`).
  Future<List<dynamic>> _initializeHomeScreen() async {
    // Aseguro que el widget esté montado antes de usar 'context'
    if (!mounted) return []; 
    
    // Uso context.read() porque solo necesito el servicio una vez, no necesito "escuchar"
    final authService = context.read<AuthService>();
    
    try {
      // --- Paso 1: Obtener mi clave privada ---
      // La necesito *antes* de cargar los chats para poder descifrar los snippets.
      print("HomeScreen [_initializeHomeScreen]: Obteniendo clave privada...");
      _privateKeyPem = await authService.getPrivateKeyForSession();
      
      // Si la clave es nula, es un error fatal para esta pantalla.
      if (_privateKeyPem == null) {
        throw Exception("No se pudo obtener la clave privada.");
      }
      print("HomeScreen [_initializeHomeScreen]: Clave privada obtenida.");

      // --- Paso 2: Cargar y devolver las conversaciones ---
      // Si tenemos la clave, ahora sí cargo la lista de chats
      // y devuelvo este Future.
      return _loadConversations(authService.token);
      
    } catch (e) {
      print("HomeScreen [_initializeHomeScreen] Error: $e");
      // Si falla (clave o carga de chats), lanzo el error
      // para que el FutureBuilder muestre el estado de error.
      throw Exception('Error al iniciar: $e');
    }
  }

  /// Método helper que llama a la API para obtener la lista de conversaciones.
  /// Devuelve el Future directamente para que el `FutureBuilder` lo maneje.
  Future<List<dynamic>> _loadConversations(String? token) async {
    if (token == null) {
      print("HomeScreen [_loadConversations] ERROR: Token nulo.");
      throw Exception('No autenticado.');
    }
    // Simplemente devuelvo el Future de la API.
    return _conversationApi.getConversations(token);
  }

  /// Navega a la pantalla de chat (`ChatScreen`) para la conversación seleccionada.
  void _navigateToChat(Map<String, dynamic> conversationData) {
     print("HomeScreen [_navigateToChat]: Navegando a ChatScreen para conversación ID ${conversationData['id']}");
     
     Navigator.of(context).push(
        MaterialPageRoute(
          // Le paso los datos de la conversación (ID, participantes) a la pantalla de chat
          builder: (ctx) => ChatScreen(conversationData: conversationData),
        ),
     ).then((_) {
        // --- IMPORTANTE: Refrescar al volver ---
        // Este código se ejecuta cuando "vuelvo" (con pop) de la ChatScreen.
        // Vuelvo a cargar la lista de chats por si hubo mensajes nuevos
        // y así actualizar el snippet y la hora.
        print("HomeScreen: Volviendo de ChatScreen. Recargando conversaciones...");
        setState(() {
          // Asigno un *nuevo* Future a la variable de estado.
          // Esto hace que el FutureBuilder se reconstruya y recargue.
          _conversationsFuture = _loadConversations(context.read<AuthService>().token);
        });
     });
  }

  /// Helper para obtener un color determinista para el avatar
  /// basado en el ID de la conversación.
  Color _getAvatarColor(int conversationId) {
    int index = conversationId % _avatarBaseColors.length;
    return _avatarBaseColors[index];
  }

  /// Helper para formatear la fecha del último mensaje (snippet).
  /// Muestra 'HH:mm' si es hoy, 'Ayer' si fue ayer, o 'dd/MM/yy' si es más antiguo.
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateToCompare = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToCompare == today) {
      return DateFormat('HH:mm').format(timestamp); // Ej: 14:30
    } else if (dateToCompare == yesterday) {
      return "Ayer";
    } else {
      return DateFormat('dd/MM/yy').format(timestamp); // Ej: 29/10/25
    }
  }

  @override
  Widget build(BuildContext context) {
    // Obtengo el AuthService (sin escuchar) para el botón de logout
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Chats'),
        actions: [
          // Botón para refrescar manualmente
          IconButton(
             icon: const Icon(Icons.refresh),
             tooltip: "Actualizar conversaciones",
             onPressed: () {
                // Para refrescar, solo necesito asignar un nuevo Future
                // a la variable de estado `_conversationsFuture`.
                setState(() {
                  _conversationsFuture = _loadConversations(authService.token);
                });
             },
          ),
          // Botón de cerrar sesión
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: () {
              print("HomeScreen: Botón Logout presionado.");
              // AuthService se encarga de limpiar el token, la clave,
              // y notificar a main.dart para que redirija a LoginScreen.
              authService.logout();
            },
          )
        ],
      ),
      // El cuerpo es un FutureBuilder que espera a que _conversationsFuture se complete.
      body: FutureBuilder<List<dynamic>>(
        future: _conversationsFuture, // 1. El Future que estamos esperando
        builder: (context, snapshot) {
          
          // --- Estado 1: Cargando ---
          // Esto se muestra mientras `_initializeHomeScreen` está en ejecución
          // (obteniendo clave Y cargando chats).
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // --- Estado 2: Error ---
          // Si `_initializeHomeScreen` lanzó una excepción (ej. sin clave, sin red)
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
                         onPressed: () {
                            // Reintento llamando a _initializeHomeScreen de nuevo
                            setState(() {
                              _conversationsFuture = _initializeHomeScreen();
                            });
                         }, 
                      )
                    ],
                 ),
               )
             );
          }
          
          // --- Estado 3: Lista Vacía ---
          // Si el Future se completó pero no trajo datos (o la lista está vacía)
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
             return Center(
               child: Padding(
                 padding: const EdgeInsets.all(24.0),
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   crossAxisAlignment: CrossAxisAlignment.center,
                   children: [
                     Icon(
                       Icons.chat_bubble_outline_rounded,
                       size: 80,
                       color: Colors.grey[300],
                     ),
                     const SizedBox(height: 16),
                     Text(
                       'No tienes conversaciones activas',
                       textAlign: TextAlign.center,
                       style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                     ),
                     const SizedBox(height: 8),
                     Text(
                       'Presiona + para iniciar una nueva.',
                       textAlign: TextAlign.center,
                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                     ),
                   ],
                 )
               )
             );
          }

          // --- Estado 4: Éxito (Mostrar Lista) ---
          final conversations = snapshot.data!;
          print("HomeScreen [FutureBuilder]: Mostrando ${conversations.length} conversaciones.");

          // Verificación de seguridad:
          // Si llegamos aquí, `_initializeHomeScreen` tuvo éxito,
          // por lo que `_privateKeyPem` *debería* estar cargado.
          if (_privateKeyPem == null) {
            // Esto no debería pasar si la lógica de _initializeHomeScreen es correcta.
            return const Center(child: Text("Error fatal: No se pudo cargar la clave privada."));
          }

          // Uso ListView.separated para poner un divisor entre cada chat
          return ListView.separated( 
            itemCount: conversations.length,
            separatorBuilder: (context, index) => Divider( 
              height: 1, 
              thickness: 0.5, 
              indent: 72, // Para alinear con el texto, no con el avatar
              endIndent: 16,
            ),
            itemBuilder: (ctx, index) {
              final conversation = conversations[index];
              // Validar que el dato sea correcto
              if (conversation is! Map<String, dynamic> || conversation['id'] == null) {
                  print("HomeScreen [ListView] Warning: Datos de conversación inválidos en índice $index.");
                  return const SizedBox.shrink(); // No renderizar nada si está mal
              }
              
              // Renderizo mi widget _ConversationTile para esta fila
              return _ConversationTile(
                conversation: conversation,
                currentUserId: authService.userId!,
                privateKeyPem: _privateKeyPem!, // Es seguro usar '!' por el check de arriba
                cryptoService: _cryptoService, 
                getAvatarColor: _getAvatarColor, // Paso la función helper
                formatTimestamp: _formatTimestamp, // Paso la función helper
                onTap: () => _navigateToChat(conversation), // Acción al tocar
              );
            },
          );
        },
      ),
      // Botón flotante para iniciar un nuevo chat
      floatingActionButton: FloatingActionButton(
        tooltip: "Iniciar nueva conversación",
        child: const Icon(Icons.add_comment_rounded),
        onPressed: () {
          print("HomeScreen: Botón FAB presionado. Navegando a UserListScreen...");
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const UserListScreen()),
          );
        },
      ),
    );
  }
} 


// --- Widget Interno _ConversationTile ---

/// Este es un widget `Stateful` *interno* para cada fila de la lista de chats.
///
/// Lo hice `Stateful` porque cada fila necesita manejar su propio estado
/// de "descifrando". El `FutureBuilder` principal carga la *lista*, pero
/// cada `_ConversationTile` descifra su *propio* snippet de forma asíncrona.
class _ConversationTile extends StatefulWidget {
  final Map<String, dynamic> conversation;
  final int currentUserId;
  final String privateKeyPem;
  final CryptoService cryptoService;
  final Function(int) getAvatarColor;
  final Function(DateTime) formatTimestamp;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.privateKeyPem,
    required this.cryptoService,
    required this.getAvatarColor,
    required this.formatTimestamp,
    required this.onTap,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

/// Estado (lógica) de mi `_ConversationTile`.
class _ConversationTileState extends State<_ConversationTile> {
  // Variables de estado para guardar los datos procesados/descifrados
  String _displayTitle = "";
  String _snippet = "Toca para iniciar el chat..."; // Texto por defecto
  String _timestamp = "";
  bool _isUnread = false; // (No implementado aún, pero listo para usarse)

  @override
  void initState() {
    super.initState();
    // Inicio el procesamiento y descifrado de los datos de *esta* conversación
    _processConversationData();
  }

  /// Procesa los datos de la conversación (título, último mensaje, descifrado).
  /// Esto se ejecuta una vez por cada fila.
  Future<void> _processConversationData() async {
    
    // --- 1. Lógica para determinar el Título del Chat ---
    final conversationId = (widget.conversation['id'] as num).toInt();
    String title = "Conversación $conversationId"; // Título de fallback
    final explicitTitle = widget.conversation['title'] as String?;
    final participants = widget.conversation['participants'] as List?;
    
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
       title = explicitTitle;
    } else if (participants != null) {
       // Si no hay título, busco el nombre del *otro* participante
       final otherParticipant = participants.firstWhere(
          (p) => p is Map && p['userId'] != null && p['userId'] != widget.currentUserId,
          orElse: () => null,
       );
       if (otherParticipant != null) {
          final username = otherParticipant['username'] as String?;
          title = username ?? 'Usuario ${otherParticipant['userId']}';
       } else if (participants.isNotEmpty && participants.first['userId'] == widget.currentUserId) {
          // Caso especial: es un chat solo conmigo mismo
          title = 'Chat contigo mismo';
       }
    }
    
    // --- 2. Lógica para procesar el Último Mensaje (Snippet) ---
    final lastMessageData = widget.conversation['lastMessage'] as Map<String, dynamic>?;
    String snippet = "Toca para iniciar el chat..."; // Default si no hay mensajes
    String timestamp = "";

    if (lastMessageData != null) {
      // Extraigo los datos del último mensaje
      final ciphertext = lastMessageData['text'] as String?; // Texto cifrado (AES)
      final encryptedKey = lastMessageData['encryptedKey'] as String?; // Clave cifrada (RSA)
      final createdAt = lastMessageData['createdAt'] as String?;

      // Formateo la fecha
      if (createdAt != null) {
         try {
           final ts = DateTime.parse(createdAt).toLocal();
           timestamp = widget.formatTimestamp(ts);
         } catch (e) { /* ignorar error de fecha */ }
      }

      // --- 3. Lógica de Descifrado del Snippet ---
      if (ciphertext != null && encryptedKey != null) {
        try {
          // 3a. Descifro la clave AES+IV (usando mi clave privada RSA)
          final combinedKeyIV = await widget.cryptoService.decryptRSA(encryptedKey, widget.privateKeyPem);
          // 3b. Separo la clave del IV
          final aesKeyMap = widget.cryptoService.splitKeyIV(combinedKeyIV);
          // 3c. Descifro el snippet (usando la clave AES)
          final plainText = widget.cryptoService.decryptAES_CBC(
            ciphertext, 
            aesKeyMap['key']!, 
            aesKeyMap['iv']!
          );
          snippet = plainText; // ¡Éxito!
        } catch (e) {
          // Si falla (ej. clave corrupta, formato incorrecto)
          print("Error al descifrar snippet para conv ${widget.conversation['id']}: $e");
          snippet = "[Mensaje no disponible]"; // Muestro un error
        }
      } else if (ciphertext != null) {
         // Si hay texto pero no clave (no debería pasar en mi lógica E2EE)
         snippet = "[Mensaje cifrado]";
      }
      
    }

    // --- 4. Actualizar el estado de este widget ---
    // (Solo si el widget todavía está en pantalla)
    if (mounted) {
      setState(() {
        _displayTitle = title;
        _snippet = snippet;
        _timestamp = timestamp;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationId = (widget.conversation['id'] as num).toInt();

    // Estilo para el snippet (negrita si no está leído)
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _isUnread ? Theme.of(context).primaryColor : Colors.grey[600],
          fontWeight: _isUnread ? FontWeight.bold : FontWeight.normal,
        );

    // Renderizo el ListTile final
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      // Avatar con la primera letra del título
      leading: CircleAvatar(
        backgroundColor: widget.getAvatarColor(conversationId),
        foregroundColor: Colors.white,
        child: Text(
          _displayTitle.isNotEmpty ? _displayTitle[0].toUpperCase() : 'C',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      // Título del chat
      title: Text(
        _displayTitle,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: _isUnread ? FontWeight.bold : FontWeight.w600,
              color: _isUnread ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.titleMedium?.color
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // Snippet (último mensaje descifrado)
      subtitle: Text(
        _snippet, 
        style: subtitleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // Hora del último mensaje
      trailing: Text(
        _timestamp, 
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _isUnread ? Theme.of(context).primaryColor : Colors.grey,
              fontWeight: _isUnread ? FontWeight.bold : FontWeight.normal,
            ),
      ),
      onTap: widget.onTap, // Acción de clic (definida en el padre)
    );
  }
}