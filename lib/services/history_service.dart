import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_entry.dart';

/// Persists watch history (title, source, playback position/duration) in
/// SharedPreferences as a JSON list, most-recently-watched first. Powers the
/// Home screen's "Continue Watching" list and resume-at-position playback.
class HistoryService {
  static const _prefsKey = 'watch_history_v1';
  static const _maxEntries = 60;

  static final HistoryService instance = HistoryService._();
  HistoryService._();

  /// A stable identity for a video source, independent of signed-URL query
  /// params that rotate on every re-fetch (e.g. fbcdn `oh`/`oe`), so the
  /// same underlying video keeps updating a single history row.
  static String keyFor({required String videoPath, String? mpdContent}) {
    final basis = mpdContent != null && mpdContent.isNotEmpty
        ? mpdContent
        : Uri.tryParse(videoPath)?.replace(query: '').toString() ?? videoPath;
    return _stableHash(basis).toRadixString(36);
  }

  /// A dependency-free 64-bit FNV-1a hash. Good enough for a local dedupe
  /// key — this never needs to be cryptographically secure, just stable.
  static int _stableHash(String input) {
    const fnvPrime = 0x100000001b3;
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash;
  }

  Future<List<HistoryEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.lastWatchedAtMs.compareTo(a.lastWatchedAtMs));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<HistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    entries.sort((a, b) => b.lastWatchedAtMs.compareTo(a.lastWatchedAtMs));
    final trimmed = entries.take(_maxEntries).toList();
    await prefs.setString(
      _prefsKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  /// Creates or updates the history row for this source. Returns the entry's
  /// stable key so the caller can push subsequent progress updates.
  Future<String> upsert({
    required String title,
    required String videoPath,
    required bool isNetwork,
    required bool isDash,
    required bool fbCdnEnabled,
    String? mpdContent,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    final key = keyFor(videoPath: videoPath, mpdContent: mpdContent);
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.key == key);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (idx >= 0) {
      entries[idx] = entries[idx].copyWith(
        title: title.isNotEmpty ? title : entries[idx].title,
        positionMs: positionMs > 0 ? positionMs : entries[idx].positionMs,
        durationMs: durationMs > 0 ? durationMs : entries[idx].durationMs,
        lastWatchedAtMs: now,
      );
    } else {
      entries.add(HistoryEntry(
        key: key,
        title: title,
        videoPath: videoPath,
        isNetwork: isNetwork,
        isDash: isDash,
        fbCdnEnabled: fbCdnEnabled,
        mpdContent: mpdContent,
        positionMs: positionMs,
        durationMs: durationMs,
        lastWatchedAtMs: now,
      ));
    }
    await _saveAll(entries);
    return key;
  }

  Future<void> updateProgress(
      String key, int positionMs, int durationMs) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx < 0) return;
    entries[idx] = entries[idx].copyWith(
      positionMs: positionMs,
      durationMs: durationMs,
      lastWatchedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveAll(entries);
  }

  /// Stores the given thumbnail path for [key] the first time a video is
  /// played — later plays never overwrite an already-captured thumbnail.
  Future<void> setThumbnailIfAbsent(String key, String thumbnailPath) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx < 0) return;
    final existing = entries[idx].thumbnailPath;
    if (existing != null && existing.isNotEmpty) return;
    entries[idx] = entries[idx].copyWith(thumbnailPath: thumbnailPath);
    await _saveAll(entries);
  }

  Future<void> remove(String key) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.key == key);
    await _saveAll(entries);
  }

  /// Updates the display title of an entry without touching any other field.
  Future<void> rename(String key, String newTitle) async {
    if (newTitle.trim().isEmpty) return;
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.key == key);
    if (idx < 0) return;
    entries[idx] = entries[idx].copyWith(title: newTitle.trim());
    await _saveAll(entries);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
