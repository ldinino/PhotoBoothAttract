# Core Bug Punchlist

CORE-001, CORE-002, CORE-004 and CORE-006 are closed; five items remain open. Baseline reviewed on 2026-10-27 at `1a7089b`.
See [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) for evidence and acceptance checks,
and [ROADMAP.md](ROADMAP.md) for sequencing. SDK findings are deferred until core cleanup is accepted.

## High Priority

- [x] **CORE-001: Folder lifecycle.** Fixed in PR #1 (`3b315b2`). Automated checks, Debug build and maintainer live-app smoke checks pass. [Notes](ENGINEERING_NOTES.md#core-001-folder-lifecycle)
- [x] **CORE-002: Preview/action mismatch.** Fixed in PR #2 (`f07a25c`). Revision-bound actions, 54 automated checks, Debug build and maintainer stale-selection UI check pass. [Notes](ENGINEERING_NOTES.md#core-002-preview-and-action-identity)

## Medium Priority

- [ ] **CORE-003: Attachment collisions.** Code fix merged in PR #7 (`6e2a68a`); 108 checks and Debug build pass. **Messages consumption and Intel/Apple Silicon draft validation deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-003-attachment-file-collisions)
- [x] **CORE-004: Missing filesystem events.** Fixed in PR #3 (`6fe6bde`). Automated checks, live FSEvents, Debug build and isolated real-window updates pass. [Notes](ENGINEERING_NOTES.md#core-004-filesystem-event-coverage)
- [ ] **CORE-005: Clear-folder failures.** Fixed in PR #6 (`93e1746`); 101 checks, Debug build and local confirmation/result-alert checks pass. **Intel/TV clear qualification deferred to the final CORE hardware pass.** [Notes](ENGINEERING_NOTES.md#core-005-clear-folder-failure-reporting)
- [x] **CORE-006: Blocking initial scan.** Fixed in PR #5 (`6960a86`). 90 automated checks, Debug/universal Release builds and maintainer-reported Intel/guest-display checks pass (2026-10-28). [Notes](ENGINEERING_NOTES.md#core-006-initial-scan-blocks-the-ui)
- [ ] **CORE-007: Ignored print failure.** Print & Digital opens the draft and dismisses the sheet regardless of the print result. **Source-confirmed; no print attempted.** [Notes](ENGINEERING_NOTES.md#core-007-print-and-digital-failure-handling)
- [ ] **CORE-008: Lost photo orientation.** Sharing JPEGs below the downscaling threshold drops EXIF rotation. **Reproduced.** [Notes](ENGINEERING_NOTES.md#core-008-share-image-orientation)

## Low Priority

- [ ] **CORE-009: Shifting partial grid.** With one photo, the guest tile is centered instead of occupying the top-left quadrant. **Reproduced by offscreen rendering.** [Notes](ENGINEERING_NOTES.md#core-009-partially-filled-guest-grid)

## Closing Items

Check an item only after its acceptance checks pass. Record the fixing commit or PR and
the actual verification in the linked engineering note. Source inspection, synthetic
checks, an app build, and hardware verification are different evidence, not substitutes.