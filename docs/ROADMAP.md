# Roadmap

## Next: Device Acceptance

The CORE fixes, native UI runner, notarization workflow and both Messages features are
implemented. Their remaining device checks are the current blocker.

1. Run the existing [native CORE UI runner](ENGINEERING_NOTES.md#native-core-ui-runner)
   on the older Intel Mac with the TV and on Apple Silicon. Repeat with one display.
2. Complete the device checks for CORE-003, CORE-005, CORE-007, CORE-008, CORE-009 and
   CAM-001 in [BUGS.md](BUGS.md), including Cooperative-mode Imaging Edge Desktop coexistence.
3. Qualify [Messages draft text](IMPLEMENTATION_SPEC.md#messages-draft-text) and
   [attachment metadata](IMPLEMENTATION_SPEC.md#messages-attachment-metadata) in real addressed
   and recipient-free drafts on both architectures. Authorize printing and delivery checks separately.
4. Verify [notarized distribution](IMPLEMENTATION_SPEC.md#notarized-distribution) from a
   quarantined download on Intel and Apple Silicon.

Record sanitized PASS/FAIL/SKIP results and equipment blockers in
[ENGINEERING_NOTES.md](ENGINEERING_NOTES.md). Close only checks with actual evidence;
the [CORE acceptance gate](IMPLEMENTATION_SPEC.md#core-acceptance-gate) remains open.

## Coming: SDK Reassessment

After CORE and both Messages features pass acceptance, audit the current camera code and
locally installed Sony SDK with device evidence. Create the SDK punchlist, decide repair
versus rewrite, then define the smallest implementation task. Preserve the hot-folder workflow.

See the [SDK entry gate](IMPLEMENTATION_SPEC.md#sdk-entry-gate) for boundaries;
[usb_cam_sonySDK.md](usb_cam_sonySDK.md) is investigation history, not acceptance evidence.