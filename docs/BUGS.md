# Bug Punchlist

CORE-001, CORE-002, CORE-004 and CORE-006 are closed; five core items remain open. Baseline reviewed on 2026-10-27 at `1a7089b`.
See [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) for evidence and acceptance checks,
and [ROADMAP.md](ROADMAP.md) for sequencing. SDK feature work remains deferred until core cleanup is accepted;
CAM-001 is a production tethering isolation fix, not an SDK feature milestone.

## Camera Workflow: High Priority

- [ ] **CAM-001: Unconditional SDK startup can interfere with Imaging Edge Desktop.**

**Reported:** During testing of the newly notarized app, the maintainer found that PBA's
unfinished native camera path can take the camera away from Sony Imaging Edge Desktop (IED).
At report time there was no setting to keep PBA out of camera resources while IED supplies the hot folder.

**Source verified before the fix (`682673b`):** [AppDelegate.swift](../PhotoBoothAttract/AppDelegate.swift) unconditionally
starts `SonyCameraManager` at launch. `start()` attempts to load the SDK dylibs and starts
`ICDeviceBrowser` even when SDK loading fails. `stop()` stops only the browser; loaded SDK
handles remain held until loader destruction. [SettingsView.swift](../PhotoBoothAttract/SettingsView.swift)
has no camera workflow preference. This confirms missing isolation, not which call claims
the physical camera or that native capture/transfer works.

**Required containment:** Add a persisted **Cooperative** / **Native** mode setting on the
assistant side, with a small `?` help button explaining both. Cooperative is the safe default,
including existing installations without a preference and invalid stored values: IED or another
tethering app owns the camera; PBA only watches the selected folder and must not initialize/load
the Sony SDK or create/start USB camera discovery. Native explicitly opts into the existing
experimental camera path; it does not promise working capture or transfer. Keep hot-folder
ingestion, printing and Messages drafts unchanged in both modes. Use restart-required mode
changes for this first fix so a UI selection cannot falsely promise release of loaded resources.

**Software verified:** Code fix merged in PR #14 (`decacd6`). Independent review passed all
16 camera-mode assertions, rejected the ungated temporary mutant with two expected failures,
and reran the correct checks successfully on merged main. All 170 shared regressions and eight
runner selector/reporting checks pass; the runner builds for arm64 and x86_64. The Debug build
succeeds with a non-blocking actor-isolation warning on the default backend factory. Actual
Cooperative app handlers and inspected screenshots verify the picker, help popover, restart
notice, unchanged active badge after saving Native, and visible Save button in an isolated copy.

**Hardware acceptance pending:** Verify IED transfer into the watched folder with Cooperative
selected, through PBA launch/relaunch and camera reconnect, on Intel and Apple Silicon. Verify
Native opt-in and return to Cooperative across a full quit/relaunch. No local camera/IED
reproduction or Native relaunch was performed; native capture and transfer remain unqualified.

## High Priority

- [x] **CORE-001: Folder lifecycle.** Fixed in PR #1 (`3b315b2`). Automated checks, Debug build and maintainer live-app smoke checks pass. [Notes](ENGINEERING_NOTES.md#core-001-folder-lifecycle)
- [x] **CORE-002: Preview/action mismatch.** Fixed in PR #2 (`f07a25c`). Revision-bound actions, 54 automated checks, Debug build and maintainer stale-selection UI check pass. [Notes](ENGINEERING_NOTES.md#core-002-preview-and-action-identity)

## Medium Priority

- [ ] **CORE-003: Attachment collisions.** Code fix merged in PR #7 (`6e2a68a`); 108 checks and Debug build pass. **Messages consumption and Intel/Apple Silicon draft validation deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-003-attachment-file-collisions)
- [x] **CORE-004: Missing filesystem events.** Fixed in PR #3 (`6fe6bde`). Automated checks, live FSEvents, Debug build and isolated real-window updates pass. [Notes](ENGINEERING_NOTES.md#core-004-filesystem-event-coverage)
- [ ] **CORE-005: Clear-folder failures.** Fixed in PR #6 (`93e1746`); 101 checks, Debug build and local confirmation/result-alert checks pass. **Intel/TV clear qualification deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-005-clear-folder-failure-reporting)
- [x] **CORE-006: Blocking initial scan.** Fixed in PR #5 (`6960a86`). 90 automated checks, Debug/universal Release builds and maintainer-reported Intel/guest-display checks pass (2026-10-28). [Notes](ENGINEERING_NOTES.md#core-006-initial-scan-blocks-the-ui)
- [ ] **CORE-007: Ignored print failure.** Code fix merged in PR #9 (`0f8b0b3`); 170 regression checks, 26 native-sheet checks and Debug build pass. **Printer and Intel/Apple Silicon qualification deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-007-print-and-digital-failure-handling)
- [ ] **CORE-008: Lost photo orientation.** Code fix merged in PR #8 (`e602762`); 162 checks and Debug build pass. **Messages orientation checks on Intel and Apple Silicon deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-008-share-image-orientation)

## Low Priority

- [ ] **CORE-009: Shifting partial grid.** Code fix merged in PR #10 (`d635b21`); 193 independent native guest/assistant checks, 170 regression checks and Debug build pass. **Intel/Apple Silicon display qualification deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-009-partially-filled-guest-grid)

## Closing Items

Check an item only after its acceptance checks pass. Record the fixing commit or PR and
the actual verification in the linked engineering note. Source inspection, synthetic
checks, an app build, and hardware verification are different evidence, not substitutes.