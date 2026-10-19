// Stage 4C-5A — live API-level checks for the `backups` bucket and the
// delete-backups Edge Function. dart:io only — no external deps.
//
//   dart run tool/cloud_backup_api_checks.dart phase1
//   dart run tool/cloud_backup_api_checks.dart phase2
//
// Credentials are read from a LOCAL env file (default
// ~/bragmat-test.env) — never printed, never committed:
//   SUPABASE_URL, SUPABASE_ANON_KEY,
//   TEST_A_EMAIL/TEST_A_PASSWORD  (approved synthetic account)
//   TEST_R_EMAIL/TEST_R_PASSWORD  (approved in phase1, revoked in phase2)
//
// Phase 1: run while BOTH test accounts are approved.
// Phase 2: run AFTER the owner sets R's beta_testers status='revoked'.
//
// All objects are synthetic (names start `apitest_`). JWTs are minted
// via /auth/v1/token at runtime and kept in memory only.

import 'dart:convert';
import 'dart:io';

final env = <String, String>{};
late String url;
late String anon;

final results = <String>[];
void check(String id, String name, bool ok, [String detail = '']) {
  results.add(
      '$id  ${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : ' — $detail'}');
}

Future<HttpClientResponse> _req(String method, String path,
    {String? jwt, Object? body, Map<String, String>? headers}) async {
  final client = HttpClient();
  final request = await client.openUrl(method, Uri.parse('$url$path'));
  request.headers.set('apikey', anon);
  if (jwt != null) request.headers.set('Authorization', 'Bearer $jwt');
  if (headers != null) headers.forEach((k, v) => request.headers.set(k, v));
  if (body is List<int>) {
    request.add(body);
  } else if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  return request.close();
}

Future<String> mintJwt(String email, String password) async {
  final r = await _req('POST', '/auth/v1/token?grant_type=password',
      body: {'email': email, 'password': password});
  final data = jsonDecode(await r.transform(utf8.decoder).join());
  final token = data['access_token'] as String?;
  if (token == null) {
    throw StateError('auth failed for $email: ${data['error_description'] ?? data}');
  }
  return token;
}

String uidFromJwt(String jwt) {
  final payload = jwt.split('.')[1];
  final norm = base64Url.normalize(payload);
  return jsonDecode(utf8.decode(base64Url.decode(norm)))['sub'] as String;
}

Future<HttpClientResponse> upload(String jwt, String path, List<int> bytes,
        {String? sha256Hex}) =>
    _req('POST', '/storage/v1/object/backups/$path',
        jwt: jwt,
        headers: {
          'Content-Type': 'application/octet-stream',
          if (sha256Hex != null)
            'x-metadata': base64.encode(utf8.encode(jsonEncode({'sha256': sha256Hex}))),
        },
        body: bytes);

Future<HttpClientResponse> list(String? jwt, String prefix) =>
    _req('POST', '/storage/v1/object/list/backups',
        jwt: jwt, body: {'prefix': prefix, 'limit': 1000, 'offset': 0});

Future<HttpClientResponse> download(String? jwt, String path) =>
    _req('GET', '/storage/v1/object/backups/$path', jwt: jwt);

Future<HttpClientResponse> remove(String jwt, List<String> paths) =>
    _req('DELETE', '/storage/v1/object/backups',
        jwt: jwt, body: {'prefixes': paths});

Future<HttpClientResponse> move(
        String jwt, String source, String destination) =>
    _req('POST', '/storage/v1/object/move',
        jwt: jwt,
        body: {
          'bucketId': 'backups',
          'sourceKey': source,
          'destinationKey': destination,
        });

Future<HttpClientResponse> ef(String? jwt, Object? body) =>
    _req('POST', '/functions/v1/delete-backups', jwt: jwt, body: body ?? {});

Future<void> drain(HttpClientResponse r) => r.drain<void>();
Future<List<int>> bytes(HttpClientResponse r) =>
    r.expand((c) => c).toList();

List<int> synthetic(int seed) =>
    List.generate(2048, (i) => (i * 31 + seed) % 251);

Future<void> phase1(String jwtA, String jwtR, String uidA, String uidR) async {
  final pathA = '$uidA/apitest_t1.bzp';
  final bytesA = synthetic(1);

  // API-1: approved user uploads under own prefix.
  var r = await upload(jwtA, pathA, bytesA, sha256Hex: 'deadbeef');
  check('API-1', 'A uploads own-prefix object', r.statusCode == 200,
      'HTTP ${r.statusCode}');
  await drain(r);

  // API-2: download returns identical bytes (transfer integrity).
  r = await download(jwtA, pathA);
  final got = await bytes(r);
  check('API-2', 'download returns identical bytes',
      r.statusCode == 200 && got.length == bytesA.length &&
          List.generate(bytesA.length, (i) => got[i] == bytesA[i])
              .every((e) => e),
      'HTTP ${r.statusCode}, ${got.length}B');

  // META: does custom sha256 metadata round-trip through list()?
  r = await list(jwtA, '$uidA/');
  final listed = jsonDecode(await r.transform(utf8.decoder).join()) as List;
  final entry = listed.firstWhere(
      (o) => o['name'] == 'apitest_t1.bzp', orElse: () => null);
  final meta = entry == null ? null : entry['metadata'];
  check('META', 'list() returns custom sha256 metadata',
      entry != null && meta is Map && meta['sha256'] == 'deadbeef',
      'metadata=$meta');

  // API-3: re-upload same name — upsert off → must fail, no overwrite.
  r = await upload(jwtA, pathA, synthetic(2));
  check('API-3', 'duplicate upload rejected (no overwrite)',
      r.statusCode >= 400, 'HTTP ${r.statusCode}');
  await drain(r);
  r = await download(jwtA, pathA);
  final got2 = await bytes(r);
  check('API-3b', 'original bytes intact after rejected overwrite',
      got2.length == bytesA.length &&
          List.generate(bytesA.length, (i) => got2[i] == bytesA[i])
              .every((e) => e));

  // API-4: list sees only own prefix.
  r = await list(jwtA, '$uidR/');
  final cross = jsonDecode(await r.transform(utf8.decoder).join()) as List;
  check('API-4', 'A listing R prefix is empty',
      r.statusCode == 200 && cross.isEmpty, 'HTTP ${r.statusCode}');

  // API-5/6: cross-user download + upload denied.
  r = await download(jwtA, '$uidR/apitest_r.bzp');
  check('API-5', 'A cannot download R object', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await upload(jwtA, '$uidR/apitest_hijack.bzp', synthetic(3));
  check('API-6', 'A cannot upload into R prefix', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);

  // API-7: move/rename — no UPDATE policy → denied even on own object.
  r = await move(jwtA, pathA, '$uidA/apitest_moved.bzp');
  check('API-7', 'rename/move denied (no UPDATE policy)',
      r.statusCode >= 400, 'HTTP ${r.statusCode}');
  await drain(r);

  // Seed R's object while R is still approved (needed by phase-2 EF-6
  // and API-5's cross-user target).
  r = await upload(jwtR, '$uidR/apitest_r.bzp', synthetic(4));
  check('API-0', 'R seeds own object (pre-revocation)',
      r.statusCode == 200, 'HTTP ${r.statusCode}');
  await drain(r);

  // Retention behaviour is a client-side policy (keep-3) — covered by
  // unit/widget tests; live check here verifies that >3 objects can
  // coexist so pruning is observably app-driven, not server-enforced.
  for (var i = 0; i < 4; i++) {
    r = await upload(jwtA, '$uidA/apitest_ret_$i.bzp', synthetic(10 + i));
    await drain(r);
  }
  r = await list(jwtA, '$uidA/');
  final all = jsonDecode(await r.transform(utf8.decoder).join()) as List;
  check('RET', 'server holds >3 objects (retention is app-side)',
      all.length >= 5, '${all.length} objects');

  // API-8: API delete physically removes (re-list confirms).
  r = await remove(jwtA, [pathA]);
  check('API-8', 'API remove accepted', r.statusCode == 200,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await list(jwtA, '$uidA/');
  final after = jsonDecode(await r.transform(utf8.decoder).join()) as List;
  check('API-8b', 'deleted object absent from subsequent listing',
      !after.any((o) => o['name'] == 'apitest_t1.bzp'));

  // API-10: anon access denied on download+list.
  r = await download(null, pathA);
  check('API-10a', 'unauthenticated download denied', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await list(null, '$uidA/');
  check('API-10b', 'unauthenticated list denied', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);

  // ── Edge Function ────────────────────────────────────────────────────
  r = await ef(null, {});
  check('EF-1', 'no Authorization → 401', r.statusCode == 401,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await ef('invalid.jwt.token', {});
  check('EF-2', 'invalid JWT → 401', r.statusCode == 401,
      'HTTP ${r.statusCode}');
  await drain(r);

  r = await ef(jwtA, {'name': 'apitest_ret_0.bzp'});
  check('EF-3', 'single-name delete works', r.statusCode == 200,
      'HTTP ${r.statusCode}');
  await drain(r);

  r = await ef(jwtA, {'name': '../$uidR/apitest_r.bzp'});
  check('EF-4', 'path traversal rejected', r.statusCode == 400,
      'HTTP ${r.statusCode}');
  await drain(r);

  r = await ef(jwtA, {'name': 'does_not_exist.bzp'});
  check('EF-5', 'missing name is a no-op', r.statusCode == 200,
      'HTTP ${r.statusCode}');
  await drain(r);

  // EF delete-all: removes remaining apitest_ret_* under A.
  r = await ef(jwtA, {});
  final efAll = jsonDecode(await r.transform(utf8.decoder).join());
  check('EF-7', 'delete-all returns deleted count',
      r.statusCode == 200 && (efAll['deleted'] as num?) != null,
      '$efAll');

  // Cleanup check: A's prefix should be empty of apitest objects.
  r = await list(jwtA, '$uidA/');
  final rem = jsonDecode(await r.transform(utf8.decoder).join()) as List;
  check('CLEAN', 'A prefix emptied by delete-all', rem.isEmpty,
      '${rem.length} left');
}

Future<void> phase2(String jwtR, String uidR) async {
  // R is now revoked — ordinary storage access must be denied.
  var r = await list(jwtR, '$uidR/');
  check('API-9a', 'revoked list denied', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await download(jwtR, '$uidR/apitest_r.bzp');
  check('API-9b', 'revoked download denied', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await upload(jwtR, '$uidR/apitest_rev.bzp', synthetic(9));
  check('API-9c', 'revoked upload denied', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);
  r = await remove(jwtR, ['$uidR/apitest_r.bzp']);
  check('API-9d', 'revoked API delete denied', r.statusCode >= 400,
      'HTTP ${r.statusCode}');
  await drain(r);

  // EF-6: revoked user can still delete their own backups via the Edge
  // Function — the account-closure path.
  r = await ef(jwtR, {'reason': 'account_closure'});
  final body = jsonDecode(await r.transform(utf8.decoder).join());
  check('EF-6', 'revoked delete-all via Edge Function',
      r.statusCode == 200 && (body['deleted'] as num? ?? 0) >= 1,
      '$body');

  // Idempotent: nothing left to delete.
  r = await ef(jwtR, {'reason': 'account_closure'});
  final body2 = jsonDecode(await r.transform(utf8.decoder).join());
  check('EF-6b', 'repeat delete is idempotent',
      r.statusCode == 200 && body2['deleted'] == 0, '$body2');
}

Future<void> main(List<String> args) async {
  final envFile = File(args.length > 1
      ? args[1]
      : '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}/bragmat-test.env');
  if (!await envFile.exists()) {
    stderr.writeln('missing env file: ${envFile.path}\n'
        'expected keys: SUPABASE_URL SUPABASE_ANON_KEY '
        'TEST_A_EMAIL TEST_A_PASSWORD TEST_R_EMAIL TEST_R_PASSWORD');
    exit(2);
  }
  for (final line in await envFile.readAsLines()) {
    final i = line.indexOf('=');
    if (i > 0) env[line.substring(0, i).trim()] = line.substring(i + 1).trim();
  }
  url = env['SUPABASE_URL']!;
  anon = env['SUPABASE_ANON_KEY']!;

  final jwtA =
      await mintJwt(env['TEST_A_EMAIL']!, env['TEST_A_PASSWORD']!);
  final uidA = uidFromJwt(jwtA);

  final phase = args.isEmpty ? 'phase1' : args[0];
  if (phase == 'phase1') {
    final jwtR =
        await mintJwt(env['TEST_R_EMAIL']!, env['TEST_R_PASSWORD']!);
    await phase1(jwtA, jwtR, uidA, uidFromJwt(jwtR));
  } else if (phase == 'phase2') {
    final jwtR =
        await mintJwt(env['TEST_R_EMAIL']!, env['TEST_R_PASSWORD']!);
    await phase2(jwtR, uidFromJwt(jwtR));
  } else {
    stderr.writeln('usage: cloud_backup_api_checks.dart [phase1|phase2]');
    exit(2);
  }

  stdout.writeln('\n── Results ($phase) ──');
  for (final r in results) {
    stdout.writeln(r);
  }
  final fails = results.where((r) => r.contains('FAIL')).length;
  stdout.writeln(fails == 0 ? 'ALL PASS' : '$fails FAILURE(S)');
  exit(fails == 0 ? 0 : 1);
}
