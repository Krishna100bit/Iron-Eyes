import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class AngleCalculator {
  static double calculateAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final rad = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x);
    var deg = (rad * 180.0 / math.pi).abs();
    if (deg > 180.0) {
      deg = 360.0 - deg;
    }
    return deg;
  }

  // Evaluates knee angles independently per leg.
  // Filters out low-confidence landmarks (min 0.40) to eliminate noise spikes.
  static double? calculateKneeAngle(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];

    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    final bool leftValid = leftHip != null && leftKnee != null && leftAnkle != null &&
        leftHip.likelihood >= 0.40 && leftKnee.likelihood >= 0.40 && leftAnkle.likelihood >= 0.40;
    final bool rightValid = rightHip != null && rightKnee != null && rightAnkle != null &&
        rightHip.likelihood >= 0.40 && rightKnee.likelihood >= 0.40 && rightAnkle.likelihood >= 0.40;

    if (!leftValid && !rightValid) return null;

    final double? leftAngle = leftValid
        ? calculateAngle(leftHip!, leftKnee!, leftAnkle!)
        : null;
    final double? rightAngle = rightValid
        ? calculateAngle(rightHip!, rightKnee!, rightAnkle!)
        : null;

    if (leftAngle != null && rightAngle != null) {
      if ((leftAngle - rightAngle).abs() <= 25.0) {
        return (leftAngle + rightAngle) / 2.0;
      } else {
        return math.min(leftAngle, rightAngle);
      }
    } else if (leftAngle != null) {
      return leftAngle;
    } else {
      return rightAngle;
    }
  }

  // Calculates thigh inclination angle relative to horizontal.
  // Serves as an infallible biomechanical fallback when ankles are cropped or occluded by dumbbells.
  // Standing: Thigh is vertical (~85°) -> maps to ~175° equivalent knee angle.
  // Parallel Squat: Thigh is horizontal (~10-15°) -> maps to ~100-105° equivalent knee angle.
  static double? calculateThighAngle(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

    final bool leftValid = leftHip != null && leftKnee != null &&
        leftHip.likelihood >= 0.42 && leftKnee.likelihood >= 0.42;
    final bool rightValid = rightHip != null && rightKnee != null &&
        rightHip.likelihood >= 0.42 && rightKnee.likelihood >= 0.42;

    if (!leftValid && !rightValid) return null;

    double computeThighEqAngle(PoseLandmark hip, PoseLandmark knee) {
      final dx = (knee.x - hip.x).abs();
      final dy = math.max(0.0, knee.y - hip.y);
      final rad = math.atan2(dy, dx);
      final degFromHoriz = rad * 180.0 / math.pi;
      return 90.0 + degFromHoriz;
    }

    final double? leftEq = leftValid ? computeThighEqAngle(leftHip!, leftKnee!) : null;
    final double? rightEq = rightValid ? computeThighEqAngle(rightHip!, rightKnee!) : null;

    if (leftEq != null && rightEq != null) {
      return (leftEq + rightEq) / 2.0;
    }
    return leftEq ?? rightEq;
  }

  // Uses Shoulder, Hip, Knee angle to determine torso/hip flexion (used for form assessment)
  static double calculateHipAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

    final bool leftValid = leftShoulder != null && leftHip != null && leftKnee != null &&
        leftShoulder.likelihood >= 0.35 && leftHip.likelihood >= 0.35 && leftKnee.likelihood >= 0.35;
    final bool rightValid = rightShoulder != null && rightHip != null && rightKnee != null &&
        rightShoulder.likelihood >= 0.35 && rightHip.likelihood >= 0.35 && rightKnee.likelihood >= 0.35;

    if (!leftValid && !rightValid) return 180.0;

    if (leftValid && rightValid) {
      final leftAngle = calculateAngle(leftShoulder!, leftHip!, leftKnee!);
      final rightAngle = calculateAngle(rightShoulder!, rightHip!, rightKnee!);
      return (leftAngle + rightAngle) / 2.0;
    } else if (leftValid) {
      return calculateAngle(leftShoulder!, leftHip!, leftKnee!);
    } else if (rightValid) {
      return calculateAngle(rightShoulder!, rightHip!, rightKnee!);
    }
    return 180.0;
  }

  // Comprehensive squat angle evaluator.
  // 1. Tries 3-point knee angle if ankles are clearly detected.
  // 2. Falls back to thigh inclination (hip to knee angle) if ankles are occluded.
  static double? calculateSquatAngle(Pose pose) {
    final kneeAngle = calculateKneeAngle(pose);
    if (kneeAngle != null) return kneeAngle;

    final thighAngle = calculateThighAngle(pose);
    if (thighAngle != null) return thighAngle;

    return null;
  }

  // Normalized Y position of hips
  static double? getHipY(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final bool leftValid = leftHip != null && leftHip.likelihood >= 0.35;
    final bool rightValid = rightHip != null && rightHip.likelihood >= 0.35;

    if (leftValid && rightValid) {
      return (leftHip!.y + rightHip!.y) / 2.0;
    } else if (leftValid) {
      return leftHip!.y;
    } else if (rightValid) {
      return rightHip!.y;
    }
    return null;
  }

  // Uses Shoulder, Elbow, Wrist angle to determine arm extension
  static double? calculateElbowAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    final bool leftValid = leftShoulder != null && leftElbow != null && leftWrist != null &&
        leftShoulder.likelihood >= 0.38 && leftElbow.likelihood >= 0.38 && leftWrist.likelihood >= 0.38;
    final bool rightValid = rightShoulder != null && rightElbow != null && rightWrist != null &&
        rightShoulder.likelihood >= 0.38 && rightElbow.likelihood >= 0.38 && rightWrist.likelihood >= 0.38;

    if (!leftValid && !rightValid) return null;

    if (leftValid && rightValid) {
      final leftAngle = calculateAngle(leftShoulder!, leftElbow!, leftWrist!);
      final rightAngle = calculateAngle(rightShoulder!, rightElbow!, rightWrist!);
      return (leftAngle + rightAngle) / 2.0;
    } else if (leftValid) {
      return calculateAngle(leftShoulder!, leftElbow!, leftWrist!);
    } else if (rightValid) {
      return calculateAngle(rightShoulder!, rightElbow!, rightWrist!);
    }
    return null;
  }

  // Evaluates asymmetric extension (injury risk for bench press)
  static double? checkElbowAsymmetry(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    final bool leftValid = leftShoulder != null && leftElbow != null && leftWrist != null &&
        leftShoulder.likelihood >= 0.38 && leftElbow.likelihood >= 0.38 && leftWrist.likelihood >= 0.38;
    final bool rightValid = rightShoulder != null && rightElbow != null && rightWrist != null &&
        rightShoulder.likelihood >= 0.38 && rightElbow.likelihood >= 0.38 && rightWrist.likelihood >= 0.38;

    if (leftValid && rightValid) {
      final leftAngle = calculateAngle(leftShoulder, leftElbow, leftWrist);
      final rightAngle = calculateAngle(rightShoulder, rightElbow, rightWrist);
      return (leftAngle - rightAngle).abs();
    }
    return null;
  }

  static bool isValidHuman(Pose pose) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    final hasUpperTorso = (leftShoulder != null && leftShoulder.likelihood >= 0.35) ||
                          (rightShoulder != null && rightShoulder.likelihood >= 0.35);
    final hasMidTorso = (leftHip != null && leftHip.likelihood >= 0.35) ||
                        (rightHip != null && rightHip.likelihood >= 0.35) ||
                        (nose != null && nose.likelihood >= 0.35);

    return hasUpperTorso && hasMidTorso;
  }

  // Uses human proportions and camera perspective to determine if the user is standing upright.
  static bool isStanding(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final hip = pose.landmarks[PoseLandmarkType.leftHip] ?? pose.landmarks[PoseLandmarkType.rightHip];

    if ((leftShoulder == null && rightShoulder == null) || hip == null) {
      return false;
    }

    final shoulderY = leftShoulder != null && rightShoulder != null
        ? (leftShoulder.y + rightShoulder.y) / 2.0
        : (leftShoulder?.y ?? rightShoulder!.y);

    final dy = hip.y - shoulderY;
    if (dy < 20) return false;

    if (leftShoulder != null && rightShoulder != null) {
      final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
      if (shoulderWidth < 10) return true;
      if (dy > shoulderWidth * 0.9) return true;
    } else {
      return true;
    }

    return false;
  }
}