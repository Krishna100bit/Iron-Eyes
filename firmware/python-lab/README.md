# IRONLOOP — Python Velocity Testing Environment

A deterministic, high-accuracy Velocity-Based Training (VBT) barbell tracking and 1RM estimation environment built in Python with pure NumPy/SciPy digital signal processing.

---

## 1. Quick Setup

```powershell
cd C:\SIH\python-lab
pip install -r requirements.txt
```

---

## 2. Interactive Live Dashboard (Primary Command)

`python src/dashboard.py` is now the **one command to run for testing**.

```powershell
python src/dashboard.py
```

### Dashboard Interface:
```
┌─ IRONLOOP ─────────────────────────────────────┐
│ BLE: [scanning... / connecting.. / CONNECTED]  │
│ Batt: 87% (4.05V)        Calibrated: YES/NO    │
│ Session: IDLE / ACTIVE                         │
│ Load: 100 kg                                   │
├────────────────────────────────────────────────┤
│ LIVE BAR SPEED:    0.74 m/s  [▲▲▲▲▲▲▲     ]    │
│ Last rep: mean 0.71 m/s  peak 0.95 m/s  OK     │
│ Reps this set: 4                               │
├────────────────────────────────────────────────┤
│ e1RM (squat): 142 kg  (R²=0.91, n=6 points)    │
├────────────────────────────────────────────────┤
│ [c] Calibrate  [s] Start  [x] Stop  [l] Set load│
│ [r] Reset set  [q] Quit                        │
└────────────────────────────────────────────────┘
```

### Keyboard Controls (Single keypress, non-blocking):
- **`s`** : **Start Session** — Sends `START_SESSION` (0x01) over BLE. The firmware runs automatic 3s stationary calibration and begins 100 Hz IMU streaming.
- **`x`** : **Stop Session** — Sends `STOP_SESSION` (0x02) over BLE.
- **`c`** : **Calibrate** — Sends standalone `CALIBRATE` (0x03) over BLE.
- **`l`** : **Set Barbell Load** — Opens a quick input prompt for load in kg (e.g. `80`, `100`, `120`), tagging all subsequent reps for e1RM regression.
- **`r`** : **Reset Set** — Clears current set's rep count and e1RM working data without resetting the BLE session.
- **`q`** : **Quit** — Cleanly disconnects BLE and auto-saves full session data (raw IMU samples + rep metrics) to `data/real_captures/`.

---

## 3. Architecture & Modules

```
python-lab/
├── requirements.txt            # bleak, numpy, scipy, matplotlib, windows-curses
├── data/
│   └── real_captures/          # Timestamped CSV logs (raw samples & rep summaries)
└── src/
    ├── dashboard.py            # Single-file interactive terminal dashboard (ONE-COMMAND ENTRY POINT)
    ├── load_velocity_engine.py # Linear regression e1RM estimation with outlier rejection & MVT
    ├── config.py               # Central repository for ALL algorithm hyper-parameters & BLE UUIDs
    ├── packet_parser.py        # Decodes 78-byte Stream & 4-byte Status packets + CRC8 verify
    ├── ble_client.py           # Bleak GATT client for IronLoop (Stream, Command, Status)
    ├── orientation_filter.py   # Mahony AHRS quaternion filter (gravity alignment)
    ├── gravity_removal.py      # Body -> World frame rotation & [0,0,9.81] removal
    ├── filtering.py            # Savitzky-Golay peak-preserving polynomial smoother
    ├── stationary_detector.py  # Dual-threshold (|accel| variance & |gyro| magnitude)
    ├── zupt_integrator.py      # Zero-Velocity Update (ZUPT) numerical integrator
    ├── rep_detector.py         # Eccentric -> Concentric -> Pause barbell rep segmenter
    ├── pipeline.py             # Pure functional end-to-end VBT processing chain
    ├── live_session.py         # Headless CLI streaming client
    └── replay_saved.py         # Offline CSV replay & parameter tuning visualizer
```

---

## 4. Load-Velocity & e1RM Profiling (`load_velocity_engine.py`)

- **Strict Linear Regression**: Fits velocity vs. load ($v = m \cdot L + c$) once $\ge 4$ distinct loads are recorded. No polynomial overfitting.
- **Outlier Rejection**: Discards points $> 2$ standard deviations from the preliminary line before refitting.
- **Minimum Velocity Threshold (MVT)**: Extrapolates 1RM at $0.30\text{ m/s}$ (configurable in `config.py` via `MIN_VELOCITY_THRESHOLD_SQUAT`).
- **Conservative Confidence Rating**: Reports $R^2$, sample count $n$, and rating ("Low confidence" for $<4$ points or $R^2 < 0.70$, "Moderate confidence" otherwise).

---

## 5. Fast Offline Tuning Loop (`replay_saved.py`)

To analyze or re-run any saved capture against modified thresholds in `config.py`:

```powershell
python src/replay_saved.py --input data/real_captures/ironloop_raw_YYYYMMDD_HHMMSS.csv
```
