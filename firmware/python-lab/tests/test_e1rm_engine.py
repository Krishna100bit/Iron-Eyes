"""
test_e1rm_engine.py  —  Unit Tests for Blended LoadVelocityEngine
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from load_velocity_engine import LoadVelocityEngine, E1RMResult, estimate_expected_pct_1rm


class TestLoadVelocityEngine(unittest.TestCase):

    def setUp(self):
        self.engine = LoadVelocityEngine(exercise_name="squat", mvt_mps=0.30, min_points=4)

    def test_zero_points_insufficient(self):
        res = self.engine.compute_e1rm()
        self.assertFalse(res.is_valid)
        self.assertIn("insufficient data", res.status_message)
        self.assertIsNone(res.e1rm_kg)

    def test_single_rep_profile_estimate(self):
        # 1 rep at 100kg @ 0.67 m/s (~70% 1RM) -> e1RM ≈ 100 / 0.70 ≈ 143-149 kg
        res = self.engine.add_rep(100.0, 0.67, 0.95, "CLEAN", 1)
        self.assertTrue(res.is_valid)
        self.assertIsNotNone(res.e1rm_kg)
        self.assertAlmostEqual(res.e1rm_kg, 100.0 / 0.70, delta=10.0)
        self.assertIn("Profile-based (n=1", res.confidence_label)
        self.assertEqual(res.blend_weight, 0.0)

    def test_noisy_points_excluded(self):
        # Add 1 clean rep and 1 noisy rep -> only 1 clean point used
        self.engine.add_rep(100.0, 0.67, 0.95, "CLEAN", 1)
        res = self.engine.add_rep(120.0, 0.50, 0.70, "NOISY", 2)
        self.assertTrue(res.is_valid)
        self.assertEqual(res.n_points, 1)

    def test_blended_e1rm_with_four_points(self):
        # Clean progression: 60kg@0.90, 80kg@0.75, 100kg@0.60, 120kg@0.45
        # Linear: v = -0.0075 * L + 1.35 => e1RM personal = (0.30 - 1.35)/(-0.0075) = 140.0 kg
        self.engine.add_rep(60.0, 0.90, 1.15, "CLEAN", 1)
        self.engine.add_rep(80.0, 0.75, 1.00, "CLEAN", 2)
        self.engine.add_rep(100.0, 0.60, 0.85, "CLEAN", 3)
        res = self.engine.add_rep(120.0, 0.45, 0.70, "CLEAN", 4)

        self.assertTrue(res.is_valid)
        self.assertEqual(res.n_points, 4)
        self.assertEqual(res.blend_weight, 4.0 / 8.0) # 0.50
        self.assertIn("Blended (n=4)", res.confidence_label)
        self.assertAlmostEqual(res.personal_e1rm_kg, 140.0, places=1)

    def test_personal_fit_at_eight_points(self):
        # 8 points along linear line
        for i, (l, v) in enumerate([
            (50, 0.975), (60, 0.90), (70, 0.825), (80, 0.75),
            (90, 0.675), (100, 0.60), (110, 0.525), (120, 0.45)
        ]):
            res = self.engine.add_rep(float(l), float(v), 1.1, "CLEAN", i + 1)

        self.assertTrue(res.is_valid)
        self.assertEqual(res.n_points, 8)
        self.assertEqual(res.blend_weight, 1.0)
        self.assertIn("Personal fit (n=8", res.confidence_label)
        self.assertAlmostEqual(res.e1rm_kg, 140.0, places=1)

    def test_reset(self):
        self.engine.add_rep(60.0, 0.90, 1.15, "CLEAN", 1)
        self.engine.reset()
        self.assertEqual(len(self.engine.points), 0)
        res = self.engine.compute_e1rm()
        self.assertFalse(res.is_valid)


class TestBatteryProfile(unittest.TestCase):

    def test_battery_mv_to_percent(self):
        from config import battery_mv_to_percent

        self.assertEqual(battery_mv_to_percent(4250), 100)
        self.assertEqual(battery_mv_to_percent(4200), 100)
        self.assertEqual(battery_mv_to_percent(4100), 90)
        self.assertEqual(battery_mv_to_percent(3790), 50)
        self.assertEqual(battery_mv_to_percent(3400), 5)
        self.assertEqual(battery_mv_to_percent(3200), 0)
        self.assertEqual(battery_mv_to_percent(3000), 0)

        # Interpolation test
        pct_3900 = battery_mv_to_percent(3900)
        self.assertTrue(70 <= pct_3900 <= 80)


if __name__ == "__main__":
    unittest.main()


