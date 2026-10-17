#!/usr/bin/env python3
"""Copy Homebrew's mpv and every non-system dylib it needs into Candela.app, so users don't need Homebrew.

    scripts/bundle_mpv.py build/Candela.app

Result:
    Contents/MacOS/mpv                      the mpv binary
    Contents/Frameworks/*.dylib             its libraries, install names rewritten to @executable_path/../Frameworks
    Contents/Resources/vulkan/icd.d/...     MoltenVK driver manifest (the app points VK_DRIVER_FILES at it)
"""
import json
import os
import re
import shutil
import subprocess
import sys

BREW = subprocess.run(["brew", "--prefix"], capture_output=True, text=True).stdout.strip() or "/opt/homebrew"
SYSTEM = ("/usr/lib/", "/System/")


def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True, check=True).stdout
    return [l.strip().split(" (")[0] for l in out.splitlines()[1:] if l.strip()]


def rpaths(path):
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True, check=True).stdout
    return re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset", out)


def resolve(ref, owner):
    """Turn @rpath/@loader_path references into real files."""
    if ref.startswith("@loader_path/"):
        return os.path.realpath(os.path.join(os.path.dirname(owner), ref[len("@loader_path/"):]))
    if ref.startswith("@rpath/"):
        name = ref[len("@rpath/"):]
        for rp in rpaths(owner) + [f"{BREW}/lib"]:
            rp = rp.replace("@loader_path", os.path.dirname(owner))
            cand = os.path.join(rp, name)
            if os.path.exists(cand):
                return os.path.realpath(cand)
        raise SystemExit(f"can't resolve {ref} from {owner}")
    return os.path.realpath(ref)


def main(app):
    macos = os.path.join(app, "Contents/MacOS")
    fw = os.path.join(app, "Contents/Frameworks")
    os.makedirs(fw, exist_ok=True)

    mpv_src = os.path.realpath(shutil.which("mpv") or f"{BREW}/bin/mpv")
    mpv_dst = os.path.join(macos, "mpv")
    shutil.copy2(mpv_src, mpv_dst)
    os.chmod(mpv_dst, 0o755)

    # The Vulkan loader dlopen()s MoltenVK via its ICD manifest, so otool never sees it: add it explicitly.
    moltenvk = os.path.realpath(f"{BREW}/lib/libMoltenVK.dylib")

    copied = {}          # real source path -> bundled file name
    queue = [(mpv_dst, mpv_src), (None, moltenvk)]
    seen = set()
    while queue:
        dst, src = queue.pop()
        if dst is None:  # a library we still have to copy
            name = os.path.basename(src)
            dst = os.path.join(fw, name)
            if src in copied:
                continue
            shutil.copy2(src, dst)
            os.chmod(dst, 0o755)
            copied[src] = name
            subprocess.run(["install_name_tool", "-id", f"@executable_path/../Frameworks/{name}", dst],
                           check=True, capture_output=True)
        if dst in seen:
            continue
        seen.add(dst)
        for ref in deps(dst):
            if ref.startswith(SYSTEM) or ref.startswith("@executable_path/"):
                continue
            real = resolve(ref, src)
            if real == src:
                continue  # the library's own id line
            name = os.path.basename(real)
            subprocess.run(["install_name_tool", "-change", ref, f"@executable_path/../Frameworks/{name}", dst],
                           check=True, capture_output=True)
            if real not in copied:
                queue.append((None, real))
        # Drop Homebrew rpaths so nothing can silently load from /opt/homebrew.
        for rp in rpaths(dst):
            if rp.startswith(BREW) or "Cellar" in rp:
                subprocess.run(["install_name_tool", "-delete_rpath", rp, dst], capture_output=True)

    icd_dir = os.path.join(app, "Contents/Resources/vulkan/icd.d")
    os.makedirs(icd_dir, exist_ok=True)
    with open(os.path.join(icd_dir, "MoltenVK_icd.json"), "w") as f:
        json.dump({"file_format_version": "1.0.0",
                   "ICD": {"library_path": "../../../Frameworks/libMoltenVK.dylib", "api_version": "1.2.0",
                           "is_portability_driver": True}}, f, indent=2)

    # install_name_tool invalidates signatures; arm64 refuses to run unsigned code.
    for name in copied.values():
        subprocess.run(["codesign", "--force", "--sign", "-", os.path.join(fw, name)], check=True, capture_output=True)
    subprocess.run(["codesign", "--force", "--sign", "-", mpv_dst], check=True, capture_output=True)

    total = sum(os.path.getsize(os.path.join(fw, n)) for n in copied.values()) + os.path.getsize(mpv_dst)
    print(f"bundled mpv + {len(copied)} libraries ({total / 1e6:.0f} MB)")

    # Fail loudly if anything still points at Homebrew.
    leaks = [f"{p}: {r}" for p in [mpv_dst] + [os.path.join(fw, n) for n in copied.values()]
             for r in deps(p) if r.startswith(BREW) or "Cellar" in r]
    if leaks:
        raise SystemExit("still linked to Homebrew:\n" + "\n".join(leaks))


if __name__ == "__main__":
    main(sys.argv[1])
