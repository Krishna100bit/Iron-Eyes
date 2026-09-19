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

  // Squat specific heuristics
  // Uses Hip, Knee, Ankle angle to determine depth
  static double? calculateKneeAngle(Pose pose) {
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];

    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    if (leftHip == null || leftKnee == null || leftAnkle == null ||
        rightHip == null || rightKnee == null || rightAnkle == null) {
      return null;
    }

    final leftConfidence = (leftHip.likelihood + leftKnee.likelihood + leftAnkle.likelihood) / 3;
    final rightConfidence = (rightHip.likelihood + rightKnee.likelihood + rightAnkle.likelihood) / 3;

    if (math.max(leftConfidence, rightConfidence) < 0.45) return null;

    if (leftConfidence >= 0.45 && rightConfidence >= 0.45) {
      final leftAngle = calculateAngle(leftHip, leftKnee, leftAnkle);
      final rightAngle = calculateAngle(rightHip, rightKnee, rightAnkle);
      // Take the maximum angle: This forces BOTH knees to bend to register depth (prevents 1-leg raises)
      return math.max(leftAngle, rightAngle);
    } else if (leftConfidence > rightConfidence) {
      return calculateAngle(leftHip, leftKnee, leftAnkle);
    } else {
      return calculateAngle(rightHip, rightKnee, rightAnkle);
    }
  }

  // Uses Shoulder, Hip, Knee angle to determine torso lean
  static double calculateHipAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

    if (leftShoulder == null || leftHip == null || leftKnee == null ||
        rightShoulder == null || rightHip == null || rightKnee == null) {
      return 180.0;
    }

    final leftConfidence = (leftShoulder.likelihood + leftHip.likelihood + leftKnee.likelihood) / 3;
    final rightConfidence = (rightShoulder.likelihood + rightHip.likelihood + rightKnee.likelihood) / 3;

    if (leftConfidence > rightConfidence) {
      return calculateAngle(leftShoulder, leftHip, leftKnee);
    } else {
      return calculateAngle(rightShoulder, rightHip, rightKnee);
    }
  }

  // Uses Shoulder, Elbow, Wrist angle to determine arm extension
  static double? calculateElbowAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    if (leftShoulder == null || leftElbow == null || leftWrist == null ||
        rightShoulder == null || rightElbow == null || rightWrist == null) {
      return null;
    }

    final leftConfidence = (leftShoulder.likelihood + leftElbow.likelihood + leftWrist.likelihood) / 3;
    final rightConfidence = (rightShoulder.likelihood + rightElbow.likelihood + rightWrist.likelihood) / 3;

    if (math.max(leftConfidence, rightConfidence) < 0.45) return null;

    if (leftConfidence > rightConfidence) {
      return calculateAngle(leftShoulder, leftElbow, leftWrist);
    } else {
      return calculateAngle(rightShoulder, rightElbow, rightWrist);
    }
  }

  static bool isValidHuman(Pose pose) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (nose == null || leftShoulder == null || rightShoulder == null) {
      return false;
    }

    // A real human should have at least ONE major upper body landmark with decent confidence.
    // If you look away, the nose drops but shoulders remain. If you face the floor, the nose drops.
    final maxConfidence = math.max(
      nose.likelihood,
      math.max(leftShoulder.likelihood, rightShoulder.likelihood)
    );

    if (maxConfidence < 0.4) {
      return false;
    }

    return true;
  }

  // Uses human proportions and camera perspective to determine if the user is standing upright.
  static bool isStanding(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final hip = pose.landmarks[PoseLandmarkType.leftHip] ?? pose.landmarks[PoseLandmarkType.rightHip];

    if (leftShoulder == null || rightShoulder == null || hip == null) {
      return false; // Not enough info, assume false to not block reps
    }

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    final avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2;
    final dy = (avgShoulderY - hip.y).abs();

    // Prevent division by zero if shoulders overlap (standing sideways)
    if (shoulderWidth < 5) return true; 

    // A standing human's vertical torso length (dy) is typically 1.5x to 2x their shoulder width.
    // In a push-up or bench press, perspective foreshortening (front view) or horizontal layout (side view) 
    // makes dy much smaller relative to shoulder width.
    if (dy > shoulderWidth * 1.5) {
      return true;
    }
    return false;
  }
}
