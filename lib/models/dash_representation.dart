class DashRepresentation {
  final String id;
  final String baseUrl;
  final int bandwidth;
  final int width;
  final int height;
  final String contentType;
  final String qualityLabel;

  const DashRepresentation({
    required this.id,
    required this.baseUrl,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.contentType,
    required this.qualityLabel,
  });

  String get bitrateLabel {
    if (bandwidth < 1000000) {
      return '${(bandwidth / 1000).toStringAsFixed(0)} kbps';
    }
    return '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps';
  }

  String get fullLabel => '$qualityLabel  ($bitrateLabel)';
}
