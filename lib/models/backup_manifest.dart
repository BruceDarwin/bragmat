/// Backup manifest model for portable ZIP backups.
/// 
/// Contains metadata about the backup including version, schema,
/// contents, and statistics for validation and display.
class BackupManifest {
  static const String currentVersion = '2.0';
  
  final String backupVersion;
  final String bragmatVersion;
  final int databaseSchemaVersion;
  final String createdAt;
  final String platform;
  final BackupContents contents;
  final BackupStatistics statistics;
  final BackupSettings? settings;

  BackupManifest({
    required this.backupVersion,
    required this.bragmatVersion,
    required this.databaseSchemaVersion,
    required this.createdAt,
    required this.platform,
    required this.contents,
    required this.statistics,
    this.settings,
  });

  factory BackupManifest.create({
    required String bragmatVersion,
    required int databaseSchemaVersion,
    required String platform,
    required BackupContents contents,
    required BackupStatistics statistics,
    BackupSettings? settings,
  }) {
    return BackupManifest(
      backupVersion: currentVersion,
      bragmatVersion: bragmatVersion,
      databaseSchemaVersion: databaseSchemaVersion,
      createdAt: DateTime.now().toIso8601String(),
      platform: platform,
      contents: contents,
      statistics: statistics,
      settings: settings,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'backupVersion': backupVersion,
      'bragmatVersion': bragmatVersion,
      'databaseSchemaVersion': databaseSchemaVersion,
      'createdAt': createdAt,
      'platform': platform,
      'contents': contents.toMap(),
      'statistics': statistics.toMap(),
      if (settings != null) 'settings': settings!.toMap(),
    };
  }

  factory BackupManifest.fromMap(Map<String, dynamic> map) {
    return BackupManifest(
      backupVersion: map['backupVersion'] as String,
      bragmatVersion: map['bragmatVersion'] as String,
      databaseSchemaVersion: map['databaseSchemaVersion'] as int,
      createdAt: map['createdAt'] as String,
      platform: map['platform'] as String,
      contents: BackupContents.fromMap(map['contents'] as Map<String, dynamic>),
      statistics: BackupStatistics.fromMap(map['statistics'] as Map<String, dynamic>),
      settings: map['settings'] != null
          ? BackupSettings.fromMap(map['settings'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Validate the manifest for compatibility and integrity.
  /// Returns a list of validation errors, or empty list if valid.
  List<String> validate({int? maxSupportedSchemaVersion}) {
    final errors = <String>[];

    // Check backup version
    if (backupVersion != currentVersion) {
      errors.add('Backup version $backupVersion is not supported (current: $currentVersion)');
    }

    // Check schema version
    if (maxSupportedSchemaVersion != null && databaseSchemaVersion > maxSupportedSchemaVersion) {
      errors.add('Database schema version $databaseSchemaVersion is not supported (max: $maxSupportedSchemaVersion)');
    }

    // Validate required fields
    if (bragmatVersion.isEmpty) {
      errors.add('Bragmat version is missing');
    }

    if (createdAt.isEmpty) {
      errors.add('Creation timestamp is missing');
    }

    if (platform.isEmpty) {
      errors.add('Platform is missing');
    }

    // Validate contents
    errors.addAll(contents.validate());

    return errors;
  }
}

class BackupContents {
  final bool database;
  final BackupMediaCounts media;
  final bool settings;

  BackupContents({
    required this.database,
    required this.media,
    required this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'database': database,
      'media': media.toMap(),
      'settings': settings,
    };
  }

  factory BackupContents.fromMap(Map<String, dynamic> map) {
    return BackupContents(
      database: map['database'] as bool,
      media: BackupMediaCounts.fromMap(map['media'] as Map<String, dynamic>),
      settings: map['settings'] as bool,
    );
  }

  List<String> validate() {
    final errors = <String>[];

    if (!database) {
      errors.add('Database is missing from backup');
    }

    return errors;
  }
}

class BackupMediaCounts {
  final int catches;
  final int trips;
  final int journals;
  final int lures;

  BackupMediaCounts({
    required this.catches,
    required this.trips,
    required this.journals,
    required this.lures,
  });

  Map<String, dynamic> toMap() {
    return {
      'catches': catches,
      'trips': trips,
      'journals': journals,
      'lures': lures,
    };
  }

  factory BackupMediaCounts.fromMap(Map<String, dynamic> map) {
    return BackupMediaCounts(
      catches: map['catches'] as int,
      trips: map['trips'] as int,
      journals: map['journals'] as int,
      lures: map['lures'] as int,
    );
  }

  int get total => catches + trips + journals + lures;
}

class BackupStatistics {
  final int catches;
  final int trips;
  final int photos;
  final int missingPhotos;

  BackupStatistics({
    required this.catches,
    required this.trips,
    required this.photos,
    required this.missingPhotos,
  });

  Map<String, dynamic> toMap() {
    return {
      'catches': catches,
      'trips': trips,
      'photos': photos,
      'missingPhotos': missingPhotos,
    };
  }

  factory BackupStatistics.fromMap(Map<String, dynamic> map) {
    return BackupStatistics(
      catches: map['catches'] as int,
      trips: map['trips'] as int,
      photos: map['photos'] as int,
      missingPhotos: map['missingPhotos'] as int,
    );
  }
}

class BackupSettings {
  final int? fishTypeSelectionMode;
  final String? defaultFishType;
  final String? lastUsedFishType;
  final int? currentTripId;
  final String? tideReferenceMode;
  final String? tideReferenceId;

  BackupSettings({
    this.fishTypeSelectionMode,
    this.defaultFishType,
    this.lastUsedFishType,
    this.currentTripId,
    this.tideReferenceMode,
    this.tideReferenceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'fishTypeSelectionMode': fishTypeSelectionMode,
      'defaultFishType': defaultFishType,
      'lastUsedFishType': lastUsedFishType,
      'currentTripId': currentTripId,
      'tideReferenceMode': tideReferenceMode,
      'tideReferenceId': tideReferenceId,
    };
  }

  factory BackupSettings.fromMap(Map<String, dynamic> map) {
    return BackupSettings(
      fishTypeSelectionMode: map['fishTypeSelectionMode'] as int?,
      defaultFishType: map['defaultFishType'] as String?,
      lastUsedFishType: map['lastUsedFishType'] as String?,
      currentTripId: map['currentTripId'] as int?,
      tideReferenceMode: map['tideReferenceMode'] as String?,
      tideReferenceId: map['tideReferenceId'] as String?,
    );
  }
}
