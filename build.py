"""Builds VeinKeeper.zip from the VeinKeeper/ addon folder.

Uses forward slashes in the zip entries (PowerShell 5.1's Compress-Archive writes
backslashes, which break extraction on macOS and in some addon managers).

    python build.py            # build the zip
    python build.py --install  # also copy the addon into the WoW Forever AddOns folder
"""
import os, shutil, sys, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(ROOT, "VeinKeeper")
ZIP = os.path.join(ROOT, "VeinKeeper.zip")
ADDONS_DIR = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"

with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, files in os.walk(ADDON):
        for f in sorted(files):
            full = os.path.join(dirpath, f)
            z.write(full, os.path.relpath(full, ROOT).replace("\\", "/"))
print("built", ZIP)

if "--install" in sys.argv:
    dest = os.path.join(ADDONS_DIR, "VeinKeeper")
    shutil.copytree(ADDON, dest, dirs_exist_ok=True)
    print("installed to", dest)
