# Recording Overhaul Spec (macOS 15+)

## Document Status
- Owner: ScreenCapture engineering
- Branch: `mcsdevv/recording-overhaul`
- Version: v1
- Date: 2026-02-08

## Executive Summary
The current recording implementation has correctness and reliability failures (non-functional pause, unstable timer UI, memory-heavy GIF capture, and settings/doc drift). This spec defines a full rewrite of recording around a production-grade session architecture:
- macOS 15+ first-class path using ScreenCaptureKit recording primitives.
- GIF generation via post-process video export with `ffmpeg` (not raw frame buffering).
- State-machine-driven session lifecycle and deterministic teardown.
- Accurate, wired recording settings with strict capability checks.
- Reliability instrumentation, automated validation, and staged rollout.

## Product Decisions (Confirmed)
1. Target platform priority: macOS 15+.
2. `ffmpeg` is approved for GIF export.
3. Pause/Resume will be hidden until implemented correctly end-to-end.
4. GIF flow: record video first, then export GIF.

## Goals
1. Zero corrupted output files in normal operation.
2. Correct and responsive recording duration UI (sub-second updates).
3. Stable long recordings without unbounded memory growth.
4. Deterministic behavior for start, stop, cancel, and app termination.
5. GIF output quality and file size competitive with best-in-class tools.
6. Documentation and app settings match actual behavior.

## Non-Goals (Phase 1)
1. Shipping Pause/Resume UI before true media timeline support exists.
2. Adding non-macOS capture backends.
3. Reworking screenshot or annotation architecture outside recording touchpoints.

## Current Problems (From Review)
1. Pause toggles UI state only, media capture does not pause.
2. Timer/UI update path is brittle and can appear frozen.
3. GIF capture buffers all frames in memory and encodes at stop.
4. GIF encoder lacks dedupe/delta/palette pipeline optimization.
5. Recording settings are mostly not wired into capture/encode behavior.
6. Audio toggles in UI/docs do not map cleanly to capture behavior.
7. Tests are shallow for recording correctness and broken in related suites.

## Requirements

### Functional
1. Support area, fullscreen, and window recording.
2. Support MP4 output (primary) and GIF output (derived export).
3. Support configurable recording FPS and quality presets.
4. Support microphone/system audio toggles with explicit availability checks.
5. Show reliable recording state and elapsed duration.
6. Provide cancel-safe behavior and app-termination-safe finalization.

### Reliability
1. No unbounded frame retention in memory.
2. Atomic output file finalization (`.partial` to final rename).
3. Guaranteed session cleanup even on stream/output errors.
4. Capture permission failures surfaced with actionable UI.

### Performance
1. Main thread never blocked by encode or export operations.
2. 60 FPS capture mode should keep dropped frame rate below 1% in normal desktop workloads.
3. GIF export should run off-main-thread and expose progress.

## High-Level Architecture

### Core Types
1. `RecordingSessionCoordinator` (MainActor)
- Public API for start/stop/cancel/status.
- Owns session state machine.
- Bridges to UI (notifications/observable state).

2. `RecordingSessionState`
- States: `idle`, `selecting`, `starting`, `recording`, `stopping`, `exportingGif`, `completed`, `failed`, `cancelled`.
- Illegal transitions rejected with structured errors.

3. `RecordingConfig`
- Input: user settings + mode (`video` or `gif`) + region/window filter.
- Output: fully resolved stream and export settings.

4. `CaptureEngine` protocol
- `start(config:)`, `stop()`, `cancel()`, `statusPublisher`.
- Implementations:
  - `SCRecordingOutputEngine` (macOS 15+ primary).
  - `AVAssetWriterEngine` (macOS 14 fallback compatibility).

5. `GifExportService`
- Consumes finalized temporary MP4 and generates GIF using `ffmpeg`.
- Progress parsing + cancellation support.

6. `RecordingFileManager`
- Creates session directories.
- Handles `.partial` lifecycle and final naming.
- Writes metadata sidecar (json).

### Data Flow
1. User starts recording -> selection completed -> `RecordingConfig` resolved.
2. `CaptureEngine` writes MP4 to `*.partial.mp4`.
3. Stop/cancel invoked -> engine finalizes or tears down.
4. On success:
- Video mode: rename `*.partial.mp4` -> final `.mp4`, save capture item.
- GIF mode: keep finalized temp mp4, run `GifExportService`, save `.gif`, optionally retain mp4 based on setting.
5. Publish completion event with metadata.

## macOS 15+ Capture Path
1. Prefer ScreenCaptureKit recording output path for stability and reduced custom muxing complexity.
2. Configure stream explicitly from resolved settings (fps, cursor, audio sources, capture rect/window).
3. Enforce bounded queue/backpressure behavior.
4. Validate sample and recording statuses, propagate failures to session state.
5. Keep fallback engine available for older environments or feature gaps.

## GIF Export Strategy (`ffmpeg`)

### Why this design
1. Avoids live frame buffering and memory blowups.
2. Produces better color and size outcomes using palette workflow.
3. Keeps capture path simple and reliable.

### Pipeline
1. Source: finalized MP4 from session output.
2. Stage A palette generation:
- `ffmpeg -y -i input.mp4 -vf "fps=<fps>,scale=<w>:-1:flags=lanczos,palettegen=stats_mode=diff" palette.png`
3. Stage B GIF encode:
- `ffmpeg -y -i input.mp4 -i palette.png -lavfi "fps=<fps>,scale=<w>:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" output.gif`
4. Optional optimization pass for small size presets:
- lossy frame decimation or lower fps/width before palette generation.

### Preset Mapping
1. GIF Low: 10 fps, width 640.
2. GIF Medium: 15 fps, width 960.
3. GIF High: 20 fps, width 1280.
4. GIF Original: source fps cap + source width cap policy (guardrail max width to avoid pathological files).

### Failure Handling
1. If `ffmpeg` unavailable:
- Show clear error with install guidance and fallback message.
2. If export fails:
- Preserve source mp4 for recovery.
- Emit structured error and telemetry.

## Pause/Resume Policy
1. Phase 1: remove/hide Pause control from UI and docs.
2. Phase 2 (future): implement true pause via segmented recording + concat during finalize, including audio sync validation.
3. No partial pause semantics accepted.

## Settings Contract (Must Be Real)

### Video
1. `recordingQuality`: low/medium/high -> resolution + bitrate ladder.
2. `recordingFPS`: 30/60 -> stream frame interval and encode assumptions.
3. `showCursor`: wired to stream config.

### Audio
1. `recordMicrophone`: enable microphone capture path when available.
2. `recordSystemAudio`: enable app/system audio path when available.
3. If unavailable, UI shows disabled state + explanation.

### GIF
1. `gifFPS`: actually controls export fps.
2. `gifQuality`: actually controls export width and optional optimization knobs.

## UI/UX Changes
1. Recording control bar must bind to a single observable session model.
2. Timer sourced from monotonic clock and session start time.
3. Remove pause button until true implementation ships.
4. For GIF recordings, show post-stop state: `Exporting GIF...` with progress.
5. On failure, show actionable toast/alert with reason and log reference.

## Storage and Metadata
1. Use unique session ID in temp filenames to prevent collisions.
2. Write metadata:
- capture mode, fps, dimensions, duration, dropped-frame estimate, audio flags, encode path.
3. Save capture item only after final file exists and passes basic validation.
4. Optional cleanup policy for intermediate mp4 after successful GIF export.

## Observability
1. Structured logs per session ID.
2. Metrics to record:
- startup latency, stop latency, export latency.
- dropped frames.
- final file size and duration.
- error class and stage.
3. Add debug command to dump latest session summary.

## Testing and Validation Plan

### Unit Tests
1. State machine transitions and illegal transition rejection.
2. Config mapping from settings to engine/export parameters.
3. File manager atomic finalize logic.
4. GIF export command generation.

### Integration Tests
1. Start/stop video recording creates playable file with non-zero duration.
2. GIF mode records mp4 then creates non-empty gif.
3. Cancel path leaves no orphan `.partial` files.
4. App termination during recording finalizes or safely aborts without crash.

### Stress/Soak
1. 100 sequential short recordings (video and gif modes).
2. Long recording memory stability test.
3. Multi-display and window capture stability sweeps.

### QA Acceptance Gates
1. No corrupted outputs in 100-run soak.
2. Timer updates continuously while recording.
3. Settings visibly affect output characteristics.
4. GIF export success rate >= 99% when `ffmpeg` present.

## Rollout Plan

### Phase 0: Foundations
1. Introduce new session model and engine protocol.
2. Wire timer/state to single source of truth.
3. Hide Pause UI.

### Phase 1: Video Reliability
1. Implement macOS 15+ primary engine.
2. Add finalize/atomic file handling.
3. Wire real settings contract.

### Phase 2: GIF Rebuild
1. Remove live GIF frame collector path.
2. Add `GifExportService` with `ffmpeg` pipeline.
3. Add progress UI and robust fallback errors.

### Phase 3: Hardening
1. Add telemetry and stress harness.
2. Fix all doc/spec drift.
3. Run soak tests and close release blockers.

## Migration Plan
1. Keep existing public triggers (`toggleRecording`, `toggleGIFRecording`) and route internally to new coordinator.
2. Maintain existing capture history schema, extending metadata non-breaking.
3. Keep macOS 14 fallback engine during transition period.

## Risks and Mitigations
1. `ffmpeg` binary availability.
- Mitigation: startup check + explicit user guidance + surfaced failure state.
2. ScreenCaptureKit behavior differences across macOS versions.
- Mitigation: macOS 15+ primary path + targeted fallback + integration matrix.
3. Audio route variability.
- Mitigation: capability probing + explicit UI state + logging.

## Definition of Done
1. Old live GIF frame buffering path is removed.
2. Pause is either fully correct or not present in UI/docs (Phase 1 target: not present).
3. Recording settings are fully wired and tested.
4. All acceptance gates pass.
5. Docs (`FEATURES.md` + recording docs) match shipped behavior exactly.

## Implementation Checklist
1. Add `RecordingSessionCoordinator` and state machine.
2. Add `RecordingConfig` resolver from user settings.
3. Build macOS 15+ capture engine.
4. Add fallback engine abstraction (macOS 14 compatibility).
5. Add `RecordingFileManager` with atomic finalize.
6. Add `GifExportService` + progress parsing + cancel support.
7. Remove/hide pause controls and stale docs.
8. Wire settings end-to-end.
9. Add unit/integration/stress tests.
10. Update docs and feature matrix.
