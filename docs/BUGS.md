# Core Bug Punchlist

CORE-001 is closed; eight items remain open. Baseline reviewed on 2026-10-27 at `1a7089b`.
See [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) for evidence and acceptance checks,
and [ROADMAP.md](ROADMAP.md) for sequencing. SDK findings are deferred until core cleanup is accepted.

## High Priority

- [x] **CORE-001: Folder lifecycle.** Fixed in PR #1 (`3b315b2`). Automated checks, Debug build and maintainer live-app smoke checks pass. [Notes](ENGINEERING_NOTES.md#core-001-folder-lifecycle)
- [ ] **CORE-002: Preview/action mismatch.** Replacing a file leaves its old thumbnail, while print/share actions read the replacement image. **Reproduced.** [Notes](ENGINEERING_NOTES.md#core-002-preview-and-action-identity)

## Medium Priority

- [ ] **CORE-003: Attachment collisions.** Different photos with the same basename overwrite the same temporary share file. **File overwrite reproduced; Messages consumption unverified.** [Notes](ENGINEERING_NOTES.md#core-003-attachment-file-collisions)
- [ ] **CORE-004: Missing filesystem events.** Deletions and rename-only arrivals are not handled by the watcher callback. **Source-confirmed; live delivery unverified.** [Notes](ENGINEERING_NOTES.md#core-004-filesystem-event-coverage)
- [ ] **CORE-005: Clear-folder failures.** Failed deletions still report success and remove surviving photos from the interface. **Reproduced.** [Notes](ENGINEERING_NOTES.md#core-005-clear-folder-failure-reporting)
- [ ] **CORE-006: Blocking initial scan.** Startup and folder selection enumerate files and generate thumbnails on the UI thread. **Source-confirmed; event-Mac impact unmeasured.** [Notes](ENGINEERING_NOTES.md#core-006-initial-scan-blocks-the-ui)
- [ ] **CORE-007: Ignored print failure.** Print & Digital opens the draft and dismisses the sheet regardless of the print result. **Source-confirmed; no print attempted.** [Notes](ENGINEERING_NOTES.md#core-007-print-and-digital-failure-handling)
- [ ] **CORE-008: Lost photo orientation.** Sharing JPEGs below the downscaling threshold drops EXIF rotation. **Reproduced.** [Notes](ENGINEERING_NOTES.md#core-008-share-image-orientation)

## Low Priority

- [ ] **CORE-009: Shifting partial grid.** With one photo, the guest tile is centered instead of occupying the top-left quadrant. **Reproduced by offscreen rendering.** [Notes](ENGINEERING_NOTES.md#core-009-partially-filled-guest-grid)

## Closing Items

Check an item only after its acceptance checks pass. Record the fixing commit or PR and
the actual verification in the linked engineering note. Source inspection, synthetic
checks, an app build, and hardware verification are different evidence, not substitutes.