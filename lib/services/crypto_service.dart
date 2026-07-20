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

    // Par de chaves X25519
    final savedPriv = prefs.getString('my_private_key');

    if (savedPriv != null) {
      final privBytes = base64Decode(savedPriv);
      // Usar o construtor correto da versão 2.9.0
      final algorithm = X25519();
      _myKeyPair = await algorithm.newKeyPairFromSeed(SecretKey(privBytes));
    } else {
      _myKeyPair = await X25519().newKeyPair();
      final privBytes = await _myKeyPair.extractPrivateKeyBytes();
      await prefs.setString('my_private_key', base64Encode(privBytes));
    }

    _myPublicKey = await _myKeyPair.extractPublicKey();

    // Chave local para encriptar a base de dados (AES-256)
    final savedLocalKey = prefs.getString('local_key');
    if (savedLocalKey != null) {
      _localKey = SecretKey(base64Decode(savedLocalKey));
    } else {
      _localKey = await AesGcm.with256bits().newSecretKey();
      await prefs.setString('local_key', base64Encode(await _localKey.extractBytes()));
    }

    _initialized = true;
  }

  String get publicKeyBase64 => base64Encode(_myPublicKey.bytes);

  void addFriendPublicKey(String friendId, String pubKeyBase64) {
    _friendPublicKeys[friendId] = SimplePublicKey(
      base64Decode(pubKeyBase64),
      type: KeyPairType.x25519,
    );
  }

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

  // Encriptação local (BD)
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
