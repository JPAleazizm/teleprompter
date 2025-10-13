import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Mixin that encapsulates basic camera lifecycle and utilities.
///
/// Provides a `CameraController`, current camera selection and simple zoom
/// helpers. Intended to be mixed into a `State` class for widgets that need
/// camera preview and recording.
///
/// Public members:
/// - `cameraController` — initialized `CameraController` after
///   `initializeCamera()` completes.
/// - `initializeCamera()` — initializes available cameras and selects the
///   front camera.
/// - `switchCamera()` — swap between available cameras.
mixin CameraBase<T extends StatefulWidget> on State<T> {
  late CameraController cameraController;
  List<CameraDescription>? cameras;
  CameraDescription? currentCamera;

  double currentZoom = 1.0;
  double baseZoom = 1.0;
  double minZoom = 1.0;
  double maxZoom = 8.0;

  Future<void> initializeCamera() async {
    try {
      cameras = await availableCameras();
      currentCamera = cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      cameraController = CameraController(
        currentCamera!,
        ResolutionPreset.max,
        fps: 30,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await cameraController.initialize();
    } catch (e, stack) {
      debugPrint('Erro ao inicializar a câmera: $e');
      debugPrintStack(stackTrace: stack);
      rethrow;
    }
  }

  Future<void> initializeZoomLimits() async {
    minZoom = await cameraController.getMinZoomLevel();
    maxZoom = await cameraController.getMaxZoomLevel();
    currentZoom = minZoom;
  }

  Future<void> switchCamera() async {
    if (cameras == null || cameras!.isEmpty) {
      debugPrint('Nenhuma câmera disponível');
      return;
    }

    try {
      final newCamera = cameras!.firstWhere(
        (camera) => camera.lensDirection != currentCamera!.lensDirection,
      );

      await cameraController.dispose();
      cameraController = CameraController(
        newCamera,
        ResolutionPreset.max,
        fps: 30,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      currentCamera = newCamera;

      await cameraController.initialize();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Erro ao trocar câmera: $e');
    }
  }
}
