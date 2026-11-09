"""Builds the VeinKeeper addon zip.

Zip entries use forward slashes (PowerShell 5.1's Compress-Archive writes
backslashes, which break extraction on macOS and in some addon managers).

    python build.py                   # VeinKeeper.zip
    python build.py --install         # also copy the addon into the WoW Forever AddOns folder
    python build.py --release 1.1.0   # dist/: VeinKeeper-1.1.0.zip, release.json, notes.md
                                      # (fails unless the .toc says ## Version: 1.1.0)
"""
import json, os, re, shutil, sys, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(ROOT, "VeinKeeper")
TOC = os.path.join(ADDON, "VeinKeeper.toc")
ADDONS_DIR = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"


def toc_field(name):
    with open(TOC, encoding="utf-8") as f:
        m = re.search(rf"^## {name}:\s*(.+?)\s*$", f.read(), re.M)
    return m.group(1) if m else None


def build_zip(path):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, dirs, files in os.walk(ADDON):
            dirs.sort()
            for f in sorted(files):
                full = os.path.join(dirpath, f)
                z.write(full, os.path.relpath(full, ROOT).replace("\\", "/"))
    print("built", path)


def changelog_section(version):
    """The CHANGELOG.md section for a version, without its heading."""
    with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as f:
        text = f.read()
    m = re.search(rf"^## {re.escape(version)}\b.*?$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        sys.exit(f"CHANGELOG.md has no '## {version}' section")
    return m.group(1).strip() + "\n"


def release(version):
    toc_version = toc_field("Version")
    if toc_version != version:
        sys.exit(f"tag says {version} but VeinKeeper.toc says {toc_version}")
    dist = os.path.join(ROOT, "dist")
    shutil.rmtree(dist, ignore_errors=True)
    os.makedirs(dist)
    # WowUp picks a GitHub release's zip for a WoW Forever installation by
    # release.json flavor "forever", or failing that by a name ending in
    # "-forever.zip" (checked against WowUp-CF's own code), so do both
    name = f"VeinKeeper-{version}-forever.zip"
    build_zip(os.path.join(dist, name))
    manifest = {"releases": [{
        "name": "VeinKeeper",
        "version": version,
        "filename": name,
        "nolib": False,
        "metadata": [{"flavor": "forever", "interface": int(toc_field("Interface"))}],
    }]}
    with open(os.path.join(dist, "release.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    with open(os.path.join(dist, "notes.md"), "w", encoding="utf-8") as f:
        f.write(changelog_section(version))
    print("release files in", dist)


if "--release" in sys.argv:
    i = sys.argv.index("--release")
    if i + 1 >= len(sys.argv):
        sys.exit("usage: build.py --release <version>")
    release(sys.argv[i + 1].lstrip("v"))
else:
    build_zip(os.path.join(ROOT, "VeinKeeper.zip"))

if "--install" in sys.argv:
    dest = os.path.join(ADDONS_DIR, "VeinKeeper")
    shutil.rmtree(dest, ignore_errors=True)  # no stale files from older versions
    shutil.copytree(ADDON, dest)
    print("installed to", dest)
