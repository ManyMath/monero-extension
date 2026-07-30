import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_extension/services/wallet_lifecycle_manager.dart';
import 'package:monero_extension/services/wallet_persistence_service.dart';
import 'package:monero_extension/services/wallet_polling_service.dart';
import 'package:monero_extension/src/ffi/signal_hub.dart';
import 'package:monero_extension/src/ffi/signal_sender.dart';
import 'package:monero_extension/src/ffi/signal_types.dart';
import 'package:monero_extension/state/scan_state.dart';
import 'package:monero_extension/state/wallet_state.dart';

import '../services/test_backends.dart';

class _Sender implements SignalSender {
  final sent = <({String name, Map<String, dynamic> data})>[];
  final _signals = StreamController<Map<String, dynamic>>.broadcast();

  @override
  void sendSignal(String signalName, Map<String, dynamic> data) {
    sent.add((name: signalName, data: data));
  }

  @override
  Stream<Map<String, dynamic>> onRawSignal(String typeName) => _signals.stream;

  void dispose() => _signals.close();
}

WalletState _walletState(SignalHub hub) => WalletState(
  lifecycle: WalletLifecycleManager(
    persistence: WalletPersistenceService(
      storage: InMemoryStorageBackend(),
      crypto: IdentityCryptoBackend(),
    ),
  ),
  signalHub: hub,
);

OwnedOutput _output(String txHash, int height) => OwnedOutput(
  txHash: txHash,
  outputIndex: 0,
  amount: 1000,
  amountXmr: '0.000000001000',
  key: 'key_$txHash',
  keyOffset: 'offset_$txHash',
  commitmentMask: 'mask_$txHash',
  receivedOutputBytes: 'bytes_$txHash',
  blockHeight: height,
  spent: false,
  keyImage: 'ki_$txHash',
  isCoinbase: false,
  frozen: false,
);

BlockScanResponse _scanned(String txHash, int height) => BlockScanResponse(
  success: true,
  blockHeight: height,
  blockHash: 'bh_$height',
  blockTimestamp: 0,
  txCount: 1,
  outputs: [_output(txHash, height)],
  daemonHeight: height + 10,
  spentKeyImages: const [],
  spentKeyImageTxHashes: const [],
);

void main() {
  late _Sender sender;

  setUp(() {
    sender = _Sender();
    setSignalSender(sender);
  });

  tearDown(() => sender.dispose());

  // Switching or loading a wallet does not stop a running scan, and a BlockScanResponse
  // says nothing about which wallet it was scanned for. Its multi-wallet sibling routes
  // every result by the address it belongs to; this path credited whichever wallet
  // happened to be active when the batch came back.
  test('a block scanned for another wallet is not credited to the active one', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();
    expect(
      sender.sent.map((s) => s.name),
      contains('send_start_continuous_scan_request'),
      reason: 'premise: a single-wallet scan is running for wallet_a',
    );

    // The user opens another wallet while that scan is in flight.
    walletState.openWallet('wallet_b', 'seed b words', 'stagenet', 'addr_b');
    expect(walletState.activeWalletId, 'wallet_b');

    hub.onBlockScan!(_scanned('scanned_for_a', 500));

    expect(
      walletState.lifecycle.openWallets['wallet_b']!.outputs,
      isEmpty,
      reason: 'wallet B must not be credited with a block scanned for wallet A',
    );
    expect(
      walletState.lifecycle.openWallets['wallet_b']!.currentHeight,
      0,
      reason: 'wallet B must not record a height it never scanned to',
    );
  });

  // The negative control. A guard that dropped everything would leave every wallet empty
  // and still satisfy the test above.
  test('a block scanned for the active wallet is credited to it', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();

    hub.onBlockScan!(_scanned('scanned_for_a', 500));

    expect(
      walletState.lifecycle.openWallets['wallet_a']!.outputs
          .map((o) => o.txHash),
      ['scanned_for_a'],
    );
    expect(
      walletState.lifecycle.openWallets['wallet_a']!.currentHeight,
      500,
    );
  });

  // A scan of a seed typed into the field has no wallet id to bind to, and the wallet it
  // belongs to is opened once its address derives — after the scan starts. Requiring a
  // match would discard results the app has always kept.
  test('a scan started before any wallet was open still credits the wallet', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.seedController.text = List.filled(25, 'word').join(' ');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    hub.onBlockScan!(_scanned('scanned_before_open', 500));

    expect(
      walletState.lifecycle.openWallets['wallet_a']!.outputs
          .map((o) => o.txHash),
      ['scanned_before_open'],
    );
  });
}
