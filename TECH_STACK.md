# Iron Eye — Feature × Technology Map

| Feature | Technology Used |
|---|---|
| **AI Rep Counting (Squat, Push-Up, Bench Press)** | Google ML Kit Pose Detection |
| **Live Skeleton Overlay on Camera** | Google ML Kit + Flutter `CustomPaint` |
| **Joint Angle Calculation** | Custom `AngleCalculator` (`dart:math`) |
| **Pose Smoothing (Noise Filter)** | Exponential Moving Average (EMA) |
| **Rep State Machine** | Custom Dart State Machine |
| **Hardware Camera Management** | `camera` plugin + `WidgetsBindingObserver` |
| **False Positive Rejection (Fingers/Objects)** | Custom Posture & Proportion Heuristics |
| **Bluetooth IMU Sensor (VBT)** | `flutter_blue_plus` (BLE) |
| **Barbell Velocity & Rep Metrics** | Custom Signal-Processing Pipeline |
| **Estimated 1-Rep Max (e1RM)** | Custom `LoadVelocityModel` |
| **Workout Session State Management** | Riverpod (`activeSessionProvider`) |
| **Local Exercise Library Data** | Local Dart Data Models |

---

## Detailed Technology Breakdown

The following sections explain the core technologies powering Iron Eye's computer vision and hardware integrations, designed for the engineering team.

### 1. Google ML Kit Pose Detection
**What it is:** A machine learning vision model developed by Google that runs entirely on-device (offline). It takes in a live video frame and outputs 33 3D skeletal landmark coordinates (e.g., left shoulder, right knee, nose) along with a "confidence score" for each joint.
**How we use it:** We stream the raw camera feed directly into ML Kit to locate the user's joints in real-time. This provides the raw X/Y coordinates needed to calculate body angles and draw the futuristic cyber-skeleton on the UI using Flutter's `CustomPaint` engine.

### 2. Custom Joint Angle & Posture Math
**What it is:** A mathematical engine (`AngleCalculator`) that uses trigonometry to convert raw X/Y coordinates from ML Kit into physical angles (degrees) and body proportions.
**How we use it:** 
- **Angles:** It mathematically tracks the angle of the elbow (for Push-Ups/Bench Press) and the knee (for Squats) by requiring both limbs to bend simultaneously.
- **Posture Validation:** It measures the distance between the shoulders vs. the vertical torso height. If the math detects a "vertical standing" posture, it strictly prevents Push-Ups from being counted (preventing a Squat from accidentally registering as a Push-up).
- **Finger Rejection:** By requiring a minimum pixel distance between shoulders and enforcing confidence scores, it rejects "hallucinated" skeletons that Neural Networks sometimes draw when a finger or abstract object is placed close to the camera.

### 3. Exponential Moving Average (EMA) Smoothing
**What it is:** A low-pass signal filter algorithm that smooths out sudden spikes in noisy data over time. 
**How we use it:** ML Kit occasionally "glitches" or the phone camera shakes, causing a joint angle to spike wildly for a single frame. The EMA filter absorbs this shock by mathematically blending the new raw angle with historical angles. This ensures the AI tracking state machine only reacts to smooth, deliberate human movement and ignores jitter and camera shake entirely.

### 4. The Rep Tracking State Machine
**What it is:** A logical control flow system that requires a sequence of strict states to be fulfilled before an action triggers.
**How we use it:** Instead of simply looking for a "bent knee" to count a rep, the system forces the user through a strict sequence:
1. `Idle` → Must achieve a locked-out starting posture (e.g., arms perfectly straight).
2. `Ready` → Must lower the body past a strict 90/100-degree depth threshold.
3. `Bottom` → Must push back up to a full lockout to complete the rep.
It also features a 400-millisecond time-based "debounce" constraint to ensure reps aren't counted faster than humanly possible.

### 5. BLE & VBT Signal Processing
**What it is:** Bluetooth Low Energy integration coupled with a physics-based signal processing pipeline.
**How we use it:** 
- `flutter_blue_plus` maintains a persistent connection to external hardware IMU sensors attached to the user's barbell.
- The `ImuPipeline` parses raw byte packets from the sensor into physical acceleration data.
- The `VelocityLoss` engine integrates this acceleration over time to calculate real-world bar speed (m/s) and tracks muscle fatigue percentage across a workout set.
- The `LoadVelocityModel` takes these speed metrics and uses linear regression to mathematically estimate the user's 1-Rep Max (e1RM) without requiring them to actually lift their maximum weight.

### 6. Riverpod State Management
**What it is:** A reactive caching and state-management framework for Dart.
**How we use it:** It acts as the central nervous system of the app. As the State Machine counts a rep, it dispatches an event to the Riverpod `activeSessionProvider`. Riverpod then instantly and efficiently updates the UI (the giant rep counter and form grade) and logs the metrics into the workout history database without needing to rebuild or stutter the camera screen.
