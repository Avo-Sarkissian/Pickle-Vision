# Pickle Vision

An iOS app that turns a single mounted iPhone into an automated referee for a pickleball court. Using on-device computer vision, it calls balls **in vs. out** and (in later phases) tracks ball speed, classifies swings and volleys, detects non-volley-zone ("kitchen") faults, tracks player movement, and keeps score.

It adapts to both **regulation pickleball courts** and improvised layouts — including playing on a tennis court using only the two front service boxes.

## Status

Early development. Design-first, built in phases.

- **Phase 0–1 · Foundation + Court Calibration** — in progress. See [`docs/superpowers/specs/2026-06-19-foundation-court-calibration-design.md`](docs/superpowers/specs/2026-06-19-foundation-court-calibration-design.md).
- Phase 2 · Ball tracking + IN/OUT calls
- Phase 3 · Players + joint tracking
- Phase 4 · Kitchen (NVZ) faults
- Phase 5 · Ball speed + swing/volley classification
- Phase 6 · Scorekeeping + player stats + session history

## Platform

Native Swift / SwiftUI, on-device (Vision + Core ML + AVFoundation). Target device: iPhone 16 Pro.
