# Pickle Vision

An iOS app that turns a single mounted iPhone into an automated referee for a pickleball court. Using on-device computer vision, it calls balls **in vs. out** and (in later phases) tracks ball speed, classifies swings and volleys, detects non-volley-zone ("kitchen") faults, tracks player movement, and keeps score.

It adapts to both **regulation pickleball courts** and improvised layouts, including playing on a tennis court using only the two front service boxes.

## Status

Early development. Design-first, built in phases. Full roadmap: [`docs/superpowers/ROADMAP.md`](docs/superpowers/ROADMAP.md).

Done so far (the on-device pieces still pending a real-court verification run):

- **Phase 0-1 · Foundation** - app shell, camera capture, manual court calibration, `CourtModel`, the Direction-B UI, capture profiles, thermal policy.
- **Phase A · Session + Capture** - tap a saved court, record a clip bound to it, clip library.
- **Phase B1 · In/Out core (deterministic)** - `Tracker` -> `BounceDetector` -> `LineJudge` -> `RefereeCore`: in/out + too-close-to-call from a ball trajectory, pure geometry/physics.
- **Phase B5 · Eval harness** - scores pipeline output against tap-test ground truth (the works-on-a-real-court gate).

Next:

- **Phase B2 · Ball detector** - the one ML piece (locate the ball per frame), developed against real recorded clips.
- **Phase B3 · In/Out pipeline**, **B4 · On-device + live**, then players + kitchen faults, scoring, stats, and a review experience (Phases C-H).

## Platform

Native Swift / SwiftUI, on-device (Vision + Core ML + AVFoundation). Target device: iPhone 16 Pro.
