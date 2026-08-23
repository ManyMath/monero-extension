import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monero_extension/src/ffi/signal_sender.dart';
import 'package:monero_extension/src/ffi/signal_types.dart';
import 'package:monero_extension/utils/offline_signing_import_utils.dart';
import 'package:monero_extension/widgets/offline_signing_dialog.dart';

class RecordingSignalSender implements SignalSender {
  final sent = <({String name, Map<String, dynamic> data})>[];
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};

  @override
  void sendSignal(String signalName, Map<String, dynamic> data) {
    sent.add((name: signalName, data: data));
  }

  @override
  Stream<Map<String, dynamic>> onRawSignal(String typeName) =>
      _controller(typeName).stream;

  void emit(String typeName, Map<String, dynamic> data) {
    _controller(typeName).add(data);
  }

  StreamController<Map<String, dynamic>> _controller(String typeName) =>
      _controllers.putIfAbsent(
        typeName,
        () => StreamController<Map<String, dynamic>>.broadcast(),
      );

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}


/// Walk the confirmation step the dialog now interposes before signing.
///
/// The dialog no longer signs whatever it is handed: an unsigned transaction is authored
/// by the untrusted online wallet, so the user is shown every destination first. These
/// tests assert the signing request, which now lives on the far side of that screen.
Future<void> confirmDestinations(
  WidgetTester tester,
  RecordingSignalSender sender, {
  bool changeIsOurs = true,
}) async {
  expect(
    sender.sent.last.name,
    'send_preview_unsigned_transaction_request',
    reason: 'the dialog must ask what the transaction pays before signing it',
  );
  sender.emit('UnsignedTransactionPreviewedResponse', {
    'success': true,
    'error': null,
    'error_code': null,
    'error_hint': null,
    'error_transient': null,
    'destinations': [
      {
        'address': '4' + 'a' * 94,
        'amount': 800000000000,
        'is_change': false,
        'is_ours': false,
      },
      {
        'address': '4' + 'b' * 94,
        'amount': 199900000000,
        'is_change': true,
        'is_ours': changeIsOurs,
      },
    ],
  });
  await tester.pump();
  await tester.tap(find.text('Sign'));
  await tester.pump();
}

void main() {
  late RecordingSignalSender sender;

  setUp(() {
    sender = RecordingSignalSender();
    setSignalSender(sender);
  });

  tearDown(() async {
    await sender.dispose();
  });

  testWidgets('returns signer metadata after showing signed QR', (
    tester,
  ) async {
    TransactionSignedOfflineResponse? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await OfflineSigningDialog.show(
                context,
                isViewOnly: false,
                seed: 'cold seed words',
                network: 'mainnet',
                spendSecretKeyHex: '1' * 64,
                viewSecretKeyHex: '2' * 64,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abcdef');
    await tester.tap(find.text('From Text'));
    await tester.pump();

    await confirmDestinations(tester, sender);

    expect(sender.sent.last.name, 'send_sign_unsigned_transaction_request');
    expect(sender.sent.last.data['unsigned_tx_hex'], 'abcdef');
    expect(sender.sent.last.data['spend_secret_key_hex'], '1' * 64);
    expect(sender.sent.last.data['view_secret_key_hex'], '2' * 64);

    sender.emit('TransactionSignedOfflineResponse', {
      'success': true,
      'error': null,
      'error_code': null,
      'error_hint': null,
      'error_transient': null,
      'tx_id': 'a' * 64,
      'fee': 1234,
      'tx_blob': 'deadbeef',
      'tx_key': 'b' * 64,
      'tx_key_additional': ['c' * 64],
      'change_outputs': [],
      'spent_key_images': ['ki_1', 'ki_2'],
      'transactions': [],
    });
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.txId, 'a' * 64);
    expect(result!.txBlob, 'deadbeef');
    expect(result!.fee, 1234);
    expect(result!.txKey, 'b' * 64);
    expect(result!.txKeyAdditional, ['c' * 64]);
    expect(result!.spentKeyImages, ['ki_1', 'ki_2']);
  });

  testWidgets('passes wallet2 unsigned txsets through to the offline signer', (
    tester,
  ) async {
    TransactionSignedOfflineResponse? result;
    final unsignedTxSetHex = '${unsignedMoneroTxSetMagicHex}aabbccdd';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await OfflineSigningDialog.show(
                context,
                isViewOnly: false,
                seed: 'cold seed words',
                network: 'mainnet',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), unsignedTxSetHex);
    await tester.tap(find.text('From Text'));
    await tester.pump();

    await confirmDestinations(tester, sender);

    expect(sender.sent.last.name, 'send_sign_unsigned_transaction_request');
    expect(sender.sent.last.data['unsigned_tx_hex'], unsignedTxSetHex);
    expect(sender.sent.last.data['network'], 'mainnet');

    sender.emit('TransactionSignedOfflineResponse', {
      'success': true,
      'error': null,
      'error_code': null,
      'error_hint': null,
      'error_transient': null,
      'tx_id': 'd' * 64,
      'fee': 4321,
      'tx_blob': 'feedface',
      'signed_txset_hex': '${signedMoneroTxSetMagicHex}feedface',
      'tx_key': 'e' * 64,
      'tx_key_additional': ['f' * 64],
      'change_outputs': [],
      'spent_key_images': ['wallet2_ki_0', 'wallet2_ki_20'],
      'transactions': [],
    });
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.txId, 'd' * 64);
    expect(result!.txBlob, 'feedface');
    expect(result!.signedTxSetHex, '${signedMoneroTxSetMagicHex}feedface');
    expect(result!.fee, 4321);
    expect(result!.txKey, 'e' * 64);
    expect(result!.txKeyAdditional, ['f' * 64]);
    expect(result!.spentKeyImages, ['wallet2_ki_0', 'wallet2_ki_20']);
  });

  testWidgets('packages signed wallet2 txset when metadata is available', (
    tester,
  ) async {
    TransactionSignedOfflineResponse? result;
    final unsignedTxSetHex = '${unsignedMoneroTxSetMagicHex}aabbccdd';
    final builtTxSetHex = '${signedMoneroTxSetMagicHex}feedface';
    final keyImages = ['a' * 64, 'b' * 64];
    final txKeyImages = [
      SignedTxSetKeyImageEntry(publicKey: 'c' * 64, keyImage: 'd' * 64),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await OfflineSigningDialog.show(
                context,
                isViewOnly: false,
                seed: 'cold seed words',
                network: 'mainnet',
                viewKeyHex: 'e' * 64,
                wallet2KeyImages: keyImages,
                wallet2TxKeyImages: txKeyImages,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), unsignedTxSetHex);
    await tester.tap(find.text('From Text'));
    await tester.pump();

    await confirmDestinations(tester, sender);

    expect(sender.sent.last.name, 'send_sign_unsigned_transaction_request');
    expect(sender.sent.last.data['unsigned_tx_hex'], unsignedTxSetHex);

    sender.emit('TransactionSignedOfflineResponse', {
      'success': true,
      'error': null,
      'error_code': null,
      'error_hint': null,
      'error_transient': null,
      'tx_id': '1' * 64,
      'fee': 5555,
      'tx_blob': 'cafebabe',
      'signed_txset_hex': null,
      'tx_key': '2' * 64,
      'tx_key_additional': ['3' * 64],
      'change_outputs': [],
      'spent_key_images': ['d' * 64],
      'transactions': [],
    });
    await tester.pump();

    expect(find.text('Packaging Signed Transaction'), findsOneWidget);
    expect(sender.sent.last.name, 'send_build_signed_txset_request');
    expect(sender.sent.last.data['unsigned_txset_hex'], unsignedTxSetHex);
    expect(sender.sent.last.data['view_key_hex'], 'e' * 64);
    expect(sender.sent.last.data['tx_blob_hex'], 'cafebabe');
    expect(sender.sent.last.data['key_images'], keyImages);
    expect(sender.sent.last.data['tx_key_images'], [
      {'public_key': 'c' * 64, 'key_image': 'd' * 64},
    ]);

    sender.emit('SignedTxSetBuiltResponse', {
      'success': true,
      'error': null,
      'error_code': null,
      'error_hint': null,
      'error_transient': null,
      'signed_txset_hex': builtTxSetHex,
    });
    await tester.pump();

    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(result, isNotNull);
    expect(result!.txId, '1' * 64);
    expect(result!.txBlob, 'cafebabe');
    expect(result!.signedTxSetHex, builtTxSetHex);
    expect(result!.fee, 5555);
    expect(result!.txKey, '2' * 64);
    expect(result!.txKeyAdditional, ['3' * 64]);
    expect(result!.spentKeyImages, ['d' * 64]);
  });

  testWidgets('will not sign when the preview shows change going elsewhere', (
    tester,
  ) async {
    final unsignedTxSetHex = '${unsignedMoneroTxSetMagicHex}aabbccdd';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await OfflineSigningDialog.show(
                context,
                isViewOnly: false,
                seed: 'cold seed words',
                network: 'mainnet',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), unsignedTxSetHex);
    await tester.tap(find.text('From Text'));
    await tester.pump();

    expect(sender.sent.last.name, 'send_preview_unsigned_transaction_request');
    sender.emit('UnsignedTransactionPreviewedResponse', {
      'success': true,
      'error': null,
      'error_code': null,
      'error_hint': null,
      'error_transient': null,
      'destinations': [
        {
          'address': '4' + 'a' * 94,
          'amount': 800000000000,
          'is_change': false,
          'is_ours': false,
        },
        {
          // The attack: declared as change, payable only by someone else.
          'address': '4' + 'c' * 94,
          'amount': 199900000000,
          'is_change': true,
          'is_ours': false,
        },
      ],
    });
    await tester.pump();

    expect(
      find.textContaining('NOT YOUR ADDRESS'),
      findsOneWidget,
      reason: 'redirected change must be called out, not rendered as ordinary change',
    );

    // warnIfMissed: false because the button is *meant* to be disabled here - the tap
    // landing on nothing is the behaviour under test, not an accident of layout.
    await tester.tap(find.text('Sign'), warnIfMissed: false);
    await tester.pump();

    expect(
      sender.sent.any(
        (signal) => signal.name == 'send_sign_unsigned_transaction_request',
      ),
      isFalse,
      reason: 'the dialog must not sign a transaction whose change is redirected',
    );
  });

  testWidgets('carries the wallet passphrase into preview and signing', (
    tester,
  ) async {
    // A seed offset passphrase picks a different wallet out of the same mnemonic, so a
    // request that leaves it empty derives the wrong wallet: the preview disowns the
    // wallet's own change and the signer then rejects it. The dialog used to hard-code
    // '' at both call sites, which meant the field existed on the wire and nothing ever
    // filled it.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await OfflineSigningDialog.show(
                context,
                isViewOnly: false,
                seed: 'cold seed words',
                passphrase: 'hunter2',
                bip39AccountIndex: 3,
                network: 'mainnet',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abcdef');
    await tester.tap(find.text('From Text'));
    await tester.pump();

    final preview = sender.sent.last;
    expect(preview.name, 'send_preview_unsigned_transaction_request');
    expect(preview.data['passphrase'], 'hunter2');
    expect(preview.data['bip39_account_index'], 3);

    await confirmDestinations(tester, sender);

    final signing = sender.sent.last;
    expect(signing.name, 'send_sign_unsigned_transaction_request');
    expect(
      signing.data['passphrase'],
      'hunter2',
      reason: 'the signer must derive the same wallet the preview showed',
    );
    expect(signing.data['bip39_account_index'], 3);
  });
}
