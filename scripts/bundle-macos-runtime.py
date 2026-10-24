#!/usr/bin/env python3
"""Copy a Mach-O library's dependencies and make them load from the same folder."""
from pathlib import Path
import shutil
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def system_library(name):
    return name.startswith(("/System/Library/", "/usr/lib/"))


def dependencies(binary):
    return [line.strip().split(" (compatibility")[0]
            for line in run("otool", "-L", str(binary)).splitlines()[1:]]


def resolve(name, binary):
    if name.startswith("@loader_path/"):
        return binary.parent / name[len("@loader_path/"):]
    if name.startswith("@rpath/"):
        lines = run("otool", "-l", str(binary)).splitlines()
        for index, line in enumerate(lines):
            if line.strip() == "cmd LC_RPATH":
                root = lines[index + 2].strip().split("path ", 1)[1].split(" (offset")[0]
                root = root.replace("@loader_path", str(binary.parent))
                candidate = Path(root) / name[len("@rpath/"):]
                if candidate.is_file() or system_library(str(candidate)):
                    return candidate
        raise RuntimeError(f"Cannot resolve {name} from {binary}")
    return Path(name)


def bundle(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    pending = [source.resolve()]
    copied = {}
    while pending:
        original = pending.pop()
        target = destination / original.name
        if target.name in copied:
            if copied[target.name] != original:
                raise RuntimeError(f"Conflicting library names: {original} and {copied[target.name]}")
            continue
        copied[target.name] = original
        shutil.copy2(original, target)
        target.chmod(target.stat().st_mode | 0o200)
        identity = run("otool", "-D", str(original)).splitlines()[1:]
        for name in dependencies(original):
            if name in identity or system_library(name):
                continue
            dependency = resolve(name, original)
            if system_library(str(dependency)):
                continue
            dependency = dependency.resolve(strict=True)
            pending.append(dependency)
            subprocess.check_call(["install_name_tool", "-change", name,
                                   f"@loader_path/{dependency.name}", str(target)])
        subprocess.check_call(["install_name_tool", "-id", f"@loader_path/{target.name}", str(target)])
        # Rewriting Mach-O load commands invalidates the original signature. Apple Silicon
        # requires at least an ad-hoc signature, including for local development builds.
        subprocess.check_call(["codesign", "--force", "--sign", "-", str(target)])
    for old in destination.iterdir():
        if old.is_file() and old.name not in copied and old.name != "runtime-files.txt":
            old.unlink()
    names = sorted(name for name in copied if name != source.name)
    (destination / "runtime-files.txt").write_text("\n".join(names) + "\n")
    print(f"Bundled macOS player and {len(names)} dependencies in {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: bundle-macos-runtime.py BRIDGE OUTPUT_DIRECTORY")
    bundle(Path(sys.argv[1]), Path(sys.argv[2]))
