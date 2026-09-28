import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PoseDetectorService {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      model: PoseDetectionModel.base,
      mode: PoseDetectionMode.stream,
    ),
  );

  bool _isBusy = false;
  Size? _lastImageSize;
  Size? get lastImageSize => _lastImageSize;

  Future<List<Pose>?> processCameraImage(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) async {
    if (_isBusy) return null;
    _isBusy = true;
    _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

    final inputImage = _inputImageFromCameraImage(image, sensorOrientation, lensDirection);
    if (inputImage == null) {
      _isBusy = false;
      return null;
    }

    try {
      final poses = await _poseDetector.processImage(inputImage);
      _isBusy = false;
      return poses;
    } catch (e) {
      _isBusy = false;
      return null;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image, int sensorOrientation, CameraLensDirection lensDirection) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
    
    final imageRotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (imageRotation == null) return null;

    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;

    final inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  void close() {
    _poseDetector.close();
  }
}