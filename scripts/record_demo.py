#!/usr/bin/env python3
"""Record the real native UI test, stopping immediately after its flow passes.
Requires a prior successful build/test and demo-document.png as the newest library image.
The movie is not a fabricated screen animation. Any trimming is done separately.
"""
import argparse, pathlib, signal, subprocess, time
parser = argparse.ArgumentParser()
parser.add_argument('--device', required=True)
parser.add_argument('--derived-data', default='SignedDerivedData')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
(root / 'artifacts').mkdir(exist_ok=True)
raw = root / 'artifacts' / 'demo-raw.mov'
log = root / 'artifacts' / 'recording-test.log'
if raw.exists():
    raise SystemExit('Move the existing raw recording before starting a new one.')
video = subprocess.Popen(['xcrun','simctl','io',args.device,'recordVideo','--codec=h264',str(raw)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
command = ['xcodebuild','-project','SnapNest.xcodeproj','-scheme','SnapNest',
           '-destination',f'platform=iOS Simulator,id={args.device}',
           '-derivedDataPath', args.derived_data,
           '-only-testing:SnapNestUITests/SnapNestUITests/testCaptureOfflineThenReconnectAndRelaunch',
           'test-without-building']
try:
    with log.open('w') as stream:
        test = subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 150
        passed = False
        while time.monotonic() < deadline:
            contents = log.read_text()
            if "testCaptureOfflineThenReconnectAndRelaunch]' passed" in contents:
                passed = True; break
            if "testCaptureOfflineThenReconnectAndRelaunch]' failed" in contents or test.poll() is not None:
                break
            time.sleep(0.25)
        if not passed:
            test.terminate()
            raise RuntimeError('Native flow did not pass; recording is not submission evidence. Inspect recording-test.log.')
finally:
    video.send_signal(signal.SIGINT)
    try: video.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        video.terminate(); video.communicate(timeout=10)
print(f'Recorded passing native flow: {raw}')
