import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

/// The file's magic bytes were not "BRGZ".
class InvalidEnvelopeException implements Exception {
  @override
  String toString() => 'Not a Bragmat encrypted backup';
}

/// The envelope version is newer than this build understands.
class UnsupportedEnvelopeVersionException implements Exception {
  UnsupportedEnvelopeVersionException(this.version);
  final int version;
  @override
  String toString() => 'Unsupported backup envelope version: $version';
}

/// Neither the passphrase nor the recovery code could unwrap the key.
class IncorrectSecretException implements Exception {
  @override
  String toString() => 'Incorrect passphrase or recovery code';
}

/// Ciphertext failed authentication or was truncated.
class CorruptEnvelopeException implements Exception {
  @override
  String toString() => 'Encrypted backup is corrupt or incomplete';
}

/// Metadata produced by a successful encryption.
class EncryptedBackupResult {
  const EncryptedBackupResult({
    required this.recoveryCode,
    required this.sha256Hex,
    required this.size,
  });

  /// Independent decryption secret — shown to the user ONCE at enable
  /// time, never stored or logged by the app.
  final String recoveryCode;

  /// SHA-256 of the written .bzp file — recorded for upload verification.
  final String sha256Hex;

  /// Total size of the written .bzp file in bytes.
  final int size;
}

/// Encrypted backup envelope — Stage 4C-2 crypto core.
///
/// File format, version 1 ("BRGZ" magic). All multi-byte integers are
/// little-endian; all offsets in bytes:
///
/// ```
///   0   magic            "BRGZ"                         (4)
///   4   version          0x01                           (1)
///   5   kdf id           0x01 = argon2id13              (1)
///   6   opslimit         u32 LE                         (4)
///  10   memlimit         u32 LE (bytes)                 (4)
///  14   salt_p           passphrase KDF salt            (16)
///  30   nonce_p          secretbox nonce, passph. wrap  (24)
///  54   wrapped_p        secretbox(archive_key)         (48)
/// 102   salt_r           recovery-code KDF salt         (16)
/// 118   nonce_r          secretbox nonce, recovery wrap (24)
/// 142   wrapped_r        secretbox(archive_key)         (48)
/// 190   ciphertext       secretstream header (24) + blocks
///                        (chunk + 17-byte tag each)
/// ```
///
/// Key structure (design doc §14.3): a random 32-byte `archive_key`
/// encrypts the payload via XChaCha20-Poly1305 secretstream. It is
/// wrapped INDEPENDENTLY under a passphrase-derived key and a
/// recovery-code-derived key (both Argon2id). Either secret alone can
/// restore; the recovery code is not derived from the passphrase.
/// Rotating the passphrase re-wraps `archive_key` only.
///
/// Versioning rule: decryptors must implement every version they have
/// ever emitted and reject unknown versions loudly — a new KDF/cipher
/// bumps `version`; additive header fields reuse the current version.
///
/// SECURITY: passphrases, recovery codes, archive keys and decrypted
/// content must never be logged (including in error messages). Secrets
/// live in [SecureKey] buffers and are disposed after use.
class BackupEnvelope {
  BackupEnvelope._();

  static const int version = 1;
  static const int kdfArgon2id = 1;
  static const int _headerLength = 190;
  static const int _defaultChunkSize = 8 * 1024 * 1024;

  /// Argon2id parameters — stored in the header so future versions can
  /// tune them without breaking old archives. "Interactive" profile:
  /// ~64 MiB / 2 passes — deliberate choice for mobile (Moto G15).
  static const int opsLimit = 2;
  static const int memLimit = 64 * 1024 * 1024;

  /// Test seam — overrides the lazy [SodiumSumoInit] path.
  static SodiumSumo? debugSodium;

  /// Test seam — smaller chunk size exercises multi-chunk paths cheaply.
  static int debugChunkSize = _defaultChunkSize;

  static Future<SodiumSumo> get _sodiumInstance async =>
      debugSodium ??= await SodiumSumoInit.init();

  /// Generate a recovery code: 160 bits of entropy, base32, grouped
  /// `XXXX-XXXX-…`. Independent of the passphrase.
  static Future<String> generateRecoveryCode() async {
    final sodium = await _sodiumInstance;
    final raw = sodium.randombytes.buf(20);
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; // RFC 4648 base32
    final code = StringBuffer();
    var bits = 0;
    var acc = 0;
    for (final b in raw) {
      acc = (acc << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        code.write(alphabet[(acc >> bits) & 31]);
      }
    }
    if (bits > 0) {
      code.write(alphabet[(acc << (5 - bits)) & 31]);
    }
    final s = code.toString();
    final groups = <String>[];
    for (var i = 0; i < s.length; i += 4) {
      groups.add(s.substring(i, i + 4 > s.length ? s.length : i + 4));
    }
    return groups.join('-');
  }

  /// Normalise a recovery code for KDF input — case- and
  /// separator-insensitive so transcription mistakes don't matter.
  static String _normalizeRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');

  /// Encrypt [input] (a ZIP produced by ZipBackupService) to [output]
  /// (.bzp). [recoveryCode] may be supplied (re-key flow) or omitted —
  /// a fresh one is generated and returned in the result. Either
  /// [passphrase] or the recovery code alone can later decrypt.
  static Future<EncryptedBackupResult> encryptFile({
    required File input,
    required File output,
    required String passphrase,
    String? recoveryCode,
  }) async {
    final sodium = await _sodiumInstance;
    final code = recoveryCode ?? await generateRecoveryCode();
    final chunkSize = debugChunkSize;

    final archiveKey = sodium.crypto.secretStream.keygen();
    (SecureKey, Uint8List)? passphraseKey;
    (SecureKey, Uint8List)? recoveryKey;
    try {
      passphraseKey = await _deriveKey(sodium, passphrase);
      recoveryKey =
          await _deriveKey(sodium, _normalizeRecoveryCode(code));

      final header = _buildHeader(
        sodium,
        archiveKey,
        passphraseKey.$1,
        passphraseKey.$2,
        recoveryKey.$1,
        recoveryKey.$2,
      );

      final sink = output.openWrite();
      try {
        sink.add(header);
        await for (final block in sodium.crypto.secretStream.pushChunked(
          messageStream: input.openRead(),
          key: archiveKey,
          chunkSize: chunkSize,
        )) {
          sink.add(block);
        }
      } finally {
        await sink.close();
      }

      return EncryptedBackupResult(
        recoveryCode: code,
        sha256Hex: await sha256OfFile(output),
        size: await output.length(),
      );
    } finally {
      archiveKey.dispose();
      passphraseKey?.$1.dispose();
      recoveryKey?.$1.dispose();
    }
  }

  /// Decrypt [input] (.bzp) to [output] (.zip). Exactly one of
  /// [passphrase] or [recoveryCode] is required; if both are supplied the
  /// passphrase is tried first. The output file is deleted on failure so
  /// a partial plaintext archive is never left behind.
  static Future<void> decryptFile({
    required File input,
    required File output,
    String? passphrase,
    String? recoveryCode,
  }) async {
    if (passphrase == null && recoveryCode == null) {
      throw ArgumentError('passphrase or recoveryCode required');
    }
    final sodium = await _sodiumInstance;

    final fileLength = await input.length();
    final headerBytes = await input
        .openRead(0, _headerLength)
        .fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c))
        .then((b) => b.takeBytes());
    if (headerBytes.length < _headerLength) {
      throw InvalidEnvelopeException();
    }
    final header = ByteData.sublistView(headerBytes);
    if (headerBytes[0] != 0x42 || // 'B'
        headerBytes[1] != 0x52 || // 'R'
        headerBytes[2] != 0x47 || // 'G'
        headerBytes[3] != 0x5A) {
      // 'Z'
      throw InvalidEnvelopeException();
    }
    final version = headerBytes[4];
    if (version != BackupEnvelope.version) {
      throw UnsupportedEnvelopeVersionException(version);
    }
    if (headerBytes[5] != kdfArgon2id) {
      throw UnsupportedEnvelopeVersionException(version);
    }
    final opsLimit = header.getUint32(6, Endian.little);
    final memLimit = header.getUint32(10, Endian.little);

    final archiveKey = await _tryUnwrap(
      sodium,
      headerBytes,
      opsLimit,
      memLimit,
      passphrase: passphrase,
      recoveryCode: recoveryCode,
    );
    if (archiveKey == null) {
      throw IncorrectSecretException();
    }

    try {
      final sink = output.openWrite();
      try {
        await for (final block in sodium.crypto.secretStream.pullChunked(
          cipherStream: input.openRead(_headerLength, fileLength),
          key: archiveKey,
          chunkSize: _debugChunkSizeForDecrypt(),
        )) {
          sink.add(block);
        }
      } finally {
        await sink.close();
      }
    } catch (e) {
      if (await output.exists()) {
        await output.delete();
      }
      throw CorruptEnvelopeException();
    } finally {
      archiveKey.dispose();
    }
  }

  /// Compute a file's SHA-256 — upload/download integrity check.
  static Future<String> sha256OfFile(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  // ── internals ──────────────────────────────────────────────────────────

  /// Chunk size used on decrypt must equal the value used at encrypt —
  /// secretstream block boundaries depend on it. The debug override is
  /// shared, so this just forwards.
  static int _debugChunkSizeForDecrypt() => debugChunkSize;

  /// Derive a wrap key. Returns (key, salt) — the salt is generated here
  /// and stored in the header by the caller.
  static Future<(SecureKey, Uint8List)> _deriveKey(
    SodiumSumo sodium,
    String secret,
  ) async {
    final salt = sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes);
    final key = sodium.crypto.pwhash.call(
      outLen: sodium.crypto.secretBox.keyBytes,
      password: Int8List.fromList(utf8.encode(secret)),
      salt: salt,
      opsLimit: opsLimit,
      memLimit: memLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
    return (key, salt);
  }

  static Uint8List _buildHeader(
    SodiumSumo sodium,
    SecureKey archiveKey,
    SecureKey passphraseKey,
    Uint8List saltP,
    SecureKey recoveryKey,
    Uint8List saltR,
  ) {
    Uint8List wrap(SecureKey wrapKey) {
      final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
      final wrapped = sodium.crypto.secretBox.easy(
        message: Uint8List.fromList(archiveKey.extractBytes()),
        nonce: nonce,
        key: wrapKey,
      );
      return Uint8List.fromList([...nonce, ...wrapped]);
    }

    final p = wrap(passphraseKey); // nonce(24) + wrapped(48) = 72
    final r = wrap(recoveryKey);

    final header = BytesBuilder();
    header.add([0x42, 0x52, 0x47, 0x5A]); // "BRGZ"
    header.addByte(version);
    header.addByte(kdfArgon2id);
    final params = ByteData(8)
      ..setUint32(0, opsLimit, Endian.little)
      ..setUint32(4, memLimit, Endian.little);
    header.add(params.buffer.asUint8List());
    header.add(saltP);
    header.add(p);
    header.add(saltR);
    header.add(r);
    return header.takeBytes();
  }

  /// Try passphrase slot then recovery-code slot. Returns null only when
  /// every supplied secret failed authentication.
  static Future<SecureKey?> _tryUnwrap(
    SodiumSumo sodium,
    Uint8List header,
    int opsLimit,
    int memLimit, {
    String? passphrase,
    String? recoveryCode,
  }) async {
    final attempts = <(String, int)>[
      if (passphrase != null) (passphrase, 14), // salt_p at offset 14
      if (recoveryCode != null)
        (_normalizeRecoveryCode(recoveryCode), 102), // salt_r
    ];
    for (final (secret, saltOffset) in attempts) {
      final salt = Uint8List.sublistView(header, saltOffset, saltOffset + 16);
      final nonceOffset = saltOffset + 16;
      final wrappedOffset = nonceOffset + 24;
      final key = sodium.crypto.pwhash.call(
        outLen: sodium.crypto.secretBox.keyBytes,
        password: Int8List.fromList(utf8.encode(secret)),
        salt: salt,
        opsLimit: opsLimit,
        memLimit: memLimit,
        alg: CryptoPwhashAlgorithm.argon2id13,
      );
      try {
        final raw = sodium.crypto.secretBox.openEasy(
          cipherText: Uint8List.sublistView(header, wrappedOffset, wrappedOffset + 48),
          nonce: Uint8List.sublistView(header, nonceOffset, nonceOffset + 24),
          key: key,
        );
        key.dispose();
        return SecureKey.fromList(sodium, raw);
      } catch (_) {
        key.dispose();
        continue; // wrong secret for this slot — try the next
      }
    }
    return null;
  }
}
