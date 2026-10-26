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
    parser.add_argument("video", help="Local video file or HTTP(S) media URL")
    parser.add_argument("--app", type=Path, default=Path(__file__).resolve().parents[1] /
                        "composeApp/build/compose/binaries/main-release/app/Nuvio HTPC.app")
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--hdr-cycle", action="store_true", help="Cycle HDR modes repeatedly and check the final output encoding")
    parser.add_argument("--pip-cycle", action="store_true", help="Enter/exit PiP three times from windowed playback and verify clean shutdown")
    parser.add_argument("--expect-hdr-source", action="store_true", help="Require HDR input detection during the mode cycle")
    args = parser.parse_args()
    executable = args.app / "Contents/MacOS/Nuvio HTPC"
    remote = re.match(r"^https?://", args.video, re.IGNORECASE) is not None
    video = Path(args.video)
    if (not remote and not video.is_file()) or not executable.is_file():
        parser.error("A video file or HTTP(S) URL and a built Nuvio HTPC.app are required")
    if args.seconds < 10:
        parser.error("Run for at least 10 seconds to verify sustained progress")
    root = Path(tempfile.mkdtemp(prefix="nuvio-macos-playback-"))
    env = os.environ.copy()
    env["JAVA_TOOL_OPTIONS"] = f"-Dnuvio.desktop.dataDir={root}/data -Dnuvio.dev.localNatives=false"
    env["NUVIO_DESKTOP_SMOKE_PLAYER_URL"] = args.video if remote else str(video.resolve())
    if args.hdr_cycle:
        env["NUVIO_DESKTOP_SMOKE_HDR_CYCLE"] = "1"
    if args.pip_cycle:
        env["NUVIO_DESKTOP_SMOKE_PIP_CYCLE"] = "1"
        profile = root / "data"
        profile.mkdir()
        (profile / "nuvio_window_state.properties").write_text("start_windowed=true\n")
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
                "app lifecycle completes as expected": process.poll() == 0 if args.pip_cycle else process.poll() is None,
                "native player created exactly once": len(re.findall(r"\(PlaybackStartTrace\) id=\d+ nativeCreateReturned ", text)) == 1,
                "file loaded event delivered": "(PlaybackStartTrace)" in text and " fileLoaded " in text,
                "first frame delivered": re.search(r"\(PlaybackStartTrace\).*summary:.*playbackRestart", text) is not None,
                "playhead advances": len(set(positions)) >= 5 and max(positions, default=0) >= 5,
                "playhead never jumps backwards": positions == sorted(positions),
                "no missing JNI methods": "UnsatisfiedLinkError" not in text,
                "no player errors": "Error: (PlayerSmoke)" not in text,
            }
            if args.pip_cycle:
                checks["three PiP cycles keep the video advancing"] = "PASS: (PipSmoke) three enter/exit cycles with advancing playback" in text
                checks["native player shuts down cleanly"] = "(DesktopShutdown) native player cleanup completed=true" in text
            if args.hdr_cycle:
                modes = re.findall(r"\(MacosHdr\) mode=(\w+) sourceHdr=(\d) output=(\w+) primaries=([\w.]+) transfer=([\w.]+) reason=mode-change", text)
                tonemap = [row for row in modes if row[0] == "AlwaysTonemap"]
                passthrough = [row for row in modes if row[0] == "AlwaysPassthrough"]
                checks["three HDR mode cycles completed"] = len(tonemap) >= 3 and len(passthrough) >= 3 and modes[-1][0] == "Auto"
                checks["tonemap restores SDR layer and pixels"] = bool(tonemap) and all(row[2:] == ("sdr", "bt.709", "srgb") for row in tonemap)
                checks["Auto restores the same encoding as passthrough"] = bool(passthrough) and modes[-1][1:] == passthrough[-1][1:]
                checks["layer encoding agrees with MPV"] = bool(modes) and all(
                    row[2:] == (("hdr", "bt.2020", "pq") if row[2] == "hdr" else ("sdr", "bt.709", "srgb"))
                    for row in modes
                )
                if args.expect_hdr_source:
                    checks["HDR source detected throughout the cycle"] = bool(modes) and all(row[1] == "1" for row in modes if row[0] != "Auto" or row != modes[0])
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
