/// A single watched-video record, persisted locally so the Home screen can
/// show "Continue Watching" and resume playback at the saved position.
class HistoryEntry {
  final String key;
  final String title;
  final String videoPath;
  final bool isNetwork;
  final bool isDash;
  final bool fbCdnEnabled;
  final String? mpdContent;
  final int positionMs;
  final int durationMs;
  final int lastWatchedAtMs;
  final String? thumbnailPath;

  const HistoryEntry({
    required this.key,
    required this.title,
    required this.videoPath,
    required this.isNetwork,
    required this.isDash,
    required this.fbCdnEnabled,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatchedAtMs,
    this.mpdContent,
    this.thumbnailPath,
  });

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  bool get isFinished => progress > 0.96;

  HistoryEntry copyWith({
    String? title,
    int? positionMs,
    int? durationMs,
    int? lastWatchedAtMs,
    String? thumbnailPath,
  }) {
    return HistoryEntry(
      key: key,
      title: title ?? this.title,
      videoPath: videoPath,
      isNetwork: isNetwork,
      isDash: isDash,
      fbCdnEnabled: fbCdnEnabled,
      mpdContent: mpdContent,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lastWatchedAtMs: lastWatchedAtMs ?? this.lastWatchedAtMs,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'videoPath': videoPath,
        'isNetwork': isNetwork,
        'isDash': isDash,
        'fbCdnEnabled': fbCdnEnabled,
        'mpdContent': mpdContent,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lastWatchedAtMs': lastWatchedAtMs,
        'thumbnailPath': thumbnailPath,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        key: json['key'] as String,
        title: json['title'] as String? ?? 'Video',
        videoPath: json['videoPath'] as String? ?? '',
        isNetwork: json['isNetwork'] as bool? ?? true,
        isDash: json['isDash'] as bool? ?? false,
        fbCdnEnabled: json['fbCdnEnabled'] as bool? ?? false,
        mpdContent: json['mpdContent'] as String?,
        positionMs: json['positionMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        lastWatchedAtMs: json['lastWatchedAtMs'] as int? ?? 0,
        thumbnailPath: json['thumbnailPath'] as String?,
      );
}
