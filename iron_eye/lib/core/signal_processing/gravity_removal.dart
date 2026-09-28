/// Removes Earth's gravity from a body-frame acceleration vector using the
/// orientation estimated by [OrientationFilter].
///
class GravityRemoval {
  static const double _g = 9.80665; // m/s²

  /// Returns the gravity-free vertical (world Z) linear acceleration, in m/s².
  /// This is the only axis used for barbell rep detection.
  ///
  /// [worldAccelZ] must come from [OrientationFilter.worldAccelZ()].
  static double removeGravityVertical(double worldAccelZ) {
    return worldAccelZ - _g;
  }

  /// Returns all three world-frame linear acceleration components.
  /// [worldAx], [worldAy], [worldAz] are the body-frame acceleration
  /// already rotated into world frame by the orientation filter.
  static (double, double, double) removeGravity(
      double worldAx, double worldAy, double worldAz) {
    return (worldAx, worldAy, worldAz - _g);
  }

  static double get gravity => _g;
}