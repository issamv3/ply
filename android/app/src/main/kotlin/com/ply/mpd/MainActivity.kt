package com.ply.mpd

import android.content.Intent
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.provider.OpenableColumns
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val channelName = "ply/media"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "mux" -> handleMux(call, result)
                "thumbnail" -> handleThumbnail(call, result)
                "getInitialIntent" -> handleGetInitialIntent(result)
                "readTextUri" -> handleReadTextUri(call, result)
                "resolveUriToFilePath" -> handleResolveUriToFilePath(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = extractIntentData(intent)
        if (data != null) {
            channel?.invokeMethod("onIntent", data)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val next = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                (current + 1).coerceAtMost(max)
            } else {
                (current - 1).coerceAtLeast(0)
            }
            // flags = 0 → silent change, no system volume UI
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, next, 0)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun handleGetInitialIntent(result: MethodChannel.Result) {
        result.success(extractIntentData(intent))
    }

    private fun extractIntentData(intent: Intent?): Map<String, String?>? {
        if (intent == null) return null
        val action = intent.action ?: return null
        if (action == Intent.ACTION_MAIN) return null

        return when (action) {
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return null
                val uriStr = uri.toString()
                val mimeType = intent.type
                    ?: try { contentResolver.getType(uri) } catch (_: Exception) { null }
                    ?: guessMime(uriStr)
                val displayName = queryDisplayName(uri)
                mapOf("uri" to uriStr, "mimeType" to mimeType, "displayName" to displayName)
            }
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val streamUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (streamUri != null) {
                    val uriStr = streamUri.toString()
                    val mimeType = intent.type
                        ?: try { contentResolver.getType(streamUri) } catch (_: Exception) { null }
                        ?: guessMime(uriStr)
                    val displayName = queryDisplayName(streamUri)
                    return mapOf("uri" to uriStr, "mimeType" to mimeType, "displayName" to displayName)
                }
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null && text.isNotBlank()) {
                    mapOf("uri" to text, "mimeType" to guessMime(text), "displayName" to null)
                } else null
            }
            else -> null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme != "content") return null
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) cursor.getString(idx) else null
                    } else null
                }
        } catch (_: Exception) { null }
    }

    private fun guessMime(uriOrPath: String): String? {
        val lower = uriOrPath.lowercase()
        return when {
            lower.endsWith(".mpd") -> "application/dash+xml"
            lower.endsWith(".mp4") -> "video/mp4"
            lower.endsWith(".m4v") -> "video/mp4"
            lower.endsWith(".webm") -> "video/webm"
            lower.endsWith(".mkv") -> "video/x-matroska"
            else -> null
        }
    }

    private fun handleResolveUriToFilePath(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        if (uriStr == null) {
            result.success(null)
            return
        }
        try {
            val uri = Uri.parse(uriStr)
            if (uri.scheme != "content") {
                result.success(if (uri.scheme == "file") uri.path else null)
                return
            }
            // Try _data column (works on many devices / older Android)
            val cursor = contentResolver.query(uri, arrayOf("_data"), null, null, null)
            val realPath = cursor?.use {
                if (it.moveToFirst()) {
                    val idx = it.getColumnIndex("_data")
                    if (idx >= 0) it.getString(idx) else null
                } else null
            }
            if (realPath != null && File(realPath).exists()) {
                result.success(realPath)
            } else {
                result.success(null)
            }
        } catch (_: Exception) {
            result.success(null)
        }
    }

    private fun handleReadTextUri(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        if (uriStr == null) {
            result.error("bad_args", "uri required", null)
            return
        }
        try {
            val uri = Uri.parse(uriStr)
            val text = when (uri.scheme) {
                "file" -> {
                    val path = uri.path ?: throw Exception("null path")
                    File(path).readText()
                }
                "content" -> {
                    contentResolver.openInputStream(uri)?.use { stream ->
                        stream.readBytes().toString(Charsets.UTF_8)
                    } ?: throw Exception("null stream")
                }
                else -> throw Exception("unsupported scheme: ${uri.scheme}")
            }
            result.success(text)
        } catch (e: Exception) {
            result.error("read_failed", e.message, null)
        }
    }

    private fun handleMux(call: MethodCall, result: MethodChannel.Result) {
        val videoPath = call.argument<String>("videoPath")
        val audioPath = call.argument<String>("audioPath")
        val outputPath = call.argument<String>("outputPath")
        if (videoPath == null || outputPath == null) {
            result.error("bad_args", "videoPath/outputPath required", null)
            return
        }
        Thread {
            var muxer: MediaMuxer? = null
            val videoExtractor = MediaExtractor()
            val audioExtractor = if (audioPath != null) MediaExtractor() else null
            try {
                val outFile = File(outputPath)
                outFile.parentFile?.mkdirs()
                if (outFile.exists()) outFile.delete()

                muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

                videoExtractor.setDataSource(videoPath)
                var videoTrackIn = -1
                var videoTrackOut = -1
                for (i in 0 until videoExtractor.trackCount) {
                    val fmt = videoExtractor.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("video/")) {
                        videoTrackIn = i
                        videoTrackOut = muxer.addTrack(fmt)
                        break
                    }
                }
                if (videoTrackIn < 0) {
                    runOnUiThread { result.error("mux_failed", "no video track found", null) }
                    return@Thread
                }

                var audioTrackIn = -1
                var audioTrackOut = -1
                if (audioPath != null && audioExtractor != null) {
                    audioExtractor.setDataSource(audioPath)
                    for (i in 0 until audioExtractor.trackCount) {
                        val fmt = audioExtractor.getTrackFormat(i)
                        val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                        if (mime.startsWith("audio/")) {
                            audioTrackIn = i
                            audioTrackOut = muxer.addTrack(fmt)
                            break
                        }
                    }
                }

                muxer.start()

                val bufSize = 1 * 1024 * 1024
                val buf = ByteBuffer.allocate(bufSize)
                val info = MediaCodec.BufferInfo()

                videoExtractor.selectTrack(videoTrackIn)
                while (true) {
                    info.size = videoExtractor.readSampleData(buf, 0)
                    if (info.size < 0) break
                    info.presentationTimeUs = videoExtractor.sampleTime
                    info.flags = videoExtractor.sampleFlags
                    muxer.writeSampleData(videoTrackOut, buf, info)
                    videoExtractor.advance()
                }

                if (audioTrackIn >= 0 && audioTrackOut >= 0 && audioExtractor != null) {
                    audioExtractor.selectTrack(audioTrackIn)
                    while (true) {
                        info.size = audioExtractor.readSampleData(buf, 0)
                        if (info.size < 0) break
                        info.presentationTimeUs = audioExtractor.sampleTime
                        info.flags = audioExtractor.sampleFlags
                        muxer.writeSampleData(audioTrackOut, buf, info)
                        audioExtractor.advance()
                    }
                }

                muxer.stop()
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                try { File(outputPath).delete() } catch (_: Exception) {}
                runOnUiThread { result.error("mux_failed", e.message, null) }
            } finally {
                try { muxer?.release() } catch (_: Exception) {}
                try { videoExtractor.release() } catch (_: Exception) {}
                try { audioExtractor?.release() } catch (_: Exception) {}
            }
        }.start()
    }

    private fun handleThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val videoPath = call.argument<String>("videoPath")
        val outputPath = call.argument<String>("outputPath")
        val timeUs = (call.argument<Number>("timeUs") ?: 1_000_000L).toLong()
        if (videoPath == null || outputPath == null) {
            result.error("bad_args", "videoPath/outputPath required", null)
            return
        }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(videoPath)
            val frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (frame == null) {
                result.error("thumbnail_failed", "no frame extracted", null)
                return
            }
            val targetWidth = 400
            val scale = targetWidth.toFloat() / frame.width.toFloat()
            val targetHeight = (frame.height * scale).toInt().coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(frame, targetWidth, targetHeight, true)

            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()
            FileOutputStream(outFile).use { fos ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 85, fos)
            }

            if (scaled !== frame) frame.recycle()
            scaled.recycle()
            result.success(true)
        } catch (e: Exception) {
            result.error("thumbnail_failed", e.message, null)
        } finally {
            retriever.release()
        }
    }
}
