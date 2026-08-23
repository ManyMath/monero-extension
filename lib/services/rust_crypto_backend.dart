import 'dart:async';
import '../src/ffi/signal_types.dart';
import 'crypto_backend.dart';

class RustCryptoBackend implements CryptoBackend {
  /// Correlates a response with the request that asked for it.
  ///
  /// Every one of these calls used to complete on the first response of its type off a
  /// broadcast stream. `SaveWalletDataRequest` and `SaveWithDerivedKeyRequest` are
  /// answered by the same type, so a manual save and an auto-save satisfied each other's
  /// completer - and a response arriving after the 10s timeout satisfied the *next*
  /// request instead, whose caller then wrote that ciphertext under its own wallet id.
  /// The counter is process-wide because the completers are.
  static int _nextRequestId = 0;
  static String _newRequestId() => 'crypto-${_nextRequestId++}';

  @override
  Future<String?> encrypt(String password, String plaintext) async {
    final requestId = _newRequestId();
    final completer = Completer<String?>();
    final subscription =
        WalletDataSavedResponse.stream.listen((response) {
      if (response.requestId == requestId && !completer.isCompleted) {
        if (response.success && response.encryptedData != null) {
          completer.complete(response.encryptedData);
        } else {
          completer.complete(null);
        }
      }
    });

    SaveWalletDataRequest(
      requestId: requestId,
      password: password,
      walletDataJson: plaintext,
    ).sendSignalToRust();

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    await subscription.cancel();
    return result;
  }

  @override
  Future<({String keyHex, String saltHex})?> deriveKey(String password) async {
    final requestId = _newRequestId();
    final completer = Completer<({String keyHex, String saltHex})?>();
    final subscription =
        EncryptionKeyDerivedResponse.stream.listen((response) {
      if (response.requestId == requestId && !completer.isCompleted) {
        if (response.success &&
            response.keyHex != null &&
            response.saltHex != null) {
          completer.complete((
            keyHex: response.keyHex!,
            saltHex: response.saltHex!,
          ));
        } else {
          completer.complete(null);
        }
      }
    });

    DeriveEncryptionKeyRequest(
      requestId: requestId,
      password: password,
    ).sendSignalToRust();

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    await subscription.cancel();
    return result;
  }

  @override
  Future<String?> encryptWithKey(
      String keyHex, String saltHex, String plaintext) async {
    final requestId = _newRequestId();
    final completer = Completer<String?>();
    final subscription =
        WalletDataSavedResponse.stream.listen((response) {
      if (response.requestId == requestId && !completer.isCompleted) {
        if (response.success && response.encryptedData != null) {
          completer.complete(response.encryptedData);
        } else {
          completer.complete(null);
        }
      }
    });

    SaveWithDerivedKeyRequest(
      requestId: requestId,
      keyHex: keyHex,
      saltHex: saltHex,
      walletDataJson: plaintext,
    ).sendSignalToRust();

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    await subscription.cancel();
    return result;
  }

  @override
  Future<String?> decrypt(String password, String ciphertext) async {
    final requestId = _newRequestId();
    final completer = Completer<String?>();
    final subscription =
        WalletDataLoadedResponse.stream.listen((response) {
      if (response.requestId == requestId && !completer.isCompleted) {
        if (response.success && response.walletDataJson != null) {
          completer.complete(response.walletDataJson);
        } else {
          completer.complete(null);
        }
      }
    });

    LoadWalletDataRequest(
      requestId: requestId,
      password: password,
      encryptedData: ciphertext,
    ).sendSignalToRust();

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    await subscription.cancel();
    return result;
  }
}
