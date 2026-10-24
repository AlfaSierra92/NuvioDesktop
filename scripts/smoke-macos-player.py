#!/usr/bin/env python3
"""Exercise the packaged macOS player's real lifecycle with a local video.

Usage: python3 scripts/smoke-macos-player.py /path/to/video.mp4
Opens a test window for 30 seconds, using temporary app data, then closes it.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("--app", type=Path, default=Path(__file__).resolve().parents[1] /
                        "composeApp/build/compose/binaries/main-release/app/Nuvio HTPC.app")
    parser.add_argument("--seconds", type=int, default=30)
    args = parser.parse_args()
    executable = args.app / "Contents/MacOS/Nuvio HTPC"
    if not args.video.is_file() or not executable.is_file():
        parser.error("Both a local video and a built Nuvio HTPC.app are required")
    if args.seconds < 10:
        parser.error("Run for at least 10 seconds to verify sustained progress")
    root = Path(tempfile.mkdtemp(prefix="nuvio-macos-playback-"))
    env = os.environ.copy()
    env["JAVA_TOOL_OPTIONS"] = f"-Dnuvio.desktop.dataDir={root}/data -Dnuvio.dev.localNatives=false"
    env["NUVIO_DESKTOP_SMOKE_PLAYER_URL"] = str(args.video.resolve())
    print(f"Test artifacts: {root}", flush=True)
    with (root / "console.log").open("w") as output:
        process = subprocess.Popen([str(executable.resolve())], env=env, stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + args.seconds
            while time.monotonic() < deadline and process.poll() is None:
                time.sleep(0.5)
            text = (root / "console.log").read_text(errors="replace")
            positions = [int(second) for second in re.findall(r"\(PlayerSmoke\) progress second=(\d+)", text)]
            checks = {
                "app remains running": process.poll() is None,
                "native player created exactly once": len(re.findall(r"\(PlaybackStartTrace\) id=\d+ nativeCreateReturned ", text)) == 1,
                "file loaded event delivered": "(PlaybackStartTrace)" in text and " fileLoaded " in text,
                "first frame delivered": re.search(r"\(PlaybackStartTrace\).*summary:.*playbackRestart", text) is not None,
                "playhead advances": len(set(positions)) >= 5 and max(positions, default=0) >= 5,
                "playhead never jumps backwards": positions == sorted(positions),
                "no missing JNI methods": "UnsatisfiedLinkError" not in text,
                "no player errors": "Error: (PlayerSmoke)" not in text,
            }
            for name, passed in checks.items():
                print(f"{'PASS' if passed else 'FAIL'}: {name}")
            if not all(checks.values()):
                raise SystemExit(f"Player smoke test failed; inspect {root / 'console.log'}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
