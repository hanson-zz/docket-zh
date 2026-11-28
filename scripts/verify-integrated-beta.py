#!/usr/bin/env python3
"""Verify the provenance and installed resources of the integrated test build."""
import argparse
import hashlib
import json
import os
import plistlib
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / 'docs/integration-beta25-sources.json'
ICONS = ('AmberClaws AstralMage CrimsonArmor EmeraldGiant NightSentinel RedMischief '
         'ShieldGuardian SkyGuardian SkylineAcrobat SpeedRunner StormWielder VioletShadow').split()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def verify_sources():
    spec = json.loads(SPEC.read_text())
    for sha in [spec['base_sha'], spec['tested_baseline_sha']] + [entry['sha'] for entry in spec['sources']]:
        subprocess.run(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor', sha, 'HEAD'], check=True)
    # Experimental work may add laptop frames; existing character artwork stays intact.
    original_art = git('diff', '--name-only', '--diff-filter=MD', spec['base_sha'], 'HEAD', '--',
                       'Resources/Pet', 'Resources/PandaStates', 'Resources/DeskCompanion', 'Resources/AppIcons')
    assert not original_art, f'Original artwork was modified: {original_art}'
    print('All seven source PR heads and the main baseline are included; original artwork is unchanged.')
    return spec


def png_info(path):
    raw = path.read_bytes()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n', path
    width, height, depth, color = struct.unpack('>IIBB', raw[16:26])
    assert depth == 8 and color == 6, f'Expected 8-bit RGBA PNG: {path}'
    return width, height


def verify_app(app, output, spec):
    contents = app / 'Contents'
    info = plistlib.loads((contents / 'Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == spec['version'], info
    assert str(info['CFBundleVersion']) == spec['build'], info
    assert info['CFBundleIdentifier'] == 'com.docket-zh.app', info
    binary = contents / 'MacOS' / info['CFBundleExecutable']
    header = binary.read_bytes()[:8]
    assert header[:4] == b'\xcf\xfa\xed\xfe' and struct.unpack('<I', header[4:8])[0] == 0x0100000C, 'Expected arm64 app'
    helper = contents / 'MacOS' / 'DocklingBrowserHost'
    assert helper.is_file() and helper.stat().st_mode & 0o111, 'Browser host is missing or not executable'
    subprocess.run(['codesign', '--verify', '--strict', str(helper)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    widgets = contents / 'PlugIns' / 'DocklingWidgets.appex' / 'Contents' / 'Info.plist'
    assert widgets.is_file(), 'Widget extension is missing'
    resources = contents / 'Resources'
    hashes = {}
    for icon in ICONS:
        for suffix, size in [('', 1024), ('-512', 512), ('-256', 256)]:
            name = f'AppIcon-{icon}{suffix}.png'
            path = resources / name
            assert png_info(path) == (size, size), name
            assert path.read_bytes() == (ROOT / 'Resources/AppIcons' / name).read_bytes(), name
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    for part in ['chassis', 'shell']:
        dimensions = []
        for theme in ['pearl', 'mechanical']:
            name = f'deck-{part}-{theme}.png'
            path = resources / name
            dimensions.append(png_info(path))
            assert path.read_bytes() == (ROOT / 'Resources/CassetteDeck' / name).read_bytes(), name
            hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        assert dimensions[0] == dimensions[1], part
    for name in ['pet-sprite-lively-center.png', 'pet-sprite-lively-laptop.png']:
        assert (resources / name).read_bytes() == (ROOT / 'Resources/Pet/sprites' / name).read_bytes(), name
    record = dict(spec, build_sha=git('rev-parse', 'HEAD'),
                  source_branch_sha=os.environ.get('HEAD_SHA', git('rev-parse', 'HEAD')),
                  ci_url=os.environ.get('CI_RUN_URL'),
                  resource_sha256=hashes,
                  automated_checks='Build, tests, localizations, source ancestry, resource bytes and signatures passed',
                  runtime_validation='Pending; not established by CI')
    output.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    print(f'Verified {spec["version"]}, browser host, widgets, 36 icons and four cassette layers.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    spec = verify_sources()
    if args.app:
        assert args.output, '--output is required with --app'
        verify_app(args.app, args.output, spec)
