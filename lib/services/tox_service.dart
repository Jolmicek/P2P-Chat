import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Tipos nativos
typedef ToxNewNative = Pointer<Void> Function(Pointer<Void> options);
typedef ToxNewDart = Pointer<Void> Function(Pointer<Void> options);

typedef ToxKillNative = Void Function(Pointer<Void> tox);
typedef ToxKillDart = void Function(Pointer<Void> tox);

typedef ToxBootstrapNative = Void Function(Pointer<Void> tox, Pointer<Utf8> address, Uint16 port, Pointer<Utf8> publicKey);
typedef ToxBootstrapDart = void Function(Pointer<Void> tox, Pointer<Utf8> address, int port, Pointer<Utf8> publicKey);

typedef ToxSelfGetAddressNative = Void Function(Pointer<Void> tox, Pointer<Uint8> address);
typedef ToxSelfGetAddressDart = void Function(Pointer<Void> tox, Pointer<Uint8> address);

typedef ToxFriendAddNative = Uint32 Function(Pointer<Void> tox, Pointer<Uint8> address, Pointer<Utf8> message, Uint32 length);
typedef ToxFriendAddDart = int Function(Pointer<Void> tox, Pointer<Uint8> address, Pointer<Utf8> message, int length);

typedef ToxFriendSendMessageNative = Uint32 Function(Pointer<Void> tox, Uint32 friendNumber, Uint32 type, Pointer<Utf8> message, Uint32 length);
typedef ToxFriendSendMessageDart = int Function(Pointer<Void> tox, int friendNumber, int type, Pointer<Utf8> message, int length);

typedef ToxIterateNative = Void Function(Pointer<Void> tox, Pointer<Void> userData);
typedef ToxIterateDart = void Function(Pointer<Void> tox, Pointer<Void> userData);

typedef ToxCallbackFriendMessageNative = Void Function(Pointer<Void> tox, Pointer<NativeFunction<FriendMessageCallbackNative>> callback, Pointer<Void> userData);
typedef ToxCallbackFriendMessageDart = void Function(Pointer<Void> tox, Pointer<NativeFunction<FriendMessageCallbackNative>> callback, Pointer<Void> userData);

typedef FriendMessageCallbackNative = Void Function(Pointer<Void> tox, Uint32 friendNumber, Uint32 type, Pointer<Utf8> message, Uint32 length, Pointer<Void> userData);

class ToxService {
  static final ToxService _instance = ToxService._internal();
  factory ToxService() => _instance;
  ToxService._internal();

  late DynamicLibrary _lib;
  late Pointer<Void> _tox;
  bool _initialized = false;

  final StreamController<ToxEvent> _eventController = StreamController<ToxEvent>.broadcast();
  Stream<ToxEvent> get events => _eventController.stream;

  String? _ownAddress;
  String? get ownAddress => _ownAddress;

  Future<void> init() async {
    if (_initialized) return;

    _lib = Platform.isAndroid
        ? DynamicLibrary.open('libtoxcore.so')
        : DynamicLibrary.process();

    final toxNew = _lib.lookupFunction<ToxNewNative, ToxNewDart>('tox_new');
    final toxKill = _lib.lookupFunction<ToxKillNative, ToxKillDart>('tox_kill');
    final toxBootstrap = _lib.lookupFunction<ToxBootstrapNative, ToxBootstrapDart>('tox_bootstrap');
    final toxSelfGetAddress = _lib.lookupFunction<ToxSelfGetAddressNative, ToxSelfGetAddressDart>('tox_self_get_address');
    final toxFriendAdd = _lib.lookupFunction<ToxFriendAddNative, ToxFriendAddDart>('tox_friend_add');
    final toxFriendSendMessage = _lib.lookupFunction<ToxFriendSendMessageNative, ToxFriendSendMessageDart>('tox_friend_send_message');
    final toxIterate = _lib.lookupFunction<ToxIterateNative, ToxIterateDart>('tox_iterate');
    final toxCallbackFriendMessage = _lib.lookupFunction<ToxCallbackFriendMessageNative, ToxCallbackFriendMessageDart>('tox_callback_friend_message');

    _tox = toxNew(nullptr);
    if (_tox == nullptr) throw Exception('Falha ao criar Tox');

    final messageCallback = Pointer.fromFunction<FriendMessageCallbackNative>(_onMessageReceived);
    toxCallbackFriendMessage(_tox, messageCallback, nullptr);

    // Bootstrap nodes
    final bootstrapNodes = [
      ('51.15.84.13', 33445, '728925473812C7AAC482BE7250BCCAD0B8CB9F737BF3D42ABD34459C1768F854'),
      ('85.172.30.117', 33445, '8E7D0B859922EF569298B4D261A8CCB5CEA9DCA0E7524F8F4B7D5E2F3C2B3E09'),
    ];
    for (final node in bootstrapNodes) {
      final addr = node.$1.toNativeUtf8();
      final key = node.$3.toNativeUtf8();
      toxBootstrap(_tox, addr, node.$2, key);
      calloc.free(addr);
      calloc.free(key);
    }

    final addrBuf = calloc<Uint8>(38);
    toxSelfGetAddress(_tox, addrBuf);
    final addrBytes = addrBuf.asTypedList(38);
    _ownAddress = addrBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    calloc.free(addrBuf);

    Isolate.spawn(_toxIterateLoop, _tox.address);

    _initialized = true;
  }

  static void _onMessageReceived(Pointer<Void> tox, int friendNumber, int type, Pointer<Utf8> message, int length, Pointer<Void> userData) {
    final msg = message.toDartString(length: length);
    ToxService()._eventController.add(ToxMessageEvent(friendNumber, msg));
  }

  static void _toxIterateLoop(int toxAddress) {
    final lib = DynamicLibrary.open('libtoxcore.so');
    final toxIterate = lib.lookupFunction<ToxIterateNative, ToxIterateDart>('tox_iterate');
    final tox = Pointer<Void>.fromAddress(toxAddress);
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      toxIterate(tox, nullptr);
    });
  }

  int addFriend(String address, String message) {
    final addr = address.hexToBytes();
    final addrPtr = calloc<Uint8>(38);
    addrPtr.asTypedList(38).setAll(0, addr);
    final msgPtr = message.toNativeUtf8();
    final friendNum = _lib.lookupFunction<ToxFriendAddNative, ToxFriendAddDart>('tox_friend_add')(_tox, addrPtr, msgPtr, message.length);
    calloc.free(addrPtr);
    calloc.free(msgPtr);
    return friendNum;
  }

  int sendMessage(int friendNumber, String text) {
    final msgPtr = text.toNativeUtf8();
    final result = _lib.lookupFunction<ToxFriendSendMessageNative, ToxFriendSendMessageDart>('tox_friend_send_message')(_tox, friendNumber, 0, msgPtr, text.length);
    calloc.free(msgPtr);
    return result;
  }

  void dispose() {
    _lib.lookupFunction<ToxKillNative, ToxKillDart>('tox_kill')(_tox);
    _eventController.close();
  }
}

abstract class ToxEvent {}
class ToxMessageEvent extends ToxEvent {
  final int friendNumber;
  final String message;
  ToxMessageEvent(this.friendNumber, this.message);
}

extension StringToBytes on String {
  Uint8List hexToBytes() {
    final result = Uint8List(length ~/ 2);
    for (int i = 0; i < length; i += 2) {
      result[i ~/ 2] = int.parse(substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
