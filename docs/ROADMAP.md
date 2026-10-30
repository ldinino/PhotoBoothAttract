# Roadmap

## Next: SDK Reassessment

[Version 1.1.1 is released](RELEASE_NOTES.md). The maintainer approved starting SDK reassessment
with the [remaining device checks deferred](ENGINEERING_NOTES.md#release-111-and-sequencing-decision),
not marked passed.

1. Obtain matching Sony SDK headers and sample sources locally; the configured SDK tree
   currently contains runtime libraries only. See the [source audit](ENGINEERING_NOTES.md#sdk-reassessment).
2. Confirm SDK version, supported cameras, Intel/Apple Silicon compatibility and the documented
   initialization, session and download APIs. Library loading and USB discovery are not transfer proof.
3. Use the audit and relevant camera evidence to define the SDK punchlist, choose repair versus
   replacement of the unfinished native path, and select the smallest testable implementation.

## Coming: Native USB Transfer

Define implementation from the SDK punchlist. Keep physical-shutter downloads aimed at the
selected folder and reuse the existing hot-folder ingestion pipeline. Cooperative remains the
production default. Remote shutter, live preview, new dependencies and SDK distribution changes
need a separate decision.

Keep deferred CORE, camera and Messages checks tracked in [BUGS.md](BUGS.md) and
[ENGINEERING_NOTES.md](ENGINEERING_NOTES.md). The [SDK entry gate](IMPLEMENTATION_SPEC.md#sdk-entry-gate)
records the sequencing exception; [usb_cam_sonySDK.md](usb_cam_sonySDK.md) remains historical investigation.