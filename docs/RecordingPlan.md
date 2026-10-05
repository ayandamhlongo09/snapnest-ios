# 60-second recording plan

Use a fresh install on a simulator or device with a non-sensitive sample image. Never record an actual identity document for this proof of concept.

- Open Demo controls and enable Go offline.
- Select the SnapNest demo document through the native photo library. Show Waiting to send.
- Disable Go offline. Show Sent before relaunch and the unique acceptance count.
- Relaunch. Show Sent and the unchanged acceptance count.

Use the passing native UI scenario through `scripts/record_demo.py`. Trim only setup time so the final movie stays under 60 seconds; retain the actual state transitions.

The endpoint is an in-app persistent mock. This video demonstrates photo selection, durable saving, reconnection, confirmation, and sent-state persistence. It does not demonstrate an iOS force quit during a write or real HTTP delivery.
