# Roadmap

## Next: Camera Backend Validation

[Version 1.1.1 is released](RELEASE_NOTES.md). The maintainer approved starting SDK reassessment
with the [remaining device checks deferred](ENGINEERING_NOTES.md#release-111-and-sequencing-decision),
not marked passed.

1. Qualify RX100 and Intel physical-shutter transfers, repeated arrivals and reconnect recovery.
   The [A6600 transfer and ingestion check](ENGINEERING_NOTES.md#older-sony-camera-backend-probe)
   passes once on Apple Silicon; the released app has no libgphoto2 backend yet.
2. Confirm card/RAM behavior without assuming SD bypass, then choose the native backend.
   A6600 transfer used `card+sdram`; Sony SDK 2.02 returned no A6600 camera object.
3. Settle dependency/licensing, universal packaging and reconnect requirements before the smallest
   app-integration PR. Do not turn a diagnostic success into a production capture/transfer claim.

## Coming: Native USB Transfer

Define implementation from the backend validation and punchlist. Keep physical-shutter downloads aimed at the
selected folder and reuse the existing hot-folder ingestion pipeline. Cooperative remains the
production default. Follow the [camera-owned copy workflow](IMPLEMENTATION_SPEC.md#native-camera-copy-workflow).
Live preview is optional follow-up work; remote shutter, new dependencies and SDK distribution changes need a separate decision.

Keep deferred CORE, camera and Messages checks tracked in [BUGS.md](BUGS.md) and
[ENGINEERING_NOTES.md](ENGINEERING_NOTES.md). The [SDK entry gate](IMPLEMENTATION_SPEC.md#sdk-entry-gate)
records the sequencing exception; [usb_cam_sonySDK.md](usb_cam_sonySDK.md) remains historical investigation.