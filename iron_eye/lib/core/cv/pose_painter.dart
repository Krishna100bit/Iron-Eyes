import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size absoluteImageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
  final Map<PoseLandmarkType, Offset>? smoothedLandmarks;
  final Map<PoseLandmarkType, double>? smoothedLikelihoods;

  PosePainter(
    this.poses,
    this.absoluteImageSize,
    this.rotation,
    this.lensDirection, {
    this.smoothedLandmarks,
    this.smoothedLikelihoods,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (poses.isEmpty) return;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    final jointHaloPaint = Paint()
      ..style = PaintingStyle.fill;

    final jointDotPaint = Paint()
      ..style = PaintingStyle.fill;

    final pose = poses.first;

    void paintLine(PoseLandmarkType type1, PoseLandmarkType type2) {
      final pos1 = smoothedLandmarks?[type1] ??
          (pose.landmarks[type1] != null ? Offset(pose.landmarks[type1]!.x, pose.landmarks[type1]!.y) : null);
      final pos2 = smoothedLandmarks?[type2] ??
          (pose.landmarks[type2] != null ? Offset(pose.landmarks[type2]!.x, pose.landmarks[type2]!.y) : null);
      final conf1 = smoothedLikelihoods?[type1] ?? pose.landmarks[type1]?.likelihood ?? 0.0;
      final conf2 = smoothedLikelihoods?[type2] ?? pose.landmarks[type2]?.likelihood ?? 0.0;

      if (pos1 != null && pos2 != null && conf1 >= 0.35 && conf2 >= 0.35) {
        final x1 = _translateX(pos1.dx, rotation, size, absoluteImageSize);
        final y1 = _translateY(pos1.dy, rotation, size, absoluteImageSize);
        final x2 = _translateX(pos2.dx, rotation, size, absoluteImageSize);
        final y2 = _translateY(pos2.dy, rotation, size, absoluteImageSize);

        final avgConf = (conf1 + conf2) / 2.0;
        final alpha = (avgConf * 0.85 + 0.15).clamp(0.25, 1.0);

        // Cyber neon glow outer stroke
        glowPaint.color = const Color(0xFF00E5FF).withOpacity(alpha * 0.35);
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), glowPaint);

        // Solid inner core stroke
        linePaint.color = const Color(0xFF00E5FF).withOpacity(alpha);
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
      }
    }

    // Connect anatomical skeletal bones:
    // Upper body / arms
    paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    paintLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
    paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    paintLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

    // Torso box
    paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    paintLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

    // Lower body / legs
    paintLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
    paintLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
    paintLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    paintLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);

    // Draw primary structural joints
    const keyJoints = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];

    for (final jointType in keyJoints) {
      final pos = smoothedLandmarks?[jointType] ??
          (pose.landmarks[jointType] != null ? Offset(pose.landmarks[jointType]!.x, pose.landmarks[jointType]!.y) : null);
      final conf = smoothedLikelihoods?[jointType] ?? pose.landmarks[jointType]?.likelihood ?? 0.0;

      if (pos != null && conf >= 0.35) {
        final x = _translateX(pos.dx, rotation, size, absoluteImageSize);
        final y = _translateY(pos.dy, rotation, size, absoluteImageSize);
        final alpha = (conf * 0.8 + 0.2).clamp(0.3, 1.0);

        // Outer cyber cyan halo
        jointHaloPaint.color = const Color(0xFF00E5FF).withOpacity(alpha * 0.45);
        canvas.drawCircle(Offset(x, y), 5.5, jointHaloPaint);

        // Crisp white core
        jointDotPaint.color = Colors.white.withOpacity(alpha);
        canvas.drawCircle(Offset(x, y), 2.5, jointDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return true;
  }

  double _translateX(double x, InputImageRotation rotation, Size size, Size absoluteImageSize) {
    if (absoluteImageSize.width == 0 || absoluteImageSize.height == 0) return x;
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
    if (absoluteImageSize.width == 0 || absoluteImageSize.height == 0) return y;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * size.height / absoluteImageSize.width;
      default:
        return y * size.height / absoluteImageSize.height;
    }
  }
}