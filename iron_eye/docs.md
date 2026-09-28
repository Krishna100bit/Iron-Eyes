# IRONLOOP — App Development Master Documentation
**Team:** IRONEYES | **Problem Statement:** SIH26213 | **Prepared for:** Mahesh & Vikram (App), Onu (Firmware)
**Scope of this doc:** Fixes and new features required before the next internal-round build.

---

## 0. Summary of Changes

| # | Area | Type | Priority |
|---|------|------|----------|
| 1 | IMU + camera velocity tracking | Bug fix | Critical |
| 2 | L-V Graph | Rework | Critical |
| 3 | e1RM calculation | Improvement | High |
| 4 | RPE column | New field | High |
| 5 | Set/Rep UI (Stance-style) | UI overhaul | Critical |
| 6 | Edit/remove sets & reps | New feature | High |
| 7 | "Iron Eye" AI fatigue flagging | New feature | High |
| 8 | Velocity bar chart (variable height) | UI fix | Medium |
| 9 | Recovery Section + Rehab Engine | New feature | High |

---

## 1. IMU + Camera Fusion — Velocity Tracking Fix

**Current behavior:** When IMU and camera are both active, velocity tracking becomes unreliable/inaccurate — readings drift or don't reflect true bar/limb speed.

**Root causes to check:**
- Timestamp misalignment between IMU sample rate and camera frame rate (need a common clock — sync both streams to a single monotonic timestamp before fusion).
- Sensor fusion likely needs a Kalman filter (or complementary filter) combining IMU acceleration (double-integrated to velocity, prone to drift) with camera-derived position/velocity (accurate but lower frequency) to cancel drift.
- Confirm camera tracking point (barbell endpoint/marker) isn't losing lock under occlusion (rack, hands, plates) — needs a fallback to IMU-only estimate when the marker is lost, with a smooth handoff back once reacquired.
- Double-check units and axis alignment — IMU orientation (from LSM6DS3TR-C) must be resolved to the vertical/movement axis every rep, not assumed fixed, since bar path angle changes rep to rep.

**Required output:** One clean, per-rep velocity estimate that stays consistent across reps and doesn't need to rely on camera alone or IMU alone.

---

## 2. L-V Graph (Load-Velocity Graph)

**Current bug:** Graph renders a single dot instead of a proper curve/scatter across the set.

**Likely cause:** Only one (load, velocity) point is being pushed per set instead of per rep, or the data array isn't updating before the chart redraws.

**Required behavior:**
- Plot **one point per rep** — X-axis = load (kg), Y-axis = velocity (m/s).
- **Simplify the velocity metric:** Use a single **overall velocity per rep** (mean concentric velocity), not separate peak and mean values. Drop the peak/mean split — one number per rep keeps the graph and the athlete-facing UI clean.
- As more sets/reps are logged across a session (or historically for that exercise), points should accumulate to show the athlete's L-V profile/trend line.
- Consider fitting a simple linear regression line through the points to estimate 1RM velocity-based (this feeds into #3 below).

---

## 3. e1RM (Estimated 1-Rep Max) Calculation

**Current issue:** Calculation is too basic/inaccurate.

**Recommended approach:**
- Use a **velocity-based e1RM** model instead of (or alongside) a rep-based formula (like Epley/Brzycki), since you already have per-rep velocity data:
  - Build/use a load-velocity profile (from #2) and extrapolate to the athlete's known minimal velocity threshold (MVT) for that lift (e.g., ~0.15–0.3 m/s for squat at true 1RM) to estimate e1RM.
  - Fall back to a rep-based formula (Epley: `1RM = weight × (1 + reps/30)`) only when there isn't enough velocity data yet (e.g., first-ever session for that lift).
- Store both the **rep-based** and **velocity-based** e1RM per session so the two can be compared/validated over time, and display the more reliable one once enough data points exist (e.g., 3+ logged sets).

---

## 4. RPE Column

**New field required** in the set-logging table/view:
- Standard 1–10 RPE scale (supports .5 increments — 6, 6.5, 7 … 10).
- Logged per set (not per rep) — matches how RPE is normally reported by lifters.
- Store alongside load, reps, and velocity so RPE can later be cross-referenced with velocity in Iron Eye's fatigue analysis (see #7) — e.g., flag when RPE is rising but velocity is also dropping faster than expected, which is a strong fatigue/injury-risk signal.

---

## 5. Set/Rep Logging UI (Stance-app style)

**Goal:** Rework the workout logging screen to match the clarity of apps like Stance.

**Required structure:**
- **Exercise → Set list → Rep detail**, drill-down style:
  - Select an exercise (e.g., Squat).
  - See a list of sets for that exercise in the current session, each showing: load, reps, RPE, and a summary velocity value.
  - Tap into a set to see per-rep velocity breakdown (small inline sparkline or list of rep-by-rep velocities).
- Keep the logging flow fast during a live session (large tap targets, minimal screens between finishing a rep and seeing the number) — the core habit loop is: lift → auto-detect rep → confirm/adjust → move to next set.

---

## 6. Edit / Remove Sets and Reps

**New capability**, tied directly to #5:
- Every set and every rep within a set needs a **swipe-to-delete or edit icon**.
- Editing a set should allow adjusting: load, RPE, and (if a rep's velocity reading was clearly a sensor glitch) manually excluding that single rep from the set's average without deleting the whole set.
- Deleting a set/rep should immediately recompute: session totals, the L-V graph, and e1RM (since bad data currently pollutes all three).
- Add a confirmation step before delete (no accidental data loss mid-session).

---

## 7. "Iron Eye" — AI Fatigue Flagging & Suggestions

**Concept:** An always-on analysis layer that compares the athlete's current session against their own historical baseline (not generic population norms) and flags meaningful deviations.

**Signals to track per exercise:**
- Velocity trend within a session (is velocity dropping faster set-to-set than the athlete's own history at similar RPE?).
- Depth consistency, if depth data is available from camera (is depth shrinking rep-to-rep — a classic fatigue/form-breakdown sign?).
- Week-over-week comparison at matched load: e.g., "your velocity at 100kg is 8% slower than last week's 100kg sets."

**Output to athlete:** Short, plain-language flags + one actionable suggestion, e.g.:
- "Velocity dropped faster than usual this set — consider ending the session here."
- "Squat depth was shallower than your last 3 sessions at this weight — focus on hitting full depth or reduce load slightly."
- "Bar speed at this weight is lower than last week — this could mean accumulated fatigue; consider a lighter day or extra rest."

**Implementation note:** Start rule-based (thresholds + rolling averages of the athlete's own data) for the hackathon build — this is explainable, fast to implement, and matches judges' expectations of a working MVP. A learned model can come later once you have more logged data.

---

## 8. Velocity Bar Chart — Variable Height by Value

**Current bug:** All velocity bars render at the same height regardless of actual velocity value — the chart currently only encodes velocity through color/label, not height.

**Fix:** Bar height must be proportional to the velocity value, e.g.:
- Normalize bar height against a fixed chart max (say 2.5–3 m/s, since squat/bench/deadlift concentric velocities rarely exceed this) so a 1 m/s rep renders visibly shorter than a 2 m/s rep.
- Keep color-coding (e.g., green = fast/fresh, yellow = moderate, red = slow/fatigued) as a secondary cue on top of height, not a replacement for it.

---

## 9. Recovery Section — Rehab Engine (New Dashboard Tab)

**Placement:** New top-level tab alongside Profile and Workout on the dashboard.

**Core flow:**
1. Athlete opens Recovery tab and is prompted with a short Q&A: recent performance data (auto-pulled from logged sessions), plus manual input on any pain/injury (location, severity, when it started, aggravating movements).
2. Iron Eye cross-references this with the athlete's velocity/RPE/depth trends (from #7) to check whether the reported issue correlates with a recent performance drop.
3. Engine outputs a **basic rehab/load-management plan**: suggested load reduction %, exercises to avoid or substitute, and a return-to-full-load timeline/checkpoints.

**MVP scope for the hackathon build:** A rules-based decision tree is enough — a fixed set of common injury categories (knee, lower back, shoulder, elbow) each mapped to a pre-built substitution list and a conservative load-reduction schedule (e.g., -20% week 1, -10% week 2, full load week 3 if pain-free). This demonstrates the concept end-to-end without needing a trained medical model, which would be out of scope for the timeline and would need real clinical validation anyway — flag clearly in the app that this is not a substitute for a physiotherapist and is a general load-management guide only.

---

## Suggested Build Order (for the internal-round timeline)

1. Fix IMU+camera velocity fusion (#1) — everything else depends on accurate velocity data.
2. Fix L-V graph + simplify to one velocity metric per rep (#2).
3. Add RPE column (#4) — quick win, unlocks Iron Eye signal quality.
4. Rework set/rep UI + edit/delete (#5, #6) — core usability, judges will interact with this directly.
5. Improve e1RM (#3).
6. Fix velocity bar chart heights (#8) — quick visual polish.
7. Build Iron Eye fatigue flagging (#7).
8. Build Recovery/rehab engine tab (#9) — strongest differentiator, but depends on stable data from 1–6.
