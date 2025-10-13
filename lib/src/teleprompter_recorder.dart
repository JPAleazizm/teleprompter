import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart' hide ImageFormat;
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teleprompter/src/cache_cleaner.dart';
import 'package:teleprompter/src/camera_base.dart';
import 'package:teleprompter/src/recorded_takes_thumbnails.dart';
import 'package:teleprompter/src/settings_teleprompter.dart';
import 'package:teleprompter/src/teleprompter_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/services.dart';

/// Full-screen teleprompter UI with camera preview and recording controls.
///
/// `TeleprompterPage` shows editable text (read-only during recording), a
/// live camera preview, recording controls and the ability to review and
/// concatenate recorded takes into a final video file. It calls
/// `onVideoReady` when the final concatenated video is available.
class TeleprompterPage extends StatefulWidget {
  /// Creates a teleprompter page initialized with [text].
  ///
  /// [maxDurationSeconds] caps the total allowed recording time (optional).
  /// [onVideoReady] is called with the final `XFile` when the output video is
  /// ready. The callback may return a `Future` if the consumer needs to run
  /// async work (for example uploading) — the widget awaits it but will not
  /// fail if the callback throws.
  const TeleprompterPage({
    super.key,
    required this.text,
    this.maxDurationSeconds,
    this.onVideoReady,
  });

  /// Initial teleprompter text.
  final String text;

  /// Optional maximum total recording time in seconds.
  final int? maxDurationSeconds;

  /// Optional callback invoked when the final video file is produced.
  ///
  /// Receives the resulting `XFile` and may return a `Future`.
  final FutureOr<void> Function(XFile finalVideo)? onVideoReady;

  @override
  State<TeleprompterPage> createState() {
    return _TeleprompterPageState();
  }
}

class _TeleprompterPageState extends State<TeleprompterPage>
    with SingleTickerProviderStateMixin, CameraBase, CacheCleanerMixin {
  late final ScrollController _scrollController;
  late final textEditingController = TextEditingController(text: widget.text);
  late final AnimationController _scrollAnimationController;
  late final Future<void> _initializeCameraFuture;

  final _isPlayingNotifier = ValueNotifier<bool>(true);
  final _isRecordingNotifier = ValueNotifier<bool>(false);
  final _cardPosition = ValueNotifier<Offset>(const Offset(16, 100));
  final _show = ValueNotifier<bool>(true);
  final _recordedTakes = ValueNotifier<List<XFile>>([]);

  final _currentTotalDurationN = ValueNotifier<double>(0.0);
  final _currentRecordingDurationN = ValueNotifier<double>(0.0);

  TextStyle? _cachedStyle;
  String? _cFont;
  int? _cSize;
  Color? _cColor;

  late final Color _glassFill, _glassBorder, _chipBg, _chipBorder;

  Color colorText = Colors.white;
  int sizeText = 18;
  int speedSeconds = 30;
  String fontName = 'Quicksand';
  bool isOnSetting = true;

  double _currentTotalDuration = 0.0;
  double _currentRecordingDuration = 0.0;
  DateTime? _recordingStartTime;

  double _savedOffset = 0.0;

  final Map<String, double> _recordedDurations = {};
  DateTime _lastTick = DateTime.now();

  int? get _maxDurationSeconds => widget.maxDurationSeconds;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    _glassFill = Colors.white.withAlpha(20);
    _glassBorder = Colors.white.withAlpha(45);
    _chipBg = Colors.white.withAlpha(45);
    _chipBorder = Colors.white.withAlpha(71);

    _scrollController = ScrollController();

    _scrollAnimationController =
        AnimationController(
            vsync: this,
            duration: Duration(seconds: speedSeconds),
          )
          ..addListener(() async {
            if (!mounted) return;

            if (_scrollController.hasClients) {
              final progress = _scrollAnimationController.value.clamp(0.0, 1.0);
              final maxExtent = _scrollController.position.maxScrollExtent;
              final targetOffset = maxExtent * progress;
              if (_isRecordingNotifier.value) {
                if ((_scrollController.offset - targetOffset).abs() > 0.5) {
                  _scrollController.jumpTo(targetOffset);
                }
              }
            }

            if (_isRecordingNotifier.value && _recordingStartTime != null) {
              final now = DateTime.now();
              if (now.difference(_lastTick).inMilliseconds >= 100) {
                _lastTick = now;
                _currentRecordingDuration =
                    now.difference(_recordingStartTime!).inMicroseconds / 1e6;
                _currentRecordingDurationN.value = _currentRecordingDuration;

                final max = _maxDurationSeconds;
                if (max != null &&
                    (_currentTotalDuration + _currentRecordingDuration) >=
                        max) {
                  await stopRecording();
                  _showTimeLimitReachedDialog();
                }
              }
            }
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(
                  _scrollController.position.maxScrollExtent,
                );
              }
            }
          });

    _initializeCameraFuture = initializeCamera().then(
      (_) => initializeZoomLimits(),
    );

    // Listen to shared settings
    TeleprompterSettings.notifier.addListener(_onSettingsChanged);
    // apply initial settings
    _applySettings(TeleprompterSettings.value);
  }

  void _onSettingsChanged() {
    final s = TeleprompterSettings.value;
    _applySettings(s);
  }

  void _applySettings(TeleprompterSettingsData s) {
    setState(() {
      speedSeconds = s.speedSeconds;
      fontName = s.fontName;
      sizeText = s.fontSize;
      colorText = s.fontColor;
      // update animation duration safely
      updateScrollSpeed(speedSeconds);
    });
  }

  double _currentOffset() {
    if (!_scrollController.hasClients) return _savedOffset;
    final max = _scrollController.position.maxScrollExtent;
    return _scrollController.offset.clamp(0.0, max);
  }

  double _currentProgressFromOffset(double offset) {
    if (!_scrollController.hasClients) return 0.0;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return 0.0;
    return (offset / max).clamp(0.0, 1.0);
  }

  void _restoreOffset() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final target = _savedOffset.clamp(0.0, max);
    _scrollController.jumpTo(target);
  }

  Future<void> startRecording() async {
    try {
      if (_maxDurationSeconds != null &&
          _currentTotalDuration >= _maxDurationSeconds!) {
        HapticFeedback.vibrate();

        _showTimeLimitReachedDialog();
        return;
      }

      FocusScope.of(context).unfocus();

      _recordingStartTime = DateTime.now();
      _currentRecordingDuration = 0.0;
      _currentRecordingDurationN.value = 0.0;

      final startProgress = _currentProgressFromOffset(_currentOffset());

      _scrollAnimationController.forward(from: startProgress);
      await cameraController.startVideoRecording();
      _isRecordingNotifier.value = true;

      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOffset());
    } catch (e) {
      HapticFeedback.vibrate();

      debugPrint('Erro ao iniciar gravação: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      _savedOffset = _currentOffset();
      _scrollAnimationController.stop();

      final file = await cameraController.stopVideoRecording();
      _isRecordingNotifier.value = false;

      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOffset());

      if (_recordingStartTime != null) {
        _currentRecordingDuration =
            DateTime.now().difference(_recordingStartTime!).inMicroseconds /
            1e6;
        _currentRecordingDurationN.value = _currentRecordingDuration;
      }

      final duration = _currentRecordingDuration;

      _recordingStartTime = null;
      _currentRecordingDuration = 0.0;
      _currentRecordingDurationN.value = 0.0;

      _recordedTakes.value = [..._recordedTakes.value, file];
      _recordedDurations[file.path] = duration;

      _updateCurrentTotalDuration();

      debugPrint(
        'Take gravado: ${file.path} (${duration.toStringAsFixed(2)}s)',
      );
    } catch (e) {
      HapticFeedback.vibrate();

      debugPrint('Erro ao parar gravação: $e');
    }
  }

  void updateScrollSpeed(int newSpeedSeconds) {
    speedSeconds = newSpeedSeconds;
    final progress = _scrollAnimationController.value;
    _scrollAnimationController.duration = Duration(seconds: speedSeconds);
    if (_isRecordingNotifier.value) {
      _scrollAnimationController.forward(from: progress);
    }
  }

  TextStyle _getFontStyle() {
    if (_cachedStyle != null &&
        _cFont == fontName &&
        _cSize == sizeText &&
        _cColor == colorText) {
      return _cachedStyle!;
    }

    const subtleShadows = <Shadow>[
      Shadow(color: Color(0x59000000), blurRadius: 2.0, offset: Offset(0, 1)),
      Shadow(color: Color(0x1E000000), blurRadius: 6.0),
    ];

    final fallback = GoogleFonts.quicksand(
      fontSize: sizeText.toDouble(),
      color: colorText,
      fontWeight: FontWeight.w700,
      height: 1.4,
      letterSpacing: 0.0,
      shadows: subtleShadows,
    );

    TextStyle style;
    try {
      style = GoogleFonts.getFont(
        fontName,
        fontSize: sizeText.toDouble(),
        color: colorText,
        fontWeight: FontWeight.w700,
        height: 1.4,
        letterSpacing: 0.0,
        shadows: subtleShadows,
      );
    } catch (_) {
      style = fallback;
    }

    _cachedStyle = style;
    _cFont = fontName;
    _cSize = sizeText;
    _cColor = colorText;
    return style;
  }

  Future<void> _showCountdownPopup(BuildContext context) async {
    int countdown = 3;
    final countdownNotifier = ValueNotifier<int>(countdown);
    late Timer timer;

    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Contagem',
      barrierColor: Colors.transparent,
      pageBuilder: (context, _, _) {
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          countdown--;
          if (countdown < 0) {
            t.cancel();
            Navigator.pop(context);
          } else {
            countdownNotifier.value = countdown;
          }
        });

        return SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(
              child: ValueListenableBuilder<int>(
                valueListenable: countdownNotifier,
                builder: (_, value, _) {
                  return Text(
                    '$value',
                    style: GoogleFonts.quicksand(
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: const [
                        Shadow(blurRadius: 10, color: Colors.black),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ).then((_) {
      timer.cancel();
      countdownNotifier.dispose();
    });
  }

  void _updateCurrentTotalDuration() {
    _currentTotalDuration = _recordedDurations.entries
        .where(
          (entry) => _recordedTakes.value.any((file) => file.path == entry.key),
        )
        .map((entry) => entry.value)
        .fold(0.0, (a, b) => a + b);
    _currentTotalDurationN.value = _currentTotalDuration;
  }

  Future<String?> concatenateVideos() async {
    if (_recordedTakes.value.isEmpty) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final outputPath =
        '${appDir.path}/video_final_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final listFile = File('${appDir.path}/inputs.txt');
    final sb = StringBuffer();

    for (var take in _recordedTakes.value) {
      sb.writeln("file '${take.path.replaceAll("'", "'\\''")}'");
    }
    await listFile.writeAsString(sb.toString());

    final command = '-f concat -safe 0 -i ${listFile.path} -c copy $outputPath';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      await clearAppCache();
      return outputPath;
    } else {
      return null;
    }
  }

  Future<void> finishAndReturnFinalVideo() async {
    final finalVideoPath = await concatenateVideos();

    if (finalVideoPath != null) {
      HapticFeedback.lightImpact();

      final finalFile = XFile(finalVideoPath);

      // Notify consumer if provided. If it's async, await it but don't fail the flow.
      try {
        final cb = widget.onVideoReady;
        if (cb != null) {
          final result = cb(finalFile);
          if (result is Future) {
            await result;
          }
        }
      } catch (_) {
        // Ignore callback errors so it doesn't break UI flow
      }

      if (!mounted) return;
      Navigator.pop(context, finalFile);
    } else {
      _messageFailed();
    }
  }

  void _messageFailed() {
    HapticFeedback.vibrate();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        content: Text(
          'Erro ao concatenar vídeos',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showTimeLimitReachedDialog() {
    HapticFeedback.vibrate();

    final maxSeconds = _maxDurationSeconds ?? 0;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Limite de tempo atingido',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Você atingiu o limite máximo de $maxSeconds segundos de vídeo. A gravação foi interrompida automaticamente.',
          style: GoogleFonts.quicksand(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.quicksand(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FutureBuilder<void>(
          future: _initializeCameraFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.blue),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Erro ao abrir a câmera',
                  style: GoogleFonts.quicksand(),
                ),
              );
            }

            final size = MediaQuery.sizeOf(context);
            final scale =
                1 /
                (cameraController.value.aspectRatio *
                    MediaQuery.sizeOf(context).aspectRatio);

            return Stack(
              children: [
                RepaintBoundary(
                  child: Center(
                    child: Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        onScaleStart: (_) {
                          HapticFeedback.lightImpact();

                          baseZoom = currentZoom;
                        },
                        onScaleUpdate: (details) async {
                          double newZoom = baseZoom * details.scale;
                          newZoom = newZoom.clamp(minZoom, maxZoom);
                          if ((newZoom - currentZoom).abs() > 0.03) {
                            currentZoom = newZoom;
                            await cameraController.setZoomLevel(newZoom);
                          }
                        },
                        onScaleEnd: (_) {
                          HapticFeedback.selectionClick();
                        },
                        child: CameraPreview(cameraController),
                      ),
                    ),
                  ),
                ),

                ValueListenableBuilder<bool>(
                  valueListenable: _show,
                  builder: (context, isVisible, _) {
                    if (!isVisible) return const SizedBox.shrink();
                    return ValueListenableBuilder<Offset>(
                      valueListenable: _cardPosition,
                      builder: (context, pos, _) {
                        return Positioned(
                          left: pos.dx,
                          top: pos.dy,
                          child: GestureDetector(
                            onPanStart: (_) {
                              HapticFeedback.lightImpact();
                            },
                            onPanUpdate: (details) =>
                                _cardPosition.value += details.delta,
                            onPanEnd: (_) {
                              HapticFeedback.selectionClick();
                            },
                            child: RepaintBoundary(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 8,
                                        sigmaY: 8,
                                      ),
                                      child: Container(
                                        width: size.width - 32,
                                        constraints: const BoxConstraints(
                                          minHeight: 110,
                                          maxHeight: 260,
                                        ),
                                        padding: const EdgeInsets.fromLTRB(
                                          18,
                                          16,
                                          18,
                                          16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _glassFill,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: _glassBorder,
                                          ),
                                        ),
                                        child: ValueListenableBuilder<bool>(
                                          valueListenable: _isRecordingNotifier,
                                          builder: (context, isRec, _) {
                                            // ÚNICO scrollable externo, mesmo controller/offset
                                            return SingleChildScrollView(
                                              controller: _scrollController,
                                              physics: isRec
                                                  ? const NeverScrollableScrollPhysics()
                                                  : const BouncingScrollPhysics(),
                                              child: TextField(
                                                controller:
                                                    textEditingController,
                                                readOnly: isRec,
                                                showCursor: !isRec,
                                                enableInteractiveSelection:
                                                    !isRec,
                                                enableSuggestions: !isRec,
                                                scrollPhysics:
                                                    const NeverScrollableScrollPhysics(),
                                                keyboardType:
                                                    TextInputType.multiline,
                                                minLines: 1,
                                                maxLines:
                                                    null, // cresce com o texto
                                                style: _getFontStyle(),
                                                decoration:
                                                    const InputDecoration(
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                      border: InputBorder.none,
                                                      enabledBorder:
                                                          InputBorder.none,
                                                      focusedBorder:
                                                          InputBorder.none,
                                                      errorBorder:
                                                          InputBorder.none,
                                                      disabledBorder:
                                                          InputBorder.none,
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -12,
                                    right: -12,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: _chipBg,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: _chipBorder),
                                      ),
                                      child: IconButton(
                                        onPressed: () {
                                          HapticFeedback.selectionClick();

                                          _show.value = false;
                                        },
                                        icon: const Icon(
                                          CupertinoIcons.xmark,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                SafeArea(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();

                                if (Platform.isAndroid) {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(
                                        'Tem certeza que quer sair?',
                                        style: GoogleFonts.quicksand(),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            HapticFeedback.selectionClick();
                                            Navigator.pop(context);
                                          },
                                          child: Text(
                                            'Cancelar',
                                            style: GoogleFonts.quicksand(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            HapticFeedback.heavyImpact();

                                            Navigator.pop(context);
                                            Navigator.pop(context);
                                          },
                                          child: Text(
                                            'Sair',
                                            style: GoogleFonts.quicksand(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else if (Platform.isIOS) {
                                  showCupertinoDialog(
                                    context: context,
                                    builder: (context) => CupertinoAlertDialog(
                                      title: Text(
                                        'Tem certeza que quer sair?',
                                        style: GoogleFonts.quicksand(),
                                      ),
                                      actions: [
                                        CupertinoDialogAction(
                                          onPressed: () {
                                            HapticFeedback.selectionClick();

                                            Navigator.pop(context);
                                          },
                                          child: Text(
                                            'Cancelar',
                                            style: GoogleFonts.quicksand(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        CupertinoDialogAction(
                                          onPressed: () {
                                            HapticFeedback.heavyImpact();

                                            Navigator.pop(context);

                                            Navigator.pop(context);
                                          },
                                          isDestructiveAction: true,
                                          child: Text(
                                            'Sair',
                                            style: GoogleFonts.quicksand(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                              child: const CircleAvatar(
                                backgroundColor: Colors.black,
                                child: Icon(Icons.close, color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox.shrink(),
                        ],
                      ),
                      const Spacer(),
                      // Controles inferiores isolados
                      RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_maxDurationSeconds != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: ValueListenableBuilder2<double, double>(
                                    first: _currentTotalDurationN,
                                    second: _currentRecordingDurationN,
                                    builder: (context, total, rec, _) {
                                      final used = total + rec;
                                      return Column(
                                        children: [
                                          ValueListenableBuilder<bool>(
                                            valueListenable:
                                                _isRecordingNotifier,
                                            builder: (_, isRec, _) {
                                              return LinearProgressIndicator(
                                                value:
                                                    (_maxDurationSeconds !=
                                                            null &&
                                                        _maxDurationSeconds! >
                                                            0)
                                                    ? (used /
                                                          _maxDurationSeconds!)
                                                    : null,
                                                backgroundColor: Colors.white24,
                                                color: isRec
                                                    ? Colors.blue
                                                    : (_maxDurationSeconds !=
                                                              null &&
                                                          used >=
                                                              (_maxDurationSeconds! *
                                                                  0.83))
                                                    ? Colors.red
                                                    : Colors.green,
                                                minHeight: 6,
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Duração total: ${used.toStringAsFixed(2)}s',
                                                style: GoogleFonts.quicksand(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (_maxDurationSeconds != null)
                                                Text(
                                                  'Máximo: ${_maxDurationSeconds!}s',
                                                  style: GoogleFonts.quicksand(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (_maxDurationSeconds != null &&
                                              used >=
                                                  (_maxDurationSeconds! *
                                                      0.83) &&
                                              used < _maxDurationSeconds!) ...[
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withAlpha(
                                                  204,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Atenção: Próximo do limite de ${_maxDurationSeconds!}s!',
                                                style: GoogleFonts.quicksand(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: _isRecordingNotifier,
                                        builder: (_, isRec, _) {
                                          return IgnorePointer(
                                            ignoring: isRec,
                                            child: AnimatedOpacity(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              curve: Curves.easeOut,
                                              opacity: isRec ? 0.0 : 1.0,
                                              child: AnimatedScale(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                curve: Curves.easeOut,
                                                scale: isRec ? 0.9 : 1.0,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    HapticFeedback.selectionClick();

                                                    showModalBottomSheet(
                                                      context: context,
                                                      isScrollControlled: true,
                                                      builder: (context) =>
                                                          const SettingsTeleprompterWidget(),
                                                    );
                                                  },
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          right: 50,
                                                        ),
                                                    width: 64,
                                                    height: 64,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withAlpha(50),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.black
                                                            .withAlpha(40),
                                                      ),
                                                    ),
                                                    child: const Icon(
                                                      CupertinoIcons.gear,
                                                      color: Colors.white,
                                                      size: 36,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _isRecordingNotifier,
                                    builder: (_, isRec, _) {
                                      final isLimitReached =
                                          _maxDurationSeconds != null &&
                                          _currentTotalDuration >=
                                              _maxDurationSeconds!;
                                      return GestureDetector(
                                        onTap: isLimitReached && !isRec
                                            ? null
                                            : () async {
                                                HapticFeedback.lightImpact();

                                                if (isRec) {
                                                  await stopRecording();
                                                } else {
                                                  await _showCountdownPopup(
                                                    context,
                                                  );
                                                  await startRecording();
                                                }
                                              },
                                        child: SizedBox(
                                          width: 88,
                                          height: 88,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 240,
                                                ),
                                                curve: Curves.easeOut,
                                                width: 88,
                                                height: 88,
                                                decoration: BoxDecoration(
                                                  color: Colors.transparent,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: isRec ? 10 : 4,
                                                  ),
                                                ),
                                              ),
                                              AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 240,
                                                ),
                                                curve: Curves.easeOut,
                                                width: isLimitReached && !isRec
                                                    ? 0
                                                    : (isRec ? 56 : 76),
                                                height: isLimitReached && !isRec
                                                    ? 0
                                                    : (isRec ? 56 : 76),
                                                decoration: BoxDecoration(
                                                  color:
                                                      isLimitReached && !isRec
                                                      ? Colors.grey
                                                      : Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: _isRecordingNotifier,
                                        builder: (_, isRec, _) {
                                          return IgnorePointer(
                                            ignoring: isRec,
                                            child: AnimatedOpacity(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              curve: Curves.easeOut,
                                              opacity: isRec ? 0.0 : 1.0,
                                              child: AnimatedScale(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                curve: Curves.easeOut,
                                                scale: isRec ? 0.9 : 1.0,
                                                child: Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 50,
                                                  ),
                                                  width: 64,
                                                  height: 64,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withAlpha(50),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.black
                                                          .withAlpha(40),
                                                    ),
                                                  ),
                                                  child: IconButton(
                                                    onPressed: isRec
                                                        ? null
                                                        : () {
                                                            HapticFeedback.selectionClick();

                                                            switchCamera();
                                                          },
                                                    iconSize: 32,
                                                    icon: const Icon(
                                                      CupertinoIcons
                                                          .camera_rotate,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOut,
                                alignment: Alignment.topCenter,
                                child: ValueListenableBuilder<List<XFile>>(
                                  valueListenable: _recordedTakes,
                                  builder: (_, takes, _) {
                                    return ValueListenableBuilder<bool>(
                                      valueListenable: _isRecordingNotifier,
                                      builder: (_, isRec, _) {
                                        if (takes.isEmpty || isRec) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                ElevatedButton(
                                                  onPressed: () {
                                                    HapticFeedback.selectionClick();

                                                    showModalBottomSheet(
                                                      context: context,
                                                      builder: (context) {
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.all(
                                                                16.0,
                                                              ),
                                                          child: RecordedTakesThumbnails(
                                                            onRemoveTake: (index) {
                                                              HapticFeedback.mediumImpact();

                                                              final removed =
                                                                  _recordedTakes
                                                                      .value[index];
                                                              _recordedTakes
                                                                      .value =
                                                                  List.from(
                                                                    _recordedTakes
                                                                        .value,
                                                                  )..removeAt(
                                                                    index,
                                                                  );
                                                              _recordedDurations
                                                                  .remove(
                                                                    removed
                                                                        .path,
                                                                  );
                                                              _updateCurrentTotalDuration();
                                                              Navigator.pop(
                                                                context,
                                                              );
                                                            },
                                                            recordedTakes:
                                                                takes,
                                                          ),
                                                        );
                                                      },
                                                    );
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors
                                                        .white
                                                        .withAlpha(15),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 20,
                                                          vertical: 14,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            18,
                                                          ),
                                                    ),
                                                    side: BorderSide(
                                                      color: Colors.white
                                                          .withAlpha(40),
                                                    ),
                                                    elevation: 0,
                                                  ),
                                                  child: Text(
                                                    'Ver takes (${takes.length})',
                                                    style:
                                                        GoogleFonts.quicksand(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                  ),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    HapticFeedback.lightImpact();

                                                    finishAndReturnFinalVideo();
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors
                                                        .white
                                                        .withAlpha(89),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 24,
                                                          vertical: 16,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            18,
                                                          ),
                                                    ),
                                                    side: BorderSide(
                                                      color: Colors.white
                                                          .withAlpha(71),
                                                    ),
                                                    elevation: 0,
                                                  ),
                                                  child: Text(
                                                    'Finalizar vídeo',
                                                    style:
                                                        GoogleFonts.quicksand(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Colors.black,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    TeleprompterSettings.notifier.removeListener(_onSettingsChanged);
    _scrollAnimationController.stop();
    _scrollAnimationController.dispose();
    _scrollController.dispose();
    cameraController.dispose();
    _isPlayingNotifier.dispose();
    _isRecordingNotifier.dispose();
    _cardPosition.dispose();
    _show.dispose();
    _recordedTakes.dispose();
    _currentTotalDurationN.dispose();
    _currentRecordingDurationN.dispose();
    clearAppCache();
    WakelockPlus.disable();
    super.dispose();
  }
}

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
  });

  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, _) => builder(context, a, b, null),
        );
      },
    );
  }
}
