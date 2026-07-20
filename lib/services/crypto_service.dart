import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  late SimpleKeyPair _myKeyPair;
  late SimplePublicKey _myPublicKey;
  late SecretKey _localKey;
  bool _initialized = false;

  final Map<String, SimplePublicKey> _friendPublicKeys = {};

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    // 1. Par de chaves X25519 (guardamos a privada e a pública juntas)
    final savedKeyData = prefs.getString('my_key_pair');

    if (savedKeyData != null) {
      // Recuperar o par guardado
      final json = jsonDecode(savedKeyData);
      final privBytes = base64Decode(json['privateKey']);
      final pubBytes = base64Decode(json['publicKey']);

      _myPublicKey = SimplePublicKey(pubBytes, type: KeyPairType.x25519);
      final keyPairData = SimpleKeyPairData(
        bytes: privBytes,
        publicKey: _myPublicKey,
      );
      _myKeyPair = SimpleKeyPair(keyPairData, publicKey: _myPublicKey);
    } else {
      // Gerar um novo par e guardar
      _myKeyPair = await X25519().newKeyPair();
      _myPublicKey = await _myKeyPair.extractPublicKey();

      final privBytes = await _myKeyPair.extractPrivateKeyBytes();
      final pubBytes = _myPublicKey.bytes;

      final json = jsonEncode({
        'privateKey': base64Encode(privBytes),
        'publicKey': base64Encode(pubBytes),
      });
      await prefs.setString('my_key_pair', json);
    }

    // 2. Chave local para a base de dados (AES‑256)
    final savedLocalKey = prefs.getString('local_key');
    if (savedLocalKey != null) {
      _localKey = SecretKey(base64Decode(savedLocalKey));
    } else {
      _localKey = await AesGcm.with256bits().newSecretKey();
      await prefs.setString('local_key', base64Encode(await _localKey.extractBytes()));
    }

    _initialized = true;
  }

  /// Chave pública (base64) para partilhar com amigos.
  String get publicKeyBase64 => base64Encode(_myPublicKey.bytes);

  /// Adiciona a chave pública de um amigo (recebida por QR/link).
  void addFriendPublicKey(String friendId, String pubKeyBase64) {
    _friendPublicKeys[friendId] = SimplePublicKey(
      base64Decode(pubKeyBase64),
      type: KeyPairType.x25519,
    );
  }

  /// Encripta uma mensagem para um amigo específico.
  Future<String> encryptMessage(String friendId, String plainText) async {
    final recipientPublicKey = _friendPublicKeys[friendId];
    if (recipientPublicKey == null) throw Exception('Chave pública do amigo não encontrada');

    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: _myKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: sharedSecret,
    );

    final payload = {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Decifra uma mensagem recebida de um amigo.
  Future<String> decryptMessage(String friendId, String encryptedPayload) async {
    final recipientPublicKey = _friendPublicKeys[friendId];
    if (recipientPublicKey == null) throw Exception('Chave pública do amigo não encontrada');

    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: _myKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final payloadMap = jsonDecode(utf8.decode(base64Decode(encryptedPayload)));
    final secretBox = SecretBox(
      base64Decode(payloadMap['ciphertext']),
      nonce: base64Decode(payloadMap['nonce']),
      mac: Mac(base64Decode(payloadMap['mac'])),
    );

    final decrypted = await AesGcm.with256bits().decrypt(secretBox, secretKey: sharedSecret);
    return utf8.decode(decrypted);
  }

  // ------------------------------------------------------
  // Encriptação para a base de dados local
  // ------------------------------------------------------

  /// Encripta uma string para armazenamento local (usa _localKey).
  Future<String> encryptData(String plainText) async {
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: _localKey,
    );

    final payload = {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Decifra uma string que foi encriptada com [encryptData].
  Future<String> decryptData(String encryptedPayload) async {
    final payloadMap = jsonDecode(utf8.decode(base64Decode(encryptedPayload)));
    final secretBox = SecretBox(
      base64Decode(payloadMap['ciphertext']),
      nonce: base64Decode(payloadMap['nonce']),
      mac: Mac(base64Decode(payloadMap['mac'])),
    );

    final decrypted = await AesGcm.with256bits().decrypt(secretBox, secretKey: _localKey);
    return utf8.decode(decrypted);
  }
}
