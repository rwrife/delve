#!/usr/bin/env python3
"""Verify the built artifact, including actual asset-catalog compiler output."""
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as source:
    info = plistlib.load(source)
assert info['CFBundleIdentifier'] == 'com.infinityball.delve', info.get('CFBundleIdentifier')
assert info['UIDeviceFamily'] == [1], info.get('UIDeviceFamily')
# Xcode 26 single-size (1024 universal) app icons do not always write
# CFBundleIconName into the archived Info.plist. Check primary icon metadata
# if present, and require compiled Assets.car + emitted AppIcon raster files.
if 'CFBundleIcons' in info:
    assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon'
assert (app / 'Assets.car').stat().st_size > 0
app_icon_rasters = list(app.glob('AppIcon*.png'))
assert app_icon_rasters, 'No emitted AppIcon PNG rasters'
print('PASS: com.infinityball.delve; iPhone only; compiled Assets.car and AppIcon raster present')
