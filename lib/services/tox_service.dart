import 'dart:async';
import 'dart:isolate';
import 'package:toxcore_ffi/toxcore_ffi.dart';

class ToxService {
  static final ToxService _instance = ToxService._internal();
  factory ToxService() => _instance;
  ToxService._internal();

  late ToxCore _tox;
  bool _isInitialized = false;
  StreamController<ToxEvent> _eventController = StreamController.broadcast();

  Stream<ToxEvent> get events => _eventController.stream;

  // O teu Tox ID real (hex)
  String? get ownAddress => _tox.ownAddress;

  Future<void> init() async {
    if (_isInitialized) return;
    _tox = ToxCore.create();
    _tox.start();
    _tox.events.listen((event) {
      _eventController.add(event);
      // Processar eventos como mensagens recebidas, pedidos de amizade, etc.
    });
    _isInitialized = true;
    // Bootstrap nodes (exemplos públicos da rede Tox)
    final nodes = [
      ('51.15.84.13', 33445, '728925473812C7AAC482BE7250BCCAD0B8CB9F737BF3D42ABD34459C1768F854'),
      ('85.172.30.117', 33445, '8E7D0B859922EF569298B4D261A8CCB5CEA9DCA0E7524F8F4B7D5E2F3C2B3E09'),
      // Adiciona mais nós se quiseres
    ];
    for (final node in nodes) {
      _tox.bootstrap(node.$1, node.$2, node.$3);
    }
  }

  // Enviar pedido de amizade
  Future<int> addFriend(String address, String message) async {
    return _tox.addFriend(address, message);
  }

  // Enviar mensagem
  Future<int> sendMessage(int friendNumber, String message) async {
    return _tox.sendMessage(friendNumber, message);
  }

  // Aceitar pedido de amizade
  void acceptFriendRequest(int friendNumber) {
    _tox.addFriendNorequest(friendNumber);
  }

  void dispose() {
    _tox.dispose();
    _eventController.close();
  }
}
