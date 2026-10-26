#!/usr/bin/env python3
"""Verify the macOS bridge's real HTTP headers and playback, without opening a window."""
import argparse
import http.server
import os
from pathlib import Path
import shlex
import subprocess
import sys
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Also exercise the packaged app and its default User-Agent")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    work = repo / "composeApp/build/native/macos-http-test"
    work.mkdir(parents=True, exist_ok=True)
    java = os.environ.get("JAVA_HOME") or subprocess.check_output(
        ["/usr/libexec/java_home", "-v", "21"], text=True).strip()
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "mpv"], text=True))
    frameworks = ["Cocoa", "Carbon", "CoreGraphics", "IOKit", "OpenGL", "QuartzCore",
                  "WebKit", "Metal", "Security", "GameController", "MediaPlayer"]
    binary = work / "http_headers_test"
    command = ["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-ObjC++", "-mmacosx-version-min=11.0",
               str(repo / "composeApp/src/desktopTest/native/macos/http_headers_test.mm"),
               f"-I{java}/include", f"-I{java}/include/darwin"]
    command += [item for framework in frameworks for item in ["-framework", framework]]
    command += flags + ["-o", str(binary)]
    with (work / "compile.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    clip = work / "clip.mp4"
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
                    "-i", "testsrc2=size=160x90:rate=24:duration=3", "-c:v", "mpeg4",
                    "-movflags", "+faststart", str(clip)], check=True)
    data = clip.read_bytes()
    expected = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "video/*, application/octet-stream",
        "X-Nuvio-Test": "comma,value\\path",
    }
    expected_headers = expected
    requests = []
    invalid = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_HEAD(self):
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()

        def do_GET(self):
            requests.append(self.path)
            if self.headers.defects or any(self.headers.get(k) != v for k, v in expected_headers.items()):
                invalid.append({k: self.headers.get(k) for k in expected_headers})
                self.send_response(400)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.path == "/redirect":
                self.send_response(307)
                self.send_header("Location", "/clip.mp4")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            start = int(self.headers.get("Range", "bytes=0-").split("=")[1].split("-")[0])
            self.send_response(206)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Range", f"bytes {start}-{len(data) - 1}/{len(data)}")
            self.send_header("Content-Length", str(len(data) - start))
            self.end_headers()
            try:
                self.wfile.write(data[start:])
            except (BrokenPipeError, ConnectionResetError):
                pass

    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            for path in ["/clip.mp4", "/redirect"]:
                subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}{path}"], check=True, timeout=15)
            if args.app:
                expected_headers = {"User-Agent": expected["User-Agent"]}
                # The packaged app must advance for 5s; give it enough media to avoid EOF.
                subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-stream_loop", "5",
                                "-i", str(clip), "-c", "copy", "-movflags", "+faststart",
                                str(work / "long.mp4")], check=True)
                data = (work / "long.mp4").read_bytes()
                subprocess.run([sys.executable, str(repo / "scripts/smoke-macos-player.py"),
                                f"http://127.0.0.1:{server.server_port}/redirect", "--app", str(args.app),
                                "--seconds", "18"], check=True, timeout=45)
        finally:
            server.shutdown()
            worker.join()
            if invalid:
                print("Rejected test headers:", invalid, flush=True)
    assert requests and not invalid, f"Malformed headers received: {invalid}"
    assert "/redirect" in requests and "/clip.mp4" in requests
    print("PASS: strict server accepts intact headers for direct and redirected media")


if __name__ == "__main__":
    main()
