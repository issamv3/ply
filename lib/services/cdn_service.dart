class CdnService {
  static const _fbFreeHost = 'z-m-video-cdg4-2.xx.fbcdn.net';

  // A real mobile-browser User-Agent. fbcdn.net edges commonly 403 requests
  // whose User-Agent identifies as a bare HTTP client / ExoPlayer's default
  // ("ExoPlayerLib/2.x.x"), even though the signed URL itself (the oh/oe
  // query params) is still valid. Browsers (and dash.js, which just reuses
  // the page's own browser context) never hit this because they always send
  // a normal browser UA + Referer automatically — that's the real reason
  // "it works in dash.js but not in the app" even after the manifest is
  // fetched correctly.
  static const _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static String rewriteMpdContent(String xmlContent,
      {required bool fbCdnEnabled}) {
    if (!fbCdnEnabled) return xmlContent;
    if (!xmlContent.contains('fbcdn.net')) return xmlContent;
    return xmlContent.replaceAllMapped(
      RegExp(r'https?://[a-zA-Z0-9\-\.]*fbcdn\.net'),
      (_) => 'https://$_fbFreeHost',
    );
  }

  static String rewrite(String url, {required bool fbCdnEnabled}) {
    if (!fbCdnEnabled) return url;
    if (!url.contains('fbcdn.net')) return url;
    try {
      final uri = Uri.parse(url);
      final rewritten = uri.replace(host: _fbFreeHost);
      return rewritten.toString();
    } catch (_) {
      return url;
    }
  }

  static bool isFacebookCdn(String url) =>
      url.contains('fbcdn.net') || url.contains('facebook.com');

  /// Headers to send with every request (manifest fetch AND every segment
  /// request ExoPlayer makes while playing) so fbcdn.net doesn't reject the
  /// connection with a 403 that surfaces to Flutter as a generic,
  /// message-less "Source error".
  static Map<String, String> headersFor(String url) {
    if (!isFacebookCdn(url)) return const {};
    return {
      'User-Agent': _browserUserAgent,
      'Referer': 'https://www.facebook.com/',
      'Origin': 'https://www.facebook.com',
    };
  }
}
