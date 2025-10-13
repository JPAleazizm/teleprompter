import 'dart:typed_data';
import 'package:camera/camera.dart' hide ImageFormat;
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// A modal widget that shows thumbnails for recorded takes and allows removing
/// individual takes.
///
/// The widget generates thumbnails asynchronously using `video_thumbnail`.
class RecordedTakesThumbnails extends StatefulWidget {
  /// The list of recorded video files to show.
  final List<XFile> recordedTakes;

  /// Called when the user requests removal of a take. Receives the take index.
  final void Function(int index) onRemoveTake;

  const RecordedTakesThumbnails({
    super.key,
    required this.recordedTakes,
    required this.onRemoveTake,
  });

  @override
  State<RecordedTakesThumbnails> createState() =>
      _RecordedTakesThumbnailsState();
}

class _RecordedTakesThumbnailsState extends State<RecordedTakesThumbnails> {
  final List<Uint8List?> _thumbnails = [];

  @override
  void initState() {
    super.initState();
    _generateThumbnails();
  }

  Future<void> _generateThumbnails() async {
    _thumbnails.clear();

    for (final take in widget.recordedTakes) {
      final thumb = await VideoThumbnail.thumbnailData(
        video: take.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128,
        quality: 75,
      );
      _thumbnails.add(thumb);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.5,
      child: _thumbnails.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              itemCount: _thumbnails.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(), // evita scroll dentro do modal
              itemBuilder: (context, index) {
                final thumb = _thumbnails[index];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: thumb != null
                          ? Image.memory(
                              thumb,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : const Icon(Icons.videocam_off, size: 128),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => widget.onRemoveTake(index),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
