import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/dash_representation.dart';
import '../providers/settings_provider.dart';
import '../services/cdn_service.dart';
import '../services/dash_parser.dart';
import '../services/download_service.dart';
import '../services/file_service.dart';
import '../services/notification_service.dart';
import '../services/history_service.dart';
import '../services/local_manifest_server.dart';

enum _VideoFit { contain, cover, stretch, r43, r169 }

class PlayerScreen extends StatefulWidget {
  final String title;
  final String videoPath;
  final bool isNetwork;
  final String? mpdContent;
  final bool fbCdnEnabled;
  final bool isDash;
  final Duration? resumeAt;
  final String? historyKey;

  const PlayerScreen({
    super.key,
    this.title = 'Video',
    required this.videoPath,
    required this.isNetwork,
    this.mpdContent,
    this.fbCdnEnabled = false,
    this.isDash = false,
    this.resumeAt,
    this.historyKey,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;
  String? _errorMsg;

  bool _showControls = true;
  bool _isLocked = false;
  bool _isFullScreen = false;
  Timer? _hideTimer;
  Timer? _overlayTimer;

  double _volume = 1.0;
  double _brightness = 0.5;
  double _playbackSpeed = 1.0;
  bool _isLooping = false;
  _VideoFit _videoFit = _VideoFit.contain;

  List<DashRepresentation> _representations = [];
  DashRepresentation? _selectedRep;

  Offset? _dragStart;
  String? _activeGesture;
  double _backDragDx = 0;
  double _gestureStartVolume = 0;
  double _gestureStartBrightness = 0;
  Duration _seekStart = Duration.zero;
  Duration _seekTarget = Duration.zero;
  Duration _accumulatedSeek = Duration.zero;

  bool _showVolumeOverlay = false;
  bool _showBrightnessOverlay = false;
  bool _showSeekOverlay = false;

  bool _isDraggingSlider = false;
  double _sliderValue = 0.0;

  Offset? _doubleTapPos;

  Timer? _sleepTimer;
  int _sleepTimerSeconds = 0;
  bool _sleepTimerActive = false;

  bool _manualLandscapeLeft = true;
  bool _autoFullScreen = false;

  String? _historyKey;
  Timer? _historyTimer;
  bool _downloading = false;
  bool _showRemaining = false;

  final GlobalKey _videoBoundaryKey = GlobalKey();
  bool _thumbnailCaptured = false;
  bool _volumeListenerReady = false;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  DeviceOrientation? _sensorOrientation;
  DeviceOrientation? _pendingSensorOrientation;
  Timer? _sensorDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _parseMpd();
    _initBrightness();
    _initVolume();
    _bootstrapPlayer();
    _initHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyAutoRotate());
  }

  void _startSensorRotation() {
    if (_accelSub != null) return;
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen(_onAccelerometerEvent);
  }

  void _stopSensorRotation() {
    _accelSub?.cancel();
    _accelSub = null;
    _sensorDebounce?.cancel();
    _sensorDebounce = null;
    _pendingSensorOrientation = null;
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!mounted) return;
    if (_isFullScreen && !_autoFullScreen) return;
    if (!context.read<SettingsProvider>().autoRotate) return;

    const flatThreshold = 4.5;
    final x = event.x;
    final y = event.y;
    if (x.abs() < flatThreshold && y.abs() < flatThreshold) return;

    const dominanceRatio = 1.6;
    DeviceOrientation? detected;
    if (x.abs() > y.abs() * dominanceRatio) {
      detected =
          x > 0 ? DeviceOrientation.landscapeLeft : DeviceOrientation.landscapeRight;
    } else if (y.abs() > x.abs() * dominanceRatio) {
      detected =
          y > 0 ? DeviceOrientation.portraitUp : DeviceOrientation.portraitDown;
    }

    final resolved = detected;
    if (resolved == null || resolved == _sensorOrientation) return;

    if (_pendingSensorOrientation != resolved) {
      _pendingSensorOrientation = resolved;
      _sensorDebounce?.cancel();
      _sensorDebounce = Timer(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        if (_isFullScreen && !_autoFullScreen) return;
        if (!context.read<SettingsProvider>().autoRotate) return;
        if (_pendingSensorOrientation != resolved) return;
        _sensorOrientation = resolved;

        final isLandscape = resolved == DeviceOrientation.landscapeLeft ||
            resolved == DeviceOrientation.landscapeRight;

        if (isLandscape) {
          if (!_isFullScreen) {
            _autoFullScreen = true;
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
          }
          await SystemChrome.setPreferredOrientations([resolved]);
          if (mounted) setState(() => _isFullScreen = true);
        } else {
          if (_isFullScreen && _autoFullScreen) {
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            await SystemChrome.setPreferredOrientations([resolved]);
            if (mounted) {
              setState(() {
                _isFullScreen = false;
                _autoFullScreen = false;
              });
            }
          } else {
            await SystemChrome.setPreferredOrientations([resolved]);
          }
        }
      });
    }
  }

  Future<void> _bootstrapPlayer() async {
    String path = widget.videoPath;
    if (widget.isDash && widget.mpdContent != null) {
      // Never trust widget.videoPath's loopback URL here: it may point at
      // a LocalManifestServer instance from a previous PlayerScreen that
      // has since been disposed (every dash player tears the singleton
      // server down in dispose()). This matters most when resuming a DASH
      // video from history — the old http://127.0.0.1:<port>/... URL is
      // dead by then and yields an immediate, message-less "Source error".
      // Republishing the manifest fresh guarantees a live server + URL on
      // every open, whether it's a brand-new play or a history resume.
      final rewrittenMpd = CdnService.rewriteMpdContent(
        widget.mpdContent!,
        fbCdnEnabled: widget.fbCdnEnabled,
      );
      path = await LocalManifestServer.instance.publish(rewrittenMpd);
    }
    await _initPlayer(
      path,
      widget.isNetwork,
      resumeAt: widget.resumeAt,
      isDash: widget.isDash,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-apply the orientation preference whenever the app comes back to the
    // foreground — another app or a system dialog may have reset it.
    if (state == AppLifecycleState.resumed && !_isFullScreen) {
      _applyAutoRotate();
    }
  }

  void _applyAutoRotate() {
    if (!mounted) return;
    if (context.read<SettingsProvider>().autoRotate) {
      // Start from portrait, then let the accelerometer-driven listener
      // (see _startSensorRotation) force the exact orientation the device
      // is physically held in. We don't rely on
      // SCREEN_ORIENTATION_FULL_SENSOR here because on several devices it
      // still silently defers to the system-wide "Auto-rotate" toggle,
      // which makes rotation appear completely broken when that toggle is
      // off — forcing one explicit orientation at a time is always honored.
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      _sensorOrientation = DeviceOrientation.portraitUp;
      _startSensorRotation();
    } else {
      // AutoRotate disabled: lock to portrait so the player stays upright
      // regardless of physical device orientation.
      _stopSensorRotation();
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _initHistory() async {
    _historyKey = widget.historyKey ??
        await HistoryService.instance.upsert(
          title: widget.title,
          videoPath: widget.videoPath,
          isNetwork: widget.isNetwork,
          isDash: widget.isDash,
          fbCdnEnabled: widget.fbCdnEnabled,
          mpdContent: widget.mpdContent,
        );
    _historyTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  void _saveProgress() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _historyKey == null) {
      return;
    }
    final position = ctrl.value.position.inMilliseconds;
    final duration = ctrl.value.duration.inMilliseconds;
    if (duration <= 0) return;
    HistoryService.instance.updateProgress(_historyKey!, position, duration);
  }

  void _parseMpd() {
    if (widget.mpdContent != null) {
      try {
        final reps = DashParser.parse(widget.mpdContent!);
        if (mounted) setState(() => _representations = reps);
      } catch (_) {}
    }
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().current;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _initVolume() async {
    try {
      FlutterVolumeController.updateShowSystemUI(false);
      final vol = await FlutterVolumeController.getVolume();
      if (vol != null && mounted) setState(() => _volume = vol);
      FlutterVolumeController.addListener((newVol) {
        if (!mounted) return;
        // The first callback fires immediately on registration with the
        // current volume — skip the overlay for that initial call.
        if (!_volumeListenerReady) {
          _volumeListenerReady = true;
          setState(() => _volume = newVol);
          return;
        }
        setState(() {
          _volume = newVol;
          _showVolumeOverlay = true;
        });
        _controller?.setVolume(newVol);
        _scheduleOverlayHide();
      });
    } catch (_) {}
  }

  Future<void> _initPlayer(String path, bool isNetwork,
      {Duration? resumeAt, bool autoPlay = true, bool isDash = false}) async {
    if (mounted) setState(() => _isLoading = true);

    // DASH manifests are always served as http://127.0.0.1:PORT/... (pasted
    // XML) or as the original http(s) URL — never as a file:// path. This
    // matters because ExoPlayer resolves BaseURL/SegmentTemplate paths
    // inside the manifest relative to the manifest's own URI scheme, and
    // some builds reject a non-http(s) URI for a DASH MediaItem outright
    // (immediate "Source error"). Only apply CDN rewriting to genuine
    // remote network paths, not to our own loopback manifest URL.
    final isLoopbackManifest = path.startsWith('http://127.0.0.1');
    final resolvedPath = isNetwork && !isLoopbackManifest
        ? CdnService.rewrite(path, fbCdnEnabled: widget.fbCdnEnabled)
        : path;

    // fbcdn.net edges reject plain HTTP-client requests (ExoPlayer's default
    // User-Agent, no Referer) with a 403 even when the signed URL itself is
    // valid — this is what actually produces the message-less "Source
    // error" seen on-device even though the exact same manifest plays fine
    // in a browser via dash.js. video_player forwards these headers to
    // EVERY request the player makes: the manifest fetch AND every segment
    // fetch afterwards (they all go through the same DataSource.Factory
    // under the hood), so this fixes both, not just the manifest load.
    // mpdContent (used for the widget.videoPath before local publishing)
    // is what carries the *original* remote URL for header-matching
    // purposes even when resolvedPath now points at our loopback server.
    final headerSourceUrl =
        isLoopbackManifest ? (widget.videoPath) : resolvedPath;
    final headers = CdnService.headersFor(headerSourceUrl);

    VideoPlayerController ctrl;
    if (isDash) {
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(resolvedPath),
        formatHint: VideoFormat.dash,
        httpHeaders: headers,
      );
    } else if (isNetwork) {
      ctrl = VideoPlayerController.networkUrl(
        Uri.parse(resolvedPath),
        httpHeaders: headers,
      );
    } else if (resolvedPath.startsWith('content://')) {
      ctrl = VideoPlayerController.contentUri(Uri.parse(resolvedPath));
    } else {
      ctrl = VideoPlayerController.file(File(resolvedPath));
    }

    try {
      await ctrl.initialize();
      ctrl.addListener(_onPlayerUpdate);
      await ctrl.setVolume(_volume);
      await ctrl.setPlaybackSpeed(_playbackSpeed);
      await ctrl.setLooping(_isLooping);

      if (resumeAt != null) await ctrl.seekTo(resumeAt);

      if (mounted) {
        _controller?.removeListener(_onPlayerUpdate);
        _controller?.dispose();
        setState(() {
          _controller = ctrl;
          _isInitialized = true;
          _isLoading = false;
        });
        if (autoPlay) {
          _controller!.play();
          WakelockPlus.enable().ignore();
          _startHideTimer();
        }
      } else {
        ctrl.dispose();
      }
    } catch (e) {
      ctrl.dispose();
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null) return;
    final val = _controller!.value;

    if (val.hasError && _errorMsg == null) {
      setState(() => _errorMsg = val.errorDescription ?? 'Playback error');
      return;
    }

    if (!_isDraggingSlider &&
        val.isInitialized &&
        val.duration.inMilliseconds > 0) {
      _sliderValue =
          val.position.inMilliseconds / val.duration.inMilliseconds;
    }

    if (val.isCompleted && !_isLooping) {
      setState(() => _showControls = true);
      _hideTimer?.cancel();
      WakelockPlus.disable().ignore();
    }

    if (!_thumbnailCaptured &&
        val.isPlaying &&
        val.position > const Duration(milliseconds: 400)) {
      _captureThumbnail();
    }

    setState(() {});
  }

  /// Saves a still frame of the video as its history thumbnail — but only
  /// the very first time this video is ever played (see
  /// [HistoryService.setThumbnailIfAbsent]).
  Future<void> _captureThumbnail() async {
    if (_historyKey == null || _thumbnailCaptured) return;
    _thumbnailCaptured = true;
    try {
      final existing = await HistoryService.instance.loadAll();
      final already = existing.any((e) =>
          e.key == _historyKey &&
          (e.thumbnailPath?.isNotEmpty ?? false) &&
          File(e.thumbnailPath!).existsSync());
      if (already) return;

      final boundary = _videoBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 0.6);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final thumbsDir = Directory('${dir.path}/thumbnails');
      if (!await thumbsDir.exists()) await thumbsDir.create(recursive: true);
      final file = File('${thumbsDir.path}/$_historyKey.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await HistoryService.instance
          .setThumbnailIfAbsent(_historyKey!, file.path);
    } catch (_) {
      _thumbnailCaptured = false;
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false) && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      _flashLockedMessage();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _flashLockedMessage() {
    setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      WakelockPlus.disable().ignore();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      _controller!.play();
      WakelockPlus.enable().ignore();
      _startHideTimer();
    }
    setState(() {});
  }

  void _seekRelative(int seconds) {
    if (_controller == null) return;
    final current = _controller!.value.position;
    final duration = _controller!.value.duration;
    final targetMs = (current.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds);
    _controller!.seekTo(Duration(milliseconds: targetMs));
    _startHideTimer();
  }

  Future<void> _switchQuality(DashRepresentation? rep) async {
    final pos = _controller?.value.position;
    final wasPlaying = _controller?.value.isPlaying ?? false;
    Navigator.of(context).pop();
    setState(() {
      _selectedRep = rep;
      _isInitialized = false;
    });

    if (rep == null) {
      String path = widget.videoPath;
      if (widget.isDash && widget.mpdContent != null) {
        // Same reasoning as _bootstrapPlayer: republish rather than trust
        // widget.videoPath, which may be a dead loopback URL when this
        // screen was opened by resuming a history entry.
        final rewrittenMpd = CdnService.rewriteMpdContent(
          widget.mpdContent!,
          fbCdnEnabled: widget.fbCdnEnabled,
        );
        path = await LocalManifestServer.instance.publish(rewrittenMpd);
      }
      await _initPlayer(
        path,
        widget.isNetwork,
        resumeAt: pos,
        autoPlay: wasPlaying,
        isDash: widget.isDash,
      );
      return;
    }

    if (widget.mpdContent != null) {
      final rewrittenForSub = CdnService.rewriteMpdContent(
        widget.mpdContent!,
        fbCdnEnabled: widget.fbCdnEnabled,
      );
      final subMpd = DashParser.generateSubMpd(rewrittenForSub, rep.id);
      // Republished over the same loopback HTTP server as the full
      // manifest — never written to a file:// path.
      final subUrl = await FileService().saveMpdToFile(subMpd);
      await _initPlayer(subUrl, true,
          resumeAt: pos, autoPlay: wasPlaying, isDash: true);
    } else {
      await _initPlayer(rep.baseUrl, true,
          resumeAt: pos, autoPlay: wasPlaying);
    }
  }

  Future<void> _startDownloadFlow() async {
    if (widget.mpdContent != null) {
      final mpdTitle = DashParser.extractTitle(widget.mpdContent!);
      if (mpdTitle != null && mounted) {
        await _runDownload(mpdTitle);
        return;
      }
    }

    if (widget.title.isNotEmpty && !widget.title.contains('://')) {
      await _runDownload(widget.title);
      return;
    }

    final l10n = AppLocalizations.of(context);
    final titleCtrl = TextEditingController(text: widget.title);

    final confirmed = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: Text(l10n.downloadTitlePrompt,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.downloadTitleHint,
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.primary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.downloadCancel,
                style: const TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(
                titleCtrl.text.trim().isEmpty
                    ? widget.title
                    : titleCtrl.text.trim()),
            child: Text(l10n.downloadStart),
          ),
        ],
      ),
    );

    if (confirmed == null || !mounted) return;
    await _runDownload(confirmed);
  }

  Future<void> _runDownload(String title) async {
    if (!mounted) return;

    await NotificationService.requestPermission();

    if (!mounted) return;
    setState(() => _downloading = true);

    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.downloadStarted),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 3),
      ),
    );

    final durationMs = _controller?.value.duration.inMilliseconds;

    String? thumbnailPath;
    final key = _historyKey;
    if (key != null) {
      try {
        final entries = await HistoryService.instance.loadAll();
        final entry = entries.firstWhere((e) => e.key == key);
        final p = entry.thumbnailPath;
        if (p != null && p.isNotEmpty && File(p).existsSync()) {
          thumbnailPath = p;
        }
      } catch (_) {}
    }

    DownloadService.startBackground(
      title: title,
      isDash: widget.isDash,
      isNetwork: widget.isNetwork,
      videoPath: widget.videoPath,
      mpdContent: widget.mpdContent,
      selectedVideoRep: _selectedRep,
      fbCdnEnabled: widget.fbCdnEnabled,
      durationMs: durationMs,
      thumbnailPath: thumbnailPath,
    ).whenComplete(() {
      if (mounted) setState(() => _downloading = false);
    });
  }

  Future<void> _toggleFullScreen() async {
    final goingFull = !_isFullScreen;
    _autoFullScreen = false;

    if (goingFull) {
      _stopSensorRotation();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // When exiting fullscreen restore the correct orientation based on the
      // autoRotate setting — do NOT always lock to portrait because that would
      // silently break auto-rotate for the rest of the session.
      if (mounted && context.read<SettingsProvider>().autoRotate) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
        _sensorOrientation = DeviceOrientation.portraitUp;
        _startSensorRotation();
      } else {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    }
    if (mounted) setState(() => _isFullScreen = goingFull);
  }

  Future<void> _rotateManual() async {
    if (_isFullScreen) {
      _manualLandscapeLeft = !_manualLandscapeLeft;
      await SystemChrome.setPreferredOrientations([
        _manualLandscapeLeft
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _toggleFullScreen();
    }
  }

  Future<void> _updateVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _volume = clamped;
      _showVolumeOverlay = true;
    });
    try {
      await FlutterVolumeController.setVolume(clamped);
    } catch (_) {}
    _controller?.setVolume(clamped);
    _scheduleOverlayHide();
  }

  Future<void> _updateBrightness(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _brightness = clamped;
      _showBrightnessOverlay = true;
    });
    try {
      await ScreenBrightness().setScreenBrightness(clamped);
    } catch (_) {}
    _scheduleOverlayHide();
  }

  void _scheduleOverlayHide() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _showVolumeOverlay = false;
          _showBrightnessOverlay = false;
        });
      }
    });
  }

  void _handlePanStart(DragStartDetails d) {
    if (_isLocked) return;
    _dragStart = d.localPosition;
    _activeGesture = null;
    _gestureStartVolume = _volume;
    _gestureStartBrightness = _brightness;
    if (_controller != null && _controller!.value.isInitialized) {
      _seekStart = _controller!.value.position;
      _accumulatedSeek = Duration.zero;
    }
    _hideTimer?.cancel();
  }

  void _handlePanUpdate(DragUpdateDetails d) {
    if (_isLocked || _dragStart == null) return;
    final size = MediaQuery.of(context).size;
    final totalDelta = d.localPosition - _dragStart!;

    if (_activeGesture == null) {
      if (totalDelta.distance < 10) return;
      final isRtl = Directionality.of(context) == TextDirection.rtl;
      final movesForward = isRtl ? totalDelta.dx < 0 : totalDelta.dx > 0;
      final isHorizontal = totalDelta.dx.abs() > totalDelta.dy.abs() * 0.6;
      if (movesForward && isHorizontal) {
        _activeGesture = 'back';
      } else if (totalDelta.dx.abs() > totalDelta.dy.abs() * 1.4) {
        _activeGesture = 'seek';
      } else if (_dragStart!.dx >= size.width / 2) {
        _activeGesture = 'volume';
      } else {
        _activeGesture = 'brightness';
      }
    }

    switch (_activeGesture) {
      case 'back':
        _backDragDx = totalDelta.dx.abs();
        break;
      case 'volume':
        final newVol =
            _gestureStartVolume - (totalDelta.dy / size.height * 2.5);
        _updateVolume(newVol);
        break;
      case 'brightness':
        final newBrt =
            _gestureStartBrightness - (totalDelta.dy / size.height * 2.5);
        _updateBrightness(newBrt);
        break;
      case 'seek':
        final secs = (totalDelta.dx / size.width * 120).round();
        _accumulatedSeek = Duration(seconds: secs);
        final raw = _seekStart + _accumulatedSeek;
        final dur = _controller?.value.duration ?? Duration.zero;
        final rawMs = raw.inMilliseconds;
        final clampedMs = rawMs < 0
            ? 0
            : rawMs > dur.inMilliseconds
                ? dur.inMilliseconds
                : rawMs;
        _seekTarget = Duration(milliseconds: clampedMs);
        setState(() => _showSeekOverlay = true);
        break;
    }
  }

  void _handlePanEnd(DragEndDetails _) {
    if (_activeGesture == 'seek' && _controller != null) {
      _controller!.seekTo(_seekTarget);
    }
    final shouldPop = _activeGesture == 'back' &&
        _backDragDx > MediaQuery.of(context).size.width * 0.22;
    setState(() {
      _activeGesture = null;
      _dragStart = null;
      _backDragDx = 0;
      _showSeekOverlay = false;
      _showVolumeOverlay = false;
      _showBrightnessOverlay = false;
    });
    _overlayTimer?.cancel();
    _startHideTimer();
    if (shouldPop && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _handleDoubleTapDown(TapDownDetails d) {
    _doubleTapPos = d.localPosition;
  }

  void _handleDoubleTap() {
    if (_isLocked) return;
    final size = MediaQuery.of(context).size;
    final x = _doubleTapPos?.dx ?? size.width / 2;
    _seekRelative(x < size.width / 2 ? -10 : 10);
    setState(() {});
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _controller?.setLooping(_isLooping);
  }

  void _startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimerSeconds = minutes * 60;
    _sleepTimerActive = true;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _sleepTimerSeconds--);
      if (_sleepTimerSeconds <= 0) {
        t.cancel();
        _sleepTimerActive = false;
        _controller?.pause();
        WakelockPlus.disable().ignore();
        setState(() => _showControls = true);
      }
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    setState(() {
      _sleepTimerActive = false;
      _sleepTimerSeconds = 0;
    });
  }

  void _showQualitySheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHandle(),
              const SizedBox(height: 8),
              _SheetTitle(title: l10n.selectQuality),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _QualityOption(
                        label: l10n.auto,
                        sublabel: null,
                        selected: _selectedRep == null,
                        onTap: () => _switchQuality(null),
                      ),
                      ..._representations.map((rep) => _QualityOption(
                            label: rep.qualityLabel,
                            sublabel: rep.bitrateLabel,
                            selected: _selectedRep?.id == rep.id,
                            onTap: () => _switchQuality(rep),
                          )),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    final l10n = AppLocalizations.of(context);
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHandle(),
                const SizedBox(height: 8),
                _SheetTitle(title: l10n.selectSpeed),
                const SizedBox(height: 8),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: speeds.map((s) {
                      final selected = _playbackSpeed == s;
                      return ChoiceChip(
                        label: Text('${s}×'),
                        selected: selected,
                        onSelected: (_) {
                          Navigator.of(ctx).pop();
                          setState(() => _playbackSpeed = s);
                          _controller?.setPlaybackSpeed(s);
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAspectSheet() {
    final l10n = AppLocalizations.of(context);
    final options = [
      (_VideoFit.contain, LucideIcons.minimize2, l10n.aspectContain),
      (_VideoFit.cover, LucideIcons.maximize2, l10n.aspectCover),
      (_VideoFit.stretch, LucideIcons.moveHorizontal, l10n.aspectStretch),
      (_VideoFit.r43, LucideIcons.square, l10n.aspect43),
      (_VideoFit.r169, LucideIcons.monitor, l10n.aspect169),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHandle(),
                const SizedBox(height: 8),
                _SheetTitle(title: l10n.aspectRatio),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        ...options.map((o) {
                          final (fit, icon, label) = o;
                          final sel = _videoFit == fit;
                          return ListTile(
                            leading: Icon(icon,
                                color: sel
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                size: 20),
                            title: Text(
                              label,
                              style: TextStyle(
                                color: sel ? scheme.primary : scheme.onSurface,
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.normal,
                              ),
                            ),
                            trailing: sel
                                ? Icon(LucideIcons.check,
                                    color: scheme.primary, size: 18)
                                : null,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              setState(() => _videoFit = fit);
                            },
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSleepTimerSheet() {
    final l10n = AppLocalizations.of(context);
    const options = [5, 10, 15, 20, 30, 60];
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetHandle(),
              const SizedBox(height: 8),
              _SheetTitle(title: l10n.sleepTimer),
              const SizedBox(height: 4),
              if (_sleepTimerActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    icon: Icon(LucideIcons.x,
                        color: scheme.error, size: 16),
                    label: Text(l10n.sleepTimerCancel,
                        style: TextStyle(color: scheme.error)),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _cancelSleepTimer();
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: options.map((min) {
                    final sel =
                        _sleepTimerActive && _sleepTimerSeconds ~/ 60 == min;
                    return ChoiceChip(
                      avatar: const Icon(LucideIcons.timer, size: 14),
                      label: Text('$min min'),
                      selected: sel,
                      onSelected: (_) {
                        Navigator.of(ctx).pop();
                        _startSleepTimer(min);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _fmt(Duration d, {bool showHours = false}) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (showHours || h > 0) {
      return '${h.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }

  String _fmtSleep(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _saveProgress();
    _historyTimer?.cancel();
    _stopSensorRotation();
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    _sleepTimer?.cancel();
    WakelockPlus.disable().ignore();
    ScreenBrightness().resetScreenBrightness().ignore();
    try {
      FlutterVolumeController.removeListener();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    if (widget.mpdContent != null) {
      LocalManifestServer.instance.dispose().ignore();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_isFullScreen,
          bottom: !_isFullScreen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildVideoLayer(),
              _buildGestureLayer(),
              if (_isLoading) _buildLoading(),
              if (_errorMsg != null) _buildError(),
              if (!_isLoading && _errorMsg == null)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControls(scheme),
                  ),
                ),
              AnimatedOpacity(
                opacity: _showVolumeOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: _buildGestureIndicator(
                  icon: _volume < 0.01
                      ? LucideIcons.volumeX
                      : _volume < 0.5
                          ? LucideIcons.volume1
                          : LucideIcons.volume2,
                  value: _volume,
                  alignment: Alignment.centerLeft,
                ),
              ),
              AnimatedOpacity(
                opacity: _showBrightnessOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: _buildGestureIndicator(
                  icon: LucideIcons.sun,
                  value: _brightness,
                  alignment: Alignment.centerRight,
                ),
              ),
              if (_showSeekOverlay) _buildSeekOverlay(),
              if (_isLocked && _showControls) _buildLockedOverlay(scheme),
              if (_sleepTimerActive) _buildSleepTimerBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (!_isInitialized || _controller == null) {
      return const ColoredBox(color: Colors.black);
    }

    final size = _controller!.value.size;

    Widget video;
    switch (_videoFit) {
      case _VideoFit.contain:
        video = Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        );
        break;
      case _VideoFit.cover:
        video = FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(_controller!),
          ),
        );
        break;
      case _VideoFit.stretch:
        video = FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(_controller!),
          ),
        );
        break;
      case _VideoFit.r43:
        video = Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: VideoPlayer(_controller!),
          ),
        );
        break;
      case _VideoFit.r169:
        video = Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: VideoPlayer(_controller!),
          ),
        );
        break;
    }

    return RepaintBoundary(
      key: _videoBoundaryKey,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: SizedBox.expand(key: ValueKey(_videoFit), child: video),
      ),
    );
  }

  Widget _buildGestureLayer() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: const ColoredBox(color: Colors.transparent),
    );
  }

  Widget _buildLoading() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(l10n.loading,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.triangleAlert,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.error,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMsg ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
              onPressed: () {
                setState(() => _errorMsg = null);
                _initPlayer(widget.videoPath, widget.isNetwork);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(ColorScheme scheme) {
    if (_isLocked) return _buildLockedOverlay(scheme);

    final ctrl = _controller;
    final position = ctrl?.value.position ?? Duration.zero;
    final duration = ctrl?.value.duration ?? Duration.zero;
    final isPlaying = ctrl?.value.isPlaying ?? false;
    final isBuffering = ctrl?.value.isBuffering ?? false;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(scheme),
        ),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CircleButton(
                icon: LucideIcons.rotateCcw,
                size: 32,
                onTap: () => _seekRelative(-10),
              ),
              const SizedBox(width: 28),
              _CircleButton(
                icon: isBuffering
                    ? null
                    : isPlaying
                        ? LucideIcons.pause
                        : LucideIcons.play,
                size: 48,
                large: true,
                loading: isBuffering,
                onTap: _togglePlayPause,
              ),
              const SizedBox(width: 28),
              _CircleButton(
                icon: LucideIcons.rotateCw,
                size: 32,
                onTap: () => _seekRelative(10),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomBar(scheme, position, duration),
        ),
      ],
    );
  }

  Widget _buildTopBar(ColorScheme scheme) {
    final qualityLabel = _selectedRep?.qualityLabel ??
        (AppLocalizations.of(context).auto.split(' ').first);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? LucideIcons.arrowRight
                  : LucideIcons.arrowLeft,
              color: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _MarqueeText(
                text: widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
          if (_representations.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(LucideIcons.layers, size: 16),
              label: Text(qualityLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              onPressed: _showQualitySheet,
            ),
          if (widget.isDash)
            IconButton(
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.download,
                      color: Colors.white, size: 20),
              tooltip: AppLocalizations.of(context).download,
              onPressed: _downloading ? null : _startDownloadFlow,
            ),
          IconButton(
            icon: const Icon(LucideIcons.rotateCw, color: Colors.white, size: 20),
            tooltip: AppLocalizations.of(context).rotate,
            onPressed: _rotateManual,
          ),
          IconButton(
            icon: Icon(
              _isLocked ? LucideIcons.lock : LucideIcons.lockOpen,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() => _isLocked = !_isLocked);
              if (_isLocked) {
                _hideTimer?.cancel();
                setState(() => _showControls = false);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
      ColorScheme scheme, Duration position, Duration duration) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _fmt(position),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    trackHeight: 3,
                    activeTrackColor: scheme.primary,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                  ),
                  child: Slider(
                    value: _sliderValue.clamp(0.0, 1.0),
                    onChangeStart: (_) {
                      setState(() => _isDraggingSlider = true);
                      _hideTimer?.cancel();
                    },
                    onChanged: (v) => setState(() => _sliderValue = v),
                    onChangeEnd: (v) {
                      setState(() => _isDraggingSlider = false);
                      if (duration.inMilliseconds > 0) {
                        _controller?.seekTo(Duration(
                          milliseconds: (v * duration.inMilliseconds).round(),
                        ));
                      }
                      _startHideTimer();
                    },
                  ),
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _showRemaining = !_showRemaining),
                child: Text(
                  _showRemaining && duration > Duration.zero
                      ? '-${_fmt(duration - position)}'
                      : _fmt(duration),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _BottomIconBtn(
                icon: LucideIcons.gauge,
                label: '${_playbackSpeed}×',
                onTap: _showSpeedSheet,
              ),
              _BottomIconBtn(
                icon: _isLooping
                    ? LucideIcons.repeat
                    : LucideIcons.repeat,
                label: null,
                active: _isLooping,
                onTap: _toggleLoop,
              ),
              _BottomIconBtn(
                icon: LucideIcons.scanLine,
                label: null,
                onTap: _showAspectSheet,
              ),
              _BottomIconBtn(
                icon: LucideIcons.timer,
                label: _sleepTimerActive ? _fmtSleep(_sleepTimerSeconds) : null,
                active: _sleepTimerActive,
                onTap: _showSleepTimerSheet,
              ),
              const Spacer(),
              Text(
                _fitLabel(l10n),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  _isFullScreen
                      ? LucideIcons.minimize2
                      : LucideIcons.maximize2,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: _toggleFullScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fitLabel(AppLocalizations l10n) {
    switch (_videoFit) {
      case _VideoFit.contain:
        return l10n.aspectContain;
      case _VideoFit.cover:
        return l10n.aspectCover;
      case _VideoFit.stretch:
        return l10n.aspectStretch;
      case _VideoFit.r43:
        return l10n.aspect43;
      case _VideoFit.r169:
        return l10n.aspect169;
    }
  }

  Widget _buildLockedOverlay(ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.topRight,
      child: GestureDetector(
        onDoubleTap: () {
          setState(() {
            _isLocked = false;
            _showControls = true;
          });
          _startHideTimer();
        },
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.lock,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                Text(
                  l10n.doubleTapUnlock,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureIndicator({
    required IconData icon,
    required double value,
    required Alignment alignment,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: EdgeInsets.only(
          left: alignment == Alignment.centerLeft ? 28 : 0,
          right: alignment == Alignment.centerRight ? 28 : 0,
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              width: 6,
              child: RotatedBox(
                quarterTurns: 3,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekOverlay() {
    final isForward = _accumulatedSeek.inMilliseconds >= 0;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isForward ? LucideIcons.fastForward : LucideIcons.rewind,
              color: Colors.white,
              size: 34,
            ),
            const SizedBox(height: 6),
            Text(
              '${isForward ? "+" : "-"}${_accumulatedSeek.inSeconds.abs()}s',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _fmt(_seekTarget),
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTimerBadge() {
    return Positioned(
      top: 60,
      right: 16,
      child: GestureDetector(
        onTap: _showSleepTimerSheet,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _sleepTimerSeconds <= 60
                  ? Colors.orangeAccent.withOpacity(0.6)
                  : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.timer,
                color: _sleepTimerSeconds <= 60
                    ? Colors.orangeAccent
                    : Colors.white70,
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                _fmtSleep(_sleepTimerSeconds),
                style: TextStyle(
                  color: _sleepTimerSeconds <= 60
                      ? Colors.orangeAccent
                      : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomIconBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool active;

  const _BottomIconBtn({
    required this.icon,
    required this.onTap,
    this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 17),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(label!,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String title;
  const _SheetTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData? icon;
  final double size;
  final bool large;
  final bool loading;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.large = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final dim = large ? 72.0 : 52.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: dim,
        height: dim,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(large ? 0.5 : 0.35),
          border: Border.all(
              color: Colors.white.withOpacity(large ? 0.2 : 0.12), width: 1.5),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                ),
              )
            : Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}

class _QualityOption extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;

  const _QualityOption({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(
        selected ? LucideIcons.checkCircle : LucideIcons.circle,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          color: selected ? scheme.primary : scheme.onSurface,
        ),
      ),
      subtitle: sublabel != null
          ? Text(sublabel!,
              style:
                  TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))
          : null,
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText({required this.text, this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final _sc = ScrollController();
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  void didUpdateWidget(_MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _scrolling = false;
      if (_sc.hasClients) _sc.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
    }
  }

  void _maybeStart() {
    if (!mounted || !_sc.hasClients) return;
    if (_sc.position.maxScrollExtent > 0 && !_scrolling) {
      _scrolling = true;
      Future.delayed(const Duration(milliseconds: 2000), _scroll);
    }
  }

  Future<void> _scroll() async {
    if (!mounted || !_sc.hasClients) return;
    final max = _sc.position.maxScrollExtent;
    if (max <= 0) {
      _scrolling = false;
      return;
    }
    await _sc.animateTo(max,
        duration: Duration(milliseconds: (max * 28).round()),
        curve: Curves.linear);
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted || !_sc.hasClients) return;
    _sc.jumpTo(0);
    await Future.delayed(const Duration(milliseconds: 1200));
    _scroll();
  }

  @override
  void dispose() {
    _scrolling = false;
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _sc,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text,
          style: widget.style, maxLines: 1, softWrap: false),
    );
  }
}
