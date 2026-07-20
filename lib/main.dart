import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'services/crypto_service.dart';
import 'services/storage_service.dart';
import 'services/tox_service.dart';

// ------------------------------------------------------
// MODELOS (mantêm‑se os mesmos)
// ------------------------------------------------------
class Contact {
  final String id;        // Tox ID (76 caracteres hex)
  String name;
  int friendNumber;       // Número interno do Tox
  List<Message> messages;

  Contact({
    required this.id,
    required this.name,
    this.friendNumber = -1,
    List<Message>? messages,
  }) : messages = messages ?? [];

  String get lastMessage {
    if (messages.isEmpty) return '';
    return messages.last.text;
  }

  String get lastTime {
    if (messages.isEmpty) return '';
    return messages.last.time;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'friendNumber': friendNumber,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'],
        name: json['name'],
        friendNumber: json['friendNumber'] ?? -1,
        messages: (json['messages'] as List)
            .map((m) => Message.fromJson(m))
            .toList(),
      );
}

class Message {
  final String text;
  final bool isMe;
  final String time;

  Message({required this.text, required this.isMe, required this.time});

  Map<String, dynamic> toJson() => {
        'text': text,
        'isMe': isMe,
        'time': time,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        text: json['text'],
        isMe: json['isMe'],
        time: json['time'],
      );
}

// ------------------------------------------------------
// APP PRINCIPAL
// ------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializa os serviços
  await CryptoService().init();
  try {
    await ToxService().init();
  } catch (e) {
    print('Tox ainda não inicializado: $e');
  }
  runApp(const P2PChatApp());
}

class P2PChatApp extends StatelessWidget {
  const P2PChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const ContactsScreen(),
    );
  }
}

// ------------------------------------------------------
// ECRÃ DE DEFINIÇÕES
// ------------------------------------------------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Definições'),
      ),
      body: ListView(
        children: const [
          ListTile(title: Text('🔒 Privacidade'), trailing: Icon(Icons.chevron_right)),
          ListTile(title: Text('🔔 Notificações'), trailing: Icon(Icons.chevron_right)),
          ListTile(title: Text('💾 Armazenamento'), trailing: Icon(Icons.chevron_right)),
          ListTile(title: Text('ℹ️ Sobre'), trailing: Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------
// LISTA DE CONVERSAS
// ------------------------------------------------------
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> contacts = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
    // Ouvir eventos do Tox (mensagens recebidas)
    ToxService().events.listen((event) {
      if (event is ToxMessageEvent) {
        // Atualiza o contacto correspondente
        setState(() {
          // ... lógica para adicionar a mensagem recebida
        });
      }
    });
  }

  Future<void> _loadContacts() async {
    final loaded = await StorageService.loadContacts();
    setState(() => contacts = loaded);
  }

  List<Contact> get filteredContacts =>
      contacts.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

  void _addNewContact(String address) {
    if (address.length != 76) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tox ID inválido.')),
      );
      return;
    }
    if (contacts.any((c) => c.id == address)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este contacto já existe.')),
      );
      return;
    }
    final tox = ToxService();
    final friendNum = tox.addFriend(address, 'Olá, adiciona-me!');
    final name = 'Amigo ${contacts.length + 1}';
    final newContact = Contact(id: address, name: name, friendNumber: friendNum);
    setState(() => contacts.add(newContact));
    StorageService.saveContacts(contacts);
  }

  void _updateContact(Contact updated) {
    setState(() {
      final index = contacts.indexWhere((c) => c.id == updated.id);
      if (index != -1) contacts[index] = updated;
    });
    StorageService.saveContacts(contacts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversas'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'myid':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const IdScreen()));
                  break;
                case 'scan':
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  );
                  if (result is String && result.length == 76) {
                    _addNewContact(result);
                  }
                  break;
                case 'manual':
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ManualAddScreen()),
                  );
                  if (result is String && result.length == 76) {
                    _addNewContact(result);
                  }
                  break;
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  break;
                case 'connection':
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Tox ID: ${ToxService().ownAddress ?? "..."}')),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'myid', child: Text('🔑 O meu Tox ID')),
              const PopupMenuItem(value: 'scan', child: Text('📷 Escanear QR')),
              const PopupMenuItem(value: 'manual', child: Text('✍️ Adicionar manualmente')),
              const PopupMenuItem(value: 'settings', child: Text('⚙️ Definições')),
              const PopupMenuItem(value: 'connection', child: Text('🌐 Conexão')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Pesquisar...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum contacto.\nAdiciona amigos pelo menu ⋮',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredContacts.length,
                    itemBuilder: (context, index) {
                      final contact = filteredContacts[index];
                      return _ContactTile(
                        contact: contact,
                        onTap: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(contact: contact),
                            ),
                          );
                          if (updated != null && updated is Contact) {
                            _updateContact(updated);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;

  const _ContactTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF6C63FF).withOpacity(0.25),
        child: Text(
          contact.name[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        contact.name,
        style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
      ),
      subtitle: contact.lastMessage.isNotEmpty
          ? Text(
              contact.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white54),
            )
          : null,
      trailing: contact.lastTime.isNotEmpty
          ? Text(contact.lastTime, style: const TextStyle(fontSize: 11, color: Colors.white38))
          : null,
    );
  }
}

// ------------------------------------------------------
// ECRÃ DE CHAT
// ------------------------------------------------------
class ChatScreen extends StatefulWidget {
  final Contact contact;
  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late List<Message> messages;
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    messages = List.from(widget.contact.messages);
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final timeStr = _formatTime(now);

    // Enviar via Tox
    if (widget.contact.friendNumber >= 0) {
      ToxService().sendMessage(widget.contact.friendNumber, text);
    }

    final msg = Message(text: text, isMe: true, time: timeStr);
    setState(() {
      messages.add(msg);
    });
    widget.contact.messages = List.from(messages);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            Navigator.pop(context, widget.contact);
          },
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF6C63FF).withOpacity(0.25),
              child: Text(
                widget.contact.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            Text(widget.contact.name, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isMe = msg.isMe;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF6C63FF) : const Color(0xFF2A2A3E),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(18),
                          ),
                        ),
                        child: Text(
                          msg.text,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(msg.time, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Mensagem...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6C63FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------
// ECRÃ DO MEU TOX ID
// ------------------------------------------------------
class IdScreen extends StatelessWidget {
  const IdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final toxService = ToxService();
    final myToxId = toxService.ownAddress ?? 'A aguardar ligação...';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('O meu Tox ID'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (myToxId.length == 76)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF6C63FF), width: 2),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: myToxId,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: Color(0xFF6C63FF),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black87,
                    ),
                  ),
                )
              else
                const CircularProgressIndicator(color: Color(0xFF6C63FF)),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: SelectableText(
                  myToxId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copiar',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ID copiado!')),
                      );
                    },
                  ),
                  _ActionButton(
                    icon: Icons.qr_code_scanner,
                    label: 'Escanear',
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                      );
                      if (result is String && result.length == 76 && context.mounted) {
                        Navigator.pop(context, result);
                      }
                    },
                  ),
                  _ActionButton(
                    icon: Icons.person_add_alt,
                    label: 'Adicionar',
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ManualAddScreen()),
                      );
                      if (result is String && result.length == 76 && context.mounted) {
                        Navigator.pop(context, result);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF6C63FF)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------
// SCANNER
// ------------------------------------------------------
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final MobileScannerController controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      final code = barcode!.rawValue!;
      if (code.length == 76) {
        setState(() => _scanned = true);
        Navigator.pop(context, code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Escanear QR'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF6C63FF), width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Text(
              'Aponta a câmara para o código QR do teu amigo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------
// ADICIONAR MANUALMENTE
// ------------------------------------------------------
class ManualAddScreen extends StatefulWidget {
  const ManualAddScreen({super.key});

  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> {
  final TextEditingController _idController = TextEditingController();

  void _submit() {
    final id = _idController.text.trim();
    if (id.length != 76) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tox ID inválido. Deve ter 76 caracteres.')),
      );
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Adicionar amigo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add_alt, size: 64, color: Color(0xFF6C63FF)),
            const SizedBox(height: 24),
            TextField(
              controller: _idController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Cola o Tox ID aqui...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('Adicionar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
