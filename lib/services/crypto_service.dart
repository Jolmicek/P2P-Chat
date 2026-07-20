import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  late final SimpleKeyPair _myKeyPair;
  late final SimplePublicKey _myPublicKey;
  bool _initialized = false;

  // Mapa de friendNumber (ou ID) -> SimplePublicKey
  final Map<String, SimplePublicKey> _friendPublicKeys = {};

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final savedPriv = prefs.getString('my_private_key');
    final algorithm = X25519();

    if (savedPriv != null) {
      final privKey = SimpleKeyPairData(
        Uint8List.fromList(base64Decode(savedPriv)),
        type: KeyPairType.x25519,
      );
      _myKeyPair = SimpleKeyPair(privKey, publicKey: await algorithm.extractPublicKey(privKey));
    } else {
      _myKeyPair = await algorithm.newKeyPair();
      await prefs.setString('my_private_key', base64Encode(await _myKeyPair.extractPrivateKeyBytes()));
    }
    _myPublicKey = await _myKeyPair.extractPublicKey();
    _initialized = true;
  }

  /// Retorna a chave pública em base64 (para partilhar via QR/link)
  String get publicKeyBase64 => base64Encode(_myPublicKey.bytes);

  /// Adiciona a chave pública de um amigo (recebida por QR ou manualmente)
  void addFriendPublicKey(String friendId, String pubKeyBase64) {
    _friendPublicKeys[friendId] = SimplePublicKey(
      Uint8List.fromList(base64Decode(pubKeyBase64)),
      type: KeyPairType.x25519,
    );
  }

  /// Cifra uma mensagem para um amigo específico
  Future<String> encryptMessage(String friendId, String plainText) async {
    final recipientPublicKey = _friendPublicKeys[friendId];
    if (recipientPublicKey == null) throw Exception('Chave pública do amigo não encontrada');

    final algorithm = X25519();
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: _myKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final cipher = AesGcm.with256bits();
    final secretBox = await cipher.encrypt(
      utf8.encode(plainText),
      secretKey: sharedSecret,
    );

    // Retorna o ciphertext + nonce + mac em base64
    final payload = {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  /// Decifra uma mensagem recebida de um amigo
  Future<String> decryptMessage(String friendId, String encryptedPayload) async {
    final recipientPublicKey = _friendPublicKeys[friendId];
    if (recipientPublicKey == null) throw Exception('Chave pública do amigo não encontrada');

    final algorithm = X25519();
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: _myKeyPair,
      remotePublicKey: recipientPublicKey,
    );

    final payloadMap = jsonDecode(utf8.decode(base64Decode(encryptedPayload)));
    final secretBox = SecretBox(
      base64Decode(payloadMap['ciphertext']),
      nonce: base64Decode(payloadMap['nonce']),
      mac: Mac(base64Decode(payloadMap['mac'])),
    );

    final cipher = AesGcm.with256bits();
    final decrypted = await cipher.decrypt(secretBox, secretKey: sharedSecret);
    return utf8.decode(decrypted);
  }
}
