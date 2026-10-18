import 'dart:io';

import 'package:bragmat/services/cloud_backup_service.dart';

/// In-memory cloud backend — no network. Fault injection covers every
/// failure mode the service/UI must survive. Shared by the service
/// tests and the CloudBackupScreen widget tests.
class FakeCloudBackupBackend implements CloudBackupBackend {
  String? uid = 'user-A';
  final objects = <String, List<int>>{};
  final metadata = <String, Map<String, String>>{};
  final deleteCalls = <List<String>>[];
  var deleteAllCalls = 0;
  var listCalls = 0;
  var uploadCalls = 0;

  // Fault injection.
  var failUpload = false;
  var failDownload = false;
  var failDelete = false;
  var failList = false;
  var quotaExceeded = false;
  var failEdgeFunction = false;

  /// Artificial latency — lets tests exercise the busy/cancel UI.
  Duration uploadDelay = Duration.zero;

  /// Deliver tampered bytes on the next download (integrity check bait).
  List<int>? downloadOverride;

  @override
  String? get userId => uid;

  @override
  Future<void> upload(String remoteName, File file,
      {required Map<String, String> metadata}) async {
    uploadCalls++;
    if (quotaExceeded) throw CloudQuotaExceededException();
    if (failUpload) throw const SocketException('offline');
    if (objects.containsKey(remoteName)) {
      throw RemoteObjectExistsException(remoteName);
    }
    objects[remoteName] = await file.readAsBytes();
    if (uploadDelay > Duration.zero) await Future.delayed(uploadDelay);
    this.metadata[remoteName] = metadata;
  }

  @override
  Future<List<RemoteBackupInfo>> list() async {
    listCalls++;
    if (failList) throw const SocketException('offline');
    return [
      for (final e in objects.entries)
        RemoteBackupInfo(
          name: e.key,
          size: e.value.length,
          sha256Hex: metadata[e.key]?['sha256'],
          createdAt: DateTime(2026),
        ),
    ];
  }

  @override
  Future<void> download(String remoteName, File dest) async {
    if (failDownload) throw const SocketException('offline');
    final bytes = downloadOverride ?? objects[remoteName];
    if (bytes == null) {
      throw const FileSystemException('not found');
    }
    downloadOverride = null;
    await dest.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<int> delete(List<String> remoteNames) async {
    if (failDelete) throw const SocketException('offline');
    deleteCalls.add(remoteNames);
    var n = 0;
    for (final name in remoteNames) {
      if (objects.remove(name) != null) {
        metadata.remove(name);
        n++;
      }
    }
    return n;
  }

  @override
  Future<int> deleteAll() async {
    if (failEdgeFunction) throw const SocketException('offline');
    deleteAllCalls++;
    final n = objects.length;
    objects.clear();
    metadata.clear();
    return n;
  }
}
