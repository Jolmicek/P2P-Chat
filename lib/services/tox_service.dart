import 'dart:async';
import 'package:toxcore_ffi/toxcore_ffi.dart' as tox;

class ToxService {
  static final ToxService _instance = ToxService._internal();
  factory ToxService() => _instance;
  ToxService._internal();

  late tox.ToxCore _core;
  bool _started = false;

  final StreamController<ToxEvent> _eventController =
      StreamController<ToxEvent>.broadcast();
  Stream<ToxEvent> get events => _eventController.stream;

  String? get ownAddress => _core.ownAddressHex;

  Future<void> init() async {
    if (_started) return;
    _core = tox.ToxCore.create();
    _core.start();
    _core.eventStream.listen((event) {
      _eventController.add(event);
    });
    // Bootstrap nodes públicos (exemplos)
    final nodes = [
      ('51.15.84.13', 33445, '728925473812C7AAC482BE7250BCCAD0B8CB9F737BF3D42ABD34459C1768F854'),
      ('85.172.30.117', 33445, '8E7D0B859922EF569298B4D261A8CCB5CEA9DCA0E7524F8F4B7D5E2F3C2B3E09'),
    ];
    for (final n in nodes) {
      _core.bootstrap(n.$1, n.$2, n.$3);
    }
    _started = true;
  }

  int addFriend(String address, String message) {
    return _core.addFriend(address, message);
  }

  int sendMessage(int friendNumber, String message) {
    return _core.sendMessage(friendNumber, message);
  }

  void acceptFriend(int friendNumber) {
    _core.addFriendNorequest(friendNumber);
  }

  void dispose() {
    _core.dispose();
    _eventController.close();
  }
}

// Alias para os eventos do pacote
typedef ToxEvent = tox.ToxEvent;
