import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_extension/services/rust_crypto_backend.dart';
import 'package:monero_extension/src/ffi/signal_sender.dart';

/// A sender with a stream per signal type, so a response can be delivered to exactly the
/// listeners of one type — which is what the real bridge does.
class _Sender implements SignalSender {
  final sent = <({String name, Map<String, dynamic> data})>[];
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};

  @override
  void sendSignal(String signalName, Map<String, dynamic> data) {
    sent.add((name: signalName, data: data));
  }

  @override
  Stream<Map<String, dynamic>> onRawSignal(String typeName) => _controllers
      .putIfAbsent(
        typeName,
        () => StreamController<Map<String, dynamic>>.broadcast(),
      )
      .stream;

  void emit(String typeName, Map<String, dynamic> data) {
    _controllers[typeName]?.add(data);
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
  }
}

Map<String, dynamic> _saved(String requestId, String ciphertext) => {
  'request_id': requestId,
  'success': true,
  'encrypted_data': ciphertext,
};

Map<String, dynamic> _loaded(String requestId, String plaintext) => {
  'request_id': requestId,
  'success': true,
  'wallet_data_json': plaintext,
};

void main() {
  late _Sender sender;

  setUp(() {
    sender = _Sender();
    setSignalSender(sender);
  });

  tearDown(() => sender.dispose());

  // `SaveWalletDataRequest` and `SaveWithDerivedKeyRequest` are answered by the *same*
  // response type, and every request used to complete on the first one off the broadcast
  // stream. The manual save and the auto-save are exactly this pair — and the manual save
  // never checked `_isAutoSaving`, so it could start while an auto-save was in flight.
  // Each ciphertext is then written under its own caller's wallet id.
  test('two saves in flight each get their own ciphertext', () async {
    final backend = RustCryptoBackend();

    final manual = backend.encrypt('password', 'wallet A json');
    final auto = backend.encryptWithKey('ab' * 32, 'cd' * 16, 'wallet B json');
    await pumpEventQueue();

    expect(sender.sent.length, 2, reason: 'premise: both requests went out');
    final manualId = sender.sent[0].data['request_id'] as String;
    final autoId = sender.sent[1].data['request_id'] as String;
    expect(
      manualId,
      isNot(autoId),
      reason: 'premise: the two requests are distinguishable',
    );

    // The second request is answered first — a normal outcome, since the two take
    // different amounts of work (one runs the KDF, the other does not).
    sender.emit('WalletDataSavedResponse', _saved(autoId, 'cipher_for_auto'));
    sender.emit('WalletDataSavedResponse', _saved(manualId, 'cipher_for_manual'));

    expect(await manual, 'cipher_for_manual');
    expect(await auto, 'cipher_for_auto');
  });

  // The other way the same hole opens, and the one that does not need two live callers:
  // a request that timed out is abandoned, but its response still arrives. Without an id
  // to reject it, the *next* request takes it — and stores the previous wallet's
  // ciphertext under the current wallet's id.
  test('a response for an abandoned request does not satisfy the next one', () async {
    final backend = RustCryptoBackend();

    final first = backend.encrypt('password', 'wallet A json');
    await pumpEventQueue();
    final abandonedId = sender.sent[0].data['request_id'] as String;

    // The late response for the abandoned request lands while the next one is waiting.
    final second = backend.encrypt('password', 'wallet B json');
    await pumpEventQueue();
    final secondId = sender.sent[1].data['request_id'] as String;

    sender.emit(
      'WalletDataSavedResponse',
      _saved(abandonedId, 'cipher_for_abandoned'),
    );
    sender.emit('WalletDataSavedResponse', _saved(secondId, 'cipher_for_second'));

    expect(
      await second,
      'cipher_for_second',
      reason: 'the abandoned request\'s ciphertext was stored under the next wallet id',
    );
    expect(await first, 'cipher_for_abandoned');
  });

  test('two loads in flight each get their own plaintext', () async {
    final backend = RustCryptoBackend();

    final a = backend.decrypt('password', 'ciphertext A');
    final b = backend.decrypt('password', 'ciphertext B');
    await pumpEventQueue();

    final idA = sender.sent[0].data['request_id'] as String;
    final idB = sender.sent[1].data['request_id'] as String;

    sender.emit('WalletDataLoadedResponse', _loaded(idB, 'wallet B json'));
    sender.emit('WalletDataLoadedResponse', _loaded(idA, 'wallet A json'));

    expect(await a, 'wallet A json');
    expect(await b, 'wallet B json');
  });

  // The negative control. Filtering on an id that never matches would make every save
  // and load hang until its 10s timeout and then report failure — the whole of
  // persistence broken, silently, and the tests above would still pass.
  test('a matching response completes the request it belongs to', () async {
    final backend = RustCryptoBackend();

    final only = backend.encrypt('password', 'wallet json');
    await pumpEventQueue();
    final id = sender.sent.single.data['request_id'] as String;

    sender.emit('WalletDataSavedResponse', _saved(id, 'the ciphertext'));

    expect(await only, 'the ciphertext');
  });

  test('a failed response completes the request it belongs to with null', () async {
    final backend = RustCryptoBackend();

    final only = backend.deriveKey('password');
    await pumpEventQueue();
    final id = sender.sent.single.data['request_id'] as String;

    sender.emit('EncryptionKeyDerivedResponse', {
      'request_id': id,
      'success': false,
      'error': 'Key derivation failed',
    });

    expect(await only, isNull);
  });
}
