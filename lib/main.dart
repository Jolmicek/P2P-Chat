import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'services/crypto_service.dart';

// ------------------------------------------------------
// MODELOS
// ------------------------------------------------------
class Contact {
  final String id;        // Chave pública base64 do amigo
  String name;
  List<Message> messages;

  Contact({
    required this.id,
    required this.name,
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
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'],
        name: json['name'],
        messages: (json['messages'] as List)
            .map((m) => Message.fromJson(m))
            .toList(),
      );
}

class Message {
  final String text;    // Cifrado ou plain?
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
// ARMAZENAMENTO LOCAL CIFRADO (SQLCipher)
// ------------------------------------------------------
class StorageService {
  static const _dbPassword = 'app-master-key'; // Derivar de password do utilizador no futuro
  static Database? _db;

  static Future<Database> _getDb() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      'p2pchat.db',
      password: _dbPassword,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE contacts(id TEXT PRIMARY KEY, name TEXT, messages TEXT)');
      },
    );
    return _db!;
  }

  static Future<List<Contact>> loadContacts() async {
    final db = await _getDb();
    final rows = await db.query('contacts');
    return rows.map((row) => Contact(
      id: row['id'] as String,
      name: row['name'] as String,
      messages: row['messages'] != null
          ? (jsonDecode(row['messages'] as String) as List).map((m) => Message.fromJson(m)).toList()
          : [],
    )).toList();
  }

  static Future<void> saveContacts(List<Contact> contacts) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      await txn.delete('contacts');
      for (final c in contacts) {
        await txn.insert('contacts', {
          'id': c.id,
          'name': c.name,
          'messages': jsonEncode(c.messages.map((m) => m.toJson()).toList()),
        });
      }
    });
  }
}

// ------------------------------------------------------
// APP PRINCIPAL
// ------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CryptoService().init();
  runApp(const P2PChatApp());
}

class P2PChatApp extends StatelessWidget {
  const P2PChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat P2P Seguro',
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
  }

  Future<void> _loadContacts() async {
    final loaded = await StorageService.loadContacts();
    setState(() => contacts = loaded);
  }

  List<Contact> get filteredContacts =>
      contacts.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

  void _addNewContact(String pubKeyBase64) {
    // pubKeyBase64 é a chave pública do amigo (≈44 caracteres base64)
    if (pubKeyBase64.length < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chave pública inválida.')),
      );
      return;
    }
    if (contacts.any((c) => c.id == pubKeyBase64)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este contacto já existe.')),
      );
      return;
    }
    // Regista a chave pública do amigo no serviço de criptografia
    CryptoService().addFriendPublicKey(pubKeyBase64, pubKeyBase64);
    final name = 'Amigo ${contacts.length + 1}';
    final newContact = Contact(id: pubKeyBase64, name: name);
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
                  if (result is String && result.length > 30) {
                    _addNewContact(result);
                  }
                  break;
                case 'manual':
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ManualAddScreen()),
                  );
                  if (result is String && result.length > 30) {
                    _addNewContact(result);
                  }
                  break;
                case 'settings':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  break;
                case 'connection':
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Chave pública: ${CryptoService().publicKeyBase64.substring(0, 12)}...')),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'myid', child: Text('🔑 O meu ID (chave pública)')),
              const PopupMenuItem(value: 'scan', child: Text('📷 Escanear QR')),
              const PopupMenuItem(value: 'manual', child: Text('✍️ Adicionar manualmente')),
              const PopupMenuItem(value: 'settings', child: Text('⚙️ Definições')),
              const PopupMenuItem(value: 'connection', child: Text('🌐 Minha chave')),
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

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Encriptar para o amigo
    final crypto = CryptoService();
    String displayText;
    try {
      final encrypted = await crypto.encryptMessage(widget.contact.id, text);
      displayText = encrypted; // Armazenamos a versão cifrada
    } catch (e) {
      // Se a chave não estiver definida, mostramos erro
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao encriptar: $e')),
      );
      return;
    }

    final now = DateTime.now();
    final timeStr = _formatTime(now);

    final msg = Message(text: displayText, isMe: true, time: timeStr);
    setState(() {
      messages.add(msg);
    });
    widget.contact.messages = List.from(messages);
    _messageController.clear();

    // Guarda localmente
    StorageService.saveContacts([widget.contact]); // Simplificado, o ideal é salvar todos
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
                // Tenta decifrar para mostrar, se possível
                return FutureBuilder<String>(
                  future: _decryptIfNeeded(msg),
                  builder: (context, snapshot) {
                    final displayText = snapshot.data ?? msg.text; // fallback cifrado
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
                              displayText,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(msg.time, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    );
                  },
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

  Future<String> _decryptIfNeeded(Message msg) async {
    if (msg.isMe) {
      try {
        return await CryptoService().decryptMessage(widget.contact.id, msg.text);
      } catch (_) {
        return msg.text; // se falhar, mostra cifrado
      }
    }
    return msg.text; // mensagens recebidas ainda não implementamos receção, mas seria igual
  }
}

// ------------------------------------------------------
// ECRÃ DO MEU ID (CHAVE PÚBLICA)
// ------------------------------------------------------
class IdScreen extends StatelessWidget {
  const IdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myPubKey = CryptoService().publicKeyBase64;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('A minha chave pública'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                  data: myPubKey,
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
              ),
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
                  myPubKey,
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
                        const SnackBar(content: Text('Chave copiada!')),
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
                      if (result is String && result.length > 30 && context.mounted) {
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
                      if (result is String && result.length > 30 && context.mounted) {
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
      // Aceitamos qualquer string com mais de 30 caracteres (base64 da chave pública)
      if (code.length > 30) {
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
        title: const Text('Escanear chave pública'),
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
    if (id.length < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chave pública inválida. Deve ter mais de 30 caracteres.')),
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
                hintText: 'Cola a chave pública aqui...',
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
