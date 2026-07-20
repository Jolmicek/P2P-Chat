import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../main.dart'; // Ajusta o import se os modelos Contact/Message estiverem noutro ficheiro
import 'crypto_service.dart';

class StorageService {
  static Database? _db;

  static Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'p2pchat.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE contacts(id TEXT PRIMARY KEY, data TEXT)');
      },
    );
    return _db!;
  }

  /// Carrega todos os contactos, decifrando os dados guardados.
  static Future<List<Contact>> loadContacts() async {
    final db = await _getDb();
    final rows = await db.query('contacts');
    final crypto = CryptoService();
    final contacts = <Contact>[];

    for (final row in rows) {
      try {
        final decrypted = await crypto.decryptData(row['data'] as String);
        final json = jsonDecode(decrypted);
        contacts.add(Contact.fromJson(json));
      } catch (_) {
        // Se a decifragem falhar (dados corrompidos, chave antiga, etc.), ignora a entrada.
      }
    }
    return contacts;
  }

  /// Guarda a lista de contactos, cifrando os dados de cada um.
  static Future<void> saveContacts(List<Contact> contacts) async {
    final db = await _getDb();
    final crypto = CryptoService();

    await db.transaction((txn) async {
      await txn.delete('contacts'); // Remove todos os registos antigos

      for (final c in contacts) {
        final json = jsonEncode(c.toJson());
        final encrypted = await crypto.encryptData(json);
        await txn.insert('contacts', {
          'id': c.id,
          'data': encrypted,
        });
      }
    });
  }
}
