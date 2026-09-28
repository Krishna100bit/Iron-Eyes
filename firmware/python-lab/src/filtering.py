"""
filtering.py  —  Savitzky-Golay Low-Pass Filtering
────────────────────────────────────────────────────
Applies a Savitzky-Golay polynomial smoothing filter (scipy.signal.savgol_filter)
to the linear acceleration signal prior to velocity integration.

Why Savitzky-Golay:
    Unlike conventional Butterworth or moving-average IIR/FIR filters that smear
    sharp acceleration peaks, Savitzky-Golay fits local polynomials to preserve
    peak heights and waveform shapes — essential for accurate peak concentric
    velocity (PV) calculation in VBT.
"""

from typing import Union
import numpy as np
from scipy.signal import savgol_filter


def apply_savgol_filter(
    data: np.ndarray,
    window_length: int = 15,
    polyorder: int = 3,
) -> np.ndarray:
    """
    Apply Savitzky-Golay filtering to 1D or 2D timeseries array.

    Args:
        data: (N,) or (N, D) numpy array of input signals.
        window_length: Length of filter window (must be a positive odd integer).
        polyorder: Order of the polynomial used to fit the samples.

    Returns:
        filtered_data: Smoothed numpy array with identical shape as data.
    """
    arr = np.asarray(data, dtype=np.float64)
    arr = np.nan_to_num(arr, nan=0.0, posinf=0.0, neginf=0.0)
    n_samples = len(arr)

    if n_samples == 0:
        return arr.copy()

    # Ensure window_length is odd
    wl = int(window_length)
    if wl % 2 == 0:
        wl += 1

    # Window length cannot exceed sample count
    if wl > n_samples:
        wl = n_samples if n_samples % 2 == 1 else n_samples - 1

    # Polynomial order must be less than window length
    po = int(polyorder)
    if po >= wl:
        po = max(1, wl - 1)

    # If array is too short for meaningful polynomial filtering, return as-is or simple mean
    if wl < 3 or po < 1:
        return arr.copy()

    axis = 0
    return savgol_filter(arr, window_length=wl, polyorder=po, axis=axis)
