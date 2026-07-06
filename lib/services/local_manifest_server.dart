import 'dart:io';

/// Serves DASH (.mpd) manifest content over a loopback HTTP server so that
/// ExoPlayer (via the video_player plugin) can fetch it exactly the way it
/// fetches any remote manifest — with a real http:// URL.
///
/// Why this exists: ExoPlayer's DASH manifest parser resolves relative
/// BaseURL / SegmentTemplate paths against the manifest's own URI. If the
/// manifest is written to disk and loaded via `file://`, any resolution
/// against that base silently breaks (some ExoPlayer builds also refuse a
/// DASH MediaItem whose URI scheme isn't http/https at all, surfacing as an
/// immediate "Source error"). Serving the exact same bytes over
/// `http://127.0.0.1:<port>/...` makes the manifest URI a normal HTTP URL,
/// which is the same trick dash.js effectively relies on when you paste XML
/// into it (it's given a Blob URL / object URL served over the page's own
/// origin, not a raw filesystem path).
class LocalManifestServer {
  LocalManifestServer._internal();
  static final LocalManifestServer instance = LocalManifestServer._internal();

  HttpServer? _server;
  final Map<String, String> _manifests = {};

  Future<int> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing.port;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;

    server.listen((request) async {
      final path = request.uri.path;
      final content = _manifests[path];
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      if (content == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType =
            ContentType('application', 'dash+xml', charset: 'utf-8')
        ..headers.set('Cache-Control', 'no-store')
        ..write(content);
      await request.response.close();
    }, onError: (_) {});

    return server.port;
  }

  /// Publishes [xmlContent] and returns a loopback URL ExoPlayer can fetch
  /// as if it were any other network manifest.
  Future<String> publish(String xmlContent) async {
    final port = await _ensureServer();
    final name = 'manifest_${DateTime.now().microsecondsSinceEpoch}.mpd';
    _manifests['/$name'] = xmlContent;
    return 'http://127.0.0.1:$port/$name';
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _manifests.clear();
  }
}
