import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bragmat/services/backup_envelope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.ffi.dart' as sodium_ffi;

/// libsodium.dll lives outside the repo (downloaded from the pinned
/// sodium_libs binary release). Override with BRAGMAT_LIBSODIUM.
const _defaultDll =
    r'C:\Users\bruce\libsodium-test\libsodium.dll';

void main() {
  late Directory tmp;

  setUpAll(() async {
    final dll = Platform.environment['BRAGMAT_LIBSODIUM'] ?? _defaultDll;
    BackupEnvelope.debugSodium =
        await sodium_ffi.SodiumSumoInit.init(() => DynamicLibrary.open(dll));
    // Small chunk size so multi-chunk paths are exercised cheaply.
    BackupEnvelope.debugChunkSize = 4096;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('envelope_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File writeInput(String name, List<int> bytes) {
    final f = File('${tmp.path}/$name')..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  List<int> randomBytes(int n, [int seed = 42]) =>
      List.generate(n, (_) => Random(seed).nextInt(256));

  group('BackupEnvelope', () {
    test('round-trip restores identical bytes', () async {
      final input = writeInput('in.zip', randomBytes(20000));
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');

      final result = await BackupEnvelope.encryptFile(
        input: input,
        output: enc,
        passphrase: 'correct horse battery staple',
      );
      expect(result.recoveryCode, isNotEmpty);
      expect(result.sha256Hex,
          await BackupEnvelope.sha256OfFile(enc));
      expect(result.size, await enc.length());

      await BackupEnvelope.decryptFile(
        input: enc,
        output: dec,
        passphrase: 'correct horse battery staple',
      );
      expect(await dec.readAsBytes(), await input.readAsBytes());
    });

    test('recovery code alone decrypts (independent secret)', () async {
      final input = writeInput('in.zip', randomBytes(5000));
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');

      final result = await BackupEnvelope.encryptFile(
        input: input,
        output: enc,
        passphrase: 'a passphrase',
      );
      await BackupEnvelope.decryptFile(
        input: enc,
        output: dec,
        recoveryCode: result.recoveryCode,
      );
      expect(await dec.readAsBytes(), await input.readAsBytes());
    });

    test('recovery code is separator- and case-insensitive', () async {
      final input = writeInput('in.zip', randomBytes(1000));
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');
      final result = await BackupEnvelope.encryptFile(
        input: input, output: enc, passphrase: 'p');
      await BackupEnvelope.decryptFile(
        input: enc,
        output: dec,
        recoveryCode:
            result.recoveryCode.toLowerCase().replaceAll('-', ''),
      );
      expect(await dec.readAsBytes(), await input.readAsBytes());
    });

    test('wrong passphrase fails and leaves no plaintext output',
        () async {
      final input = writeInput('in.zip', randomBytes(3000));
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'right');
      await expectLater(
        BackupEnvelope.decryptFile(
            input: enc, output: dec, passphrase: 'wrong'),
        throwsA(isA<IncorrectSecretException>()),
      );
      expect(await dec.exists(), false);
    });

    test('wrong passphrase but correct recovery code still decrypts',
        () async {
      final input = writeInput('in.zip', randomBytes(3000));
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');
      final result = await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'right');
      await BackupEnvelope.decryptFile(
        input: enc,
        output: dec,
        passphrase: 'wrong', // fails → falls back to recovery slot
        recoveryCode: result.recoveryCode,
      );
      expect(await dec.readAsBytes(), await input.readAsBytes());
    });

    test('tampered ciphertext fails authentication', () async {
      final input = writeInput('in.zip', randomBytes(10000));
      final enc = File('${tmp.path}/out.bzp');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      // Flip a byte well inside the ciphertext region (past the
      // 190-byte header).
      final bytes = await enc.readAsBytes();
      bytes[250] ^= 0xFF;
      await enc.writeAsBytes(bytes);
      await expectLater(
        BackupEnvelope.decryptFile(
            input: enc, output: File('${tmp.path}/o.zip'),
            passphrase: 'p'),
        throwsA(isA<CorruptEnvelopeException>()),
      );
    });

    test('truncated ciphertext fails', () async {
      final input = writeInput('in.zip', randomBytes(10000));
      final enc = File('${tmp.path}/out.bzp');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      final bytes = await enc.readAsBytes();
      final trunc = File('${tmp.path}/trunc.bzp')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length - 500));
      await expectLater(
        BackupEnvelope.decryptFile(
            input: trunc, output: File('${tmp.path}/o.zip'),
            passphrase: 'p'),
        throwsA(isA<CorruptEnvelopeException>()),
      );
    });

    test('non-envelope input rejected before decryption', () async {
      final junk = writeInput('junk.bzp', randomBytes(400));
      await expectLater(
        BackupEnvelope.decryptFile(
            input: junk, output: File('${tmp.path}/o.zip'),
            passphrase: 'p'),
        throwsA(isA<InvalidEnvelopeException>()),
      );
    });

    test('unknown envelope version rejected', () async {
      final input = writeInput('in.zip', randomBytes(1000));
      final enc = File('${tmp.path}/out.bzp');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      final bytes = await enc.readAsBytes();
      bytes[4] = 0x99; // version byte
      await enc.writeAsBytes(bytes);
      await expectLater(
        BackupEnvelope.decryptFile(
            input: enc, output: File('${tmp.path}/o.zip'),
            passphrase: 'p'),
        throwsA(isA<UnsupportedEnvelopeVersionException>()),
      );
    });

    test('empty file round-trips', () async {
      final input = writeInput('empty.zip', <int>[]);
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      await BackupEnvelope.decryptFile(
          input: enc, output: dec, passphrase: 'p');
      expect(await dec.length(), 0);
    });

    test('exact chunk-multiple input round-trips', () async {
      // 8192 = exactly 2 × 4096 debug chunk size — exercises the
      // empty-final-message path.
      final input = writeInput('in.zip', randomBytes(8192));
      final enc = File('${tmp.path}/out.bzp');
      final dec = File('${tmp.path}/out.zip');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      await BackupEnvelope.decryptFile(
          input: enc, output: dec, passphrase: 'p');
      expect(await dec.readAsBytes(), await input.readAsBytes());
    });

    test('distinct ciphertext per call (fresh nonces/salts)', () async {
      final input = writeInput('in.zip', randomBytes(2000));
      final a = File('${tmp.path}/a.bzp');
      final b = File('${tmp.path}/b.bzp');
      await BackupEnvelope.encryptFile(
          input: input, output: a, passphrase: 'p');
      await BackupEnvelope.encryptFile(
          input: input, output: b, passphrase: 'p');
      expect(await a.readAsBytes(), isNot(await b.readAsBytes()));
    });

    test('recovery codes are unique and well-formed', () async {
      final c1 = await BackupEnvelope.generateRecoveryCode();
      final c2 = await BackupEnvelope.generateRecoveryCode();
      expect(c1, isNot(c2));
      // 160 bits → 32 base32 chars, grouped by 4 → 8 groups
      expect(c1.replaceAll('-', '').length, 32);
      expect(c1, matches(RegExp(r'^[A-Z2-7]{4}(-[A-Z2-7]{4}){7}$')));
    });

    test('envelope header layout is as specified', () async {
      final input = writeInput('in.zip', randomBytes(500));
      final enc = File('${tmp.path}/out.bzp');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      final bytes = ByteData.sublistView(await enc.readAsBytes());
      // magic
      expect(bytes.getUint8(0), 0x42); // B
      expect(bytes.getUint8(1), 0x52); // R
      expect(bytes.getUint8(2), 0x47); // G
      expect(bytes.getUint8(3), 0x5A); // Z
      expect(bytes.getUint8(4), 1); // version
      expect(bytes.getUint8(5), 1); // kdf = argon2id
      expect(bytes.getUint32(6, Endian.little), BackupEnvelope.opsLimit);
      expect(bytes.getUint32(10, Endian.little), BackupEnvelope.memLimit);
      expect((await enc.length()) > 190, true);
    });

    test('decrypt requires a secret', () async {
      final input = writeInput('in.zip', randomBytes(100));
      final enc = File('${tmp.path}/out.bzp');
      await BackupEnvelope.encryptFile(
          input: input, output: enc, passphrase: 'p');
      await expectLater(
        BackupEnvelope.decryptFile(
            input: enc, output: File('${tmp.path}/o.zip')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
