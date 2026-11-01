# Roadmap

## Next: Camera Backend Validation

[Version 1.1.1 is released](RELEASE_NOTES.md). The maintainer approved starting SDK reassessment
with the [remaining device checks deferred](ENGINEERING_NOTES.md#release-111-and-sequencing-decision),
not marked passed.

1. Validate physical-shutter events and one test-image transfer through libgphoto2, with separate
   authorization and disposable fixtures. The [A6600 connection/summary check](ENGINEERING_NOTES.md#older-sony-camera-backend-probe)
   passes; transfer is not yet verified. SDK 2.02 returned no A6600 camera object.
2. Qualify RX100 and Intel behavior, then decide whether libgphoto2 or the Sony SDK should own
   the native path. Matching vendor headers/samples are now available; no backend replacement is approved yet.
3. Settle dependency/licensing, universal packaging and reconnect requirements before the smallest
   app-integration PR. Do not turn a diagnostic success into a production capture/transfer claim.

## Coming: Native USB Transfer

Define implementation from the backend validation and punchlist. Keep physical-shutter downloads aimed at the
selected folder and reuse the existing hot-folder ingestion pipeline. Cooperative remains the
production default. Remote shutter, live preview, new dependencies and SDK distribution changes
need a separate decision.

Keep deferred CORE, camera and Messages checks tracked in [BUGS.md](BUGS.md) and
[ENGINEERING_NOTES.md](ENGINEERING_NOTES.md). The [SDK entry gate](IMPLEMENTATION_SPEC.md#sdk-entry-gate)
records the sequencing exception; [usb_cam_sonySDK.md](usb_cam_sonySDK.md) remains historical investigation.