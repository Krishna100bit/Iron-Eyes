import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size absoluteImageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  PosePainter(this.poses, this.absoluteImageSize, this.rotation, this.lensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = const Color(0xFF00E5FF); // Cyber Blue

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..color = Colors.white;

    for (final pose in poses) {
      pose.landmarks.forEach((_, landmark) {
        final x = _translateX(landmark.x, rotation, size, absoluteImageSize);
        final y = _translateY(landmark.y, rotation, size, absoluteImageSize);
        canvas.drawCircle(Offset(x, y), 5, pointPaint);
      });

      void paintLine(PoseLandmarkType type1, PoseLandmarkType type2) {
        final joint1 = pose.landmarks[type1];
        final joint2 = pose.landmarks[type2];
        if (joint1 != null && joint2 != null && joint1.likelihood > 0.6 && joint2.likelihood > 0.6) {
          final x1 = _translateX(joint1.x, rotation, size, absoluteImageSize);
          final y1 = _translateY(joint1.y, rotation, size, absoluteImageSize);
          final x2 = _translateX(joint2.x, rotation, size, absoluteImageSize);
          final y2 = _translateY(joint2.y, rotation, size, absoluteImageSize);
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
        }
      }

      // Draw arms
      paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      paintLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      paintLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

      // Draw body
      paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
      paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      paintLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

      // Draw legs
      paintLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      paintLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      paintLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      paintLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.absoluteImageSize != absoluteImageSize ||
           oldDelegate.poses != poses;
  }

  double _translateX(double x, InputImageRotation rotation, Size size, Size absoluteImageSize) {
    double scaledX = 0;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        scaledX = x * size.width / absoluteImageSize.height;
        break;
      default:
        scaledX = x * size.width / absoluteImageSize.width;
    }
    return lensDirection == CameraLensDirection.front ? size.width - scaledX : scaledX;
  }

  double _translateY(double y, InputImageRotation rotation, Size size, Size absoluteImageSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * size.height / absoluteImageSize.width;
      default:
        return y * size.height / absoluteImageSize.height;
    }
  }
}
