# Roadmap

Core cleanup comes first, followed by the two high-priority Messages features. SDK work
starts only after the core acceptance gate and both feature acceptance checks are met.
This roadmap is planned work, not release history or a claim that fixes have shipped.

## 1. Core Cleanup

**Status:** In progress. CORE-001, CORE-002, CORE-004 and CORE-006 are closed; five items in [BUGS.md](BUGS.md) remain open.

**Next implementation:** Native CORE UI validation runner. All CORE code fixes are merged;
CORE-003, CORE-005, CORE-007, CORE-008 and CORE-009 remain open for final device qualification.
Implement the runner below before the batched Intel/TV and Apple Silicon pass. Pending device
evidence stays explicit; the overall CORE gate is not complete.

1. Stabilize folder lifecycle and photo identity first: CORE-001 and CORE-002. Then cover filesystem events and move scans off the UI thread: CORE-004 and CORE-006.
2. Fix clear-folder reporting, attachment isolation, orientation and print-failure handling: CORE-005, CORE-003, CORE-008 and CORE-007.
3. Fix the partial guest grid: CORE-009 (merged in PR #10; device checks pending). Exercise the assistant buttons, matching badges and display lifecycle end to end.
4. Tidy the touched core code as the fixes land. Remove dead paths and misleading helpers; prefer direct names and small, testable logic. Do not turn cleanup into an architecture rewrite or a visual redesign.

### Required Before Leaving CORE

- [ ] **Native UI validation runner and final hardware pass.** After the fixes, provide a script that
	drives the agreed CORE UI flows with synthetic fixtures and isolated preferences, including pending
	cancellation and request-scoped sheet completion. Emit per-case
	PASS/FAIL/SKIP, a summary and a failing exit code for failures; skipped/manual checks are not passes.
	Use state-based waits, preserve event settings, restore permissions and remove fixtures, and close
	only app instances launched by the runner. Run the final pass on the older Intel Mac with the TV
	and on Apple Silicon. Keep physical printing and Messages consumption/delivery as separately
	authorized manual checks. Record only sanitized evidence and model/OS information, not identifiers
	or raw diagnostic exports. No automatic sending or real printing as routine automation.
- [ ] **Developer ID signing and notarized distribution.** The maintainer has an Apple Developer
	account; confirm Developer ID Application certificate access before implementation. Update the
	existing release workflow to sign the app and nested code, including required Sony SDK libraries,
	with secure timestamps and compatible hardened-runtime settings; notarize and staple the result.
	Verify signatures, universal app/SDK slices and Gatekeeper behavior from a quarantined download
	on Intel and Apple Silicon. Preserve the deployment target, non-sandboxed architecture and SDK
	licensing/distribution assumptions. Keep certificates, private keys and notary credentials out of
	Git and chat. This task does not authorize certificate export, OS security bypasses, release tags
	or publishing.

### Acceptance Gate

- [ ] All core punchlist items meet their linked acceptance checks, with fixing commits or PRs and verification recorded in [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md).
- [ ] Regression checks cover ordering, stable action selection, file replacement, incomplete writes, repeated events, folder changes and disappearing files. High-risk pure checks reject a deliberately wrong implementation.
- [ ] The actual Debug build passes. A real app launch confirms the affected controls, empty/error states, partial/full grids and single-display fallback.
- [ ] Live hot-folder events, secondary-display lifecycle and older Intel Mac responsiveness have device evidence. Authorized printer and Messages draft checks are recorded separately from build or simulated results.
- [ ] The final native UI runner reports its results, and Developer ID signing, notarization, stapling and downloaded-build Gatekeeper checks above are complete before work moves beyond CORE.
- [ ] Cleanup preserves original images except an explicitly confirmed clear, silent configured-printer 4x6 output, assistant-controlled sending, the current deployment target and non-sandboxed architecture.

Record equipment blockers explicitly; do not mark the gate complete on mocks alone.
SDK changes, new camera features, dependency changes and unrelated updater work are out of scope.

## 2. High-Priority Messages Features

After CORE acceptance, implement customizable draft text first, then metadata preservation.
Both features are high priority and must meet their acceptance checks before SDK implementation.
The CORE acceptance gate above remains unchanged; these features do not close pending CORE items.

### Customizable Messages Draft Text

**Status:** Code merged in PR #16 (`b19ce59`). Independent review passed 182 regression
assertions, rejected the blank-default mutant with three expected failures, and reran the
correct suite successfully, including on merged main. The arm64 Debug build and eight
isolated real-app Settings checks pass; Settings-only screenshots were inspected. Save,
unsaved dismissal, multiline text, blank text and relaunch persistence were verified.
Real Messages drafts on Intel and Apple Silicon remain untested. High priority; required
before SDK implementation. CORE acceptance remains open.

Allow the assistant to customize the message prefilled alongside a photo without changing
code. Both addressed and recipient-free drafts must use the same configured text. Messages
remains the editable system draft; the assistant still controls sending. Opening a draft is
not proof of sending or delivery.

**Behavior:** A global multiline plain-text setting in
[SettingsView.swift](../PhotoBoothAttract/SettingsView.swift), stored in `UserDefaults`,
is loaded when Settings opens and persisted only by Save. [MessageManager.swift](../PhotoBoothAttract/MessageManager.swift)
reads it for every draft, so both paths share one text/item builder and changes need no
restart. A missing or non-string value uses `Thank you for choosing SD Photography.
https://www.sd-photo.com/`; blank or whitespace-only text means photo only; other text is
kept exactly. Already-open drafts are unchanged. Templates, placeholders, per-customer data
and a preview sheet are out of scope.

**Acceptance:** Verify persistence, the agreed default/blank behavior and identical text
selection in both draft paths with focused automated checks. Separately verify that real
Messages drafts contain the configured text and photo, with and without a recipient, and
remain editable without automatic sending. Use synthetic photos and placeholder recipients;
do not send messages or record guest data as routine validation.

### Preserve Metadata in Messages Attachments

**Status:** Implemented on branch `feat/preserve-message-metadata`; pending audit and merge.
Software checks pass (see Acceptance). Real Messages drafts on Intel and Apple Silicon, and
recipient-copy retention, are deferred to the final hardware gate. High priority; required
before SDK implementation. CORE acceptance remains open.

Preserve standard photo metadata, especially camera-set Artist and Copyright information,
in the compressed photo handed to Messages. Apply to both addressed and recipient-free
drafts; keep original photo files untouched.

**Behavior:** In [MessageManager.swift](../PhotoBoothAttract/MessageManager.swift),
`compressedCopy` bakes orientation into downsampled pixels and writes the source's ImageIO
metadata (`CGImageMetadata`) with each encode, so the whole file, metadata included, is measured
against the 1 MB target. `outputMetadata` sets stored orientation to 1 and stored dimensions to the
output size; the embedded preview is not carried over. Vendor MakerNotes are not guaranteed to
round-trip. Standard XMP larger than one APP1 segment (about 64 KB) was not exercised.
Recipient-side metadata retention has not been verified.

**GPS policy (working decision, open for maintainer override):** a Messages setting in
[SettingsView.swift](../PhotoBoothAttract/SettingsView.swift), persisted by Save under
`messagesStripGPS`, removes GPS. Missing or non-boolean values remove it; only an explicit saved
off keeps it. Each attachment request reads the setting once. Removal covers the GPS property
dictionary and every GPS tag in the metadata, and the result is read back before use. When
stripping is on and the re-encode fails or GPS remains, no attachment is produced and an error is
logged; the original-byte fallback is used only when stripping is off.

**Scope:**
- Preserve standard EXIF/TIFF, IPTC and XMP metadata, including artist/creator and
	copyright/rights fields. Use ImageIO properties and metadata APIs; vendor MakerNotes are
	not guaranteed to round-trip.
- For re-encoded copies, normalize orientation to 1, update EXIF `PixelXDimension` and
	`PixelYDimension` and other stored dimensions to the actual output size, and remove or
	regenerate the embedded EXIF preview thumbnail. Do not retain conflicting orientation or
	dimension values in other metadata namespaces.
- Preserve the 3000 px longest-edge cap, no upscaling and existing JPEG quality policy.
	Include metadata bytes in each quality-search and fallback encode. The existing 1 MB
	sizing goal remains a target, not a guaranteed maximum.
- Offer assistant-only GPS stripping; confirm its default and persistence before
	implementation. Apply the chosen policy consistently, including the original-byte
	fallback. An encode failure must not silently bypass GPS stripping or modify the original.

**Acceptance:** Use synthetic fixtures with known EXIF/TIFF, IPTC and XMP fields, rotated
orientation, an embedded preview and dummy GPS. Read exported attachments back with
`CGImageSourceCopyPropertiesAtIndex` and `CGImageSourceCopyMetadataAtIndex`; compare preserved
fields, orientation 1, actual versus stored dimensions, preview handling and both GPS modes.
Cover missing metadata, metadata-heavy files near the size target, encode failures and
fallbacks in both draft paths. Verify original files remain byte-for-byte unchanged.

**Software evidence:** `bash scripts/check-folder-lifecycle.sh` reads production-generated
attachments back with `CGImageSourceCopyPropertiesAtIndex` and `CGImageSourceCopyMetadataAtIndex`:
attribution in TIFF, IPTC and XMP; orientations 1-8 and none at 2000 and 4000 px; resize; preview
removal; missing metadata; a metadata-heavy file; both policies; the preference defaults; forced
encode failure and undecodable-source fallbacks; and unchanged source bytes. Mutants that bypass
stripping, let stripping requests fall back to raw bytes, or leave stored orientation/dimension tags
stale are rejected. Both draft paths share `attachmentURL`, and the policy is read once in
`openDraft`. Settings save, unsaved dismissal and relaunch persistence were exercised in the real
Debug app. Messages itself was not opened.

**Pending hardware gate:** [core-ui-runner](../scripts/core-ui-runner/main.swift) lists the manual
checks. On Intel and Apple Silicon, inspect addressed and recipient-free drafts with synthetic
photos under both GPS settings, and compare sanitized fields with the source. Recipient copies
need separately authorized delivery evidence.

Export checks do not prove Messages or carriers preserve metadata in the recipient's copy;
that needs separate, authorized device evidence without automatic sending or guest data.
Print/save metadata behavior has not been reviewed for this request and is out of scope.

## 3. SDK Reassessment and Implementation

**Status:** Deferred until the core acceptance gate is met, including final hardware validation
and Developer ID signing/notarization readiness, and both high-priority Messages features above
are implemented and verified.

After core cleanup and both Messages features, re-audit the current SDK code and locally
installed Sony SDK with relevant camera evidence. Then create a separate SDK punchlist and
decide whether the integration should be repaired or rewritten. Do not create that punchlist
during core cleanup or Messages feature work.

[usb_cam_sonySDK.md](usb_cam_sonySDK.md) is historical investigation, not proof of working
initialization, camera control or transfer. Loading libraries or discovering a USB camera
does not establish that captured images reach the app.

Keep the hot-folder product working while SDK work proceeds. Do not add direct capture,
automatic sending, SDK distribution changes or new OS requirements without an explicit decision.
SDK scope, acceptance checks and sequencing will be defined with its later punchlist,
not inferred from old milestone completion labels.

## References

- [BUGS.md](BUGS.md): glanceable core punchlist.
- [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md): evidence and acceptance checks.
- [IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md): original requirements and implementation history.
- [RELEASE_NOTES.md](RELEASE_NOTES.md): recorded release history only.