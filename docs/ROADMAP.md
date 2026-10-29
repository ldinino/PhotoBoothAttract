# Roadmap

Core cleanup comes first. SDK work starts only after the core acceptance gate is met.
This roadmap is planned work, not release history or a claim that fixes have shipped.

## 1. Core Cleanup

**Status:** In progress. CORE-001, CORE-002, CORE-004 and CORE-006 are closed; five items in [BUGS.md](BUGS.md) remain open.

**Next implementation:** CORE-007 print-failure handling. CORE-003, CORE-005 and CORE-008 code fixes
are merged; their device checks remain pending. Finish the remaining code fixes before requesting
another Intel/TV pass. Hardware validation is batched at the end of CORE; pending device evidence stays
explicit and does not block the next implementation task.

1. Stabilize folder lifecycle and photo identity first: CORE-001 and CORE-002. Then cover filesystem events and move scans off the UI thread: CORE-004 and CORE-006.
2. Fix clear-folder reporting, attachment isolation, orientation and print-failure handling: CORE-005, CORE-003, CORE-008 and CORE-007.
3. Fix the partial guest grid: CORE-009. Exercise the assistant buttons, matching badges and display lifecycle end to end.
4. Tidy the touched core code as the fixes land. Remove dead paths and misleading helpers; prefer direct names and small, testable logic. Do not turn cleanup into an architecture rewrite or a visual redesign.

### Required Before Leaving CORE

- [ ] **Native UI validation runner and final hardware pass.** After the fixes, provide a script that
	drives the agreed CORE UI flows with synthetic fixtures and isolated preferences. Emit per-case
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

## 2. SDK Reassessment and Implementation

**Status:** Deferred until the core acceptance gate is met, including final hardware validation and
Developer ID signing/notarization readiness above.

After core cleanup, re-audit the current SDK code and locally installed Sony SDK with
relevant camera evidence. Then create a separate SDK punchlist and decide whether the
integration should be repaired or rewritten. Do not create that punchlist during core cleanup.

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