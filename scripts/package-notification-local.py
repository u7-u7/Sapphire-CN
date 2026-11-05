#!/usr/bin/env python3
"""Stage a locally signed notification test app, including its recovery companion."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--built-app', type=Path, required=True)
parser.add_argument('--reference-app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--identity', required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error('Output must not exist; choose a new staging directory.')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(args.reference_app)], check=True)
args.output.mkdir(parents=True)
app = args.output / 'Sapphire.app'
subprocess.run(['ditto', str(args.built_app), str(app)], check=True)
info_path = app / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['SapphireLocalBuildLabel'] = 'CN11 realtime local test'
info_path.write_bytes(plistlib.dumps(info))
main = app / 'Contents/MacOS/Sapphire'
helper = main.with_name('SapphireNotificationRecovery')
subprocess.run(['ditto', str(main), str(helper)], check=True)
magic = {bytes.fromhex(value) for value in ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
components = set()
for item in app.rglob('*'):
    if item.is_symlink():
        continue
    if item.is_dir() and item.suffix in ['.app', '.appex', '.framework', '.xpc', '.systemextension', '.driver', '.bundle']:
        components.add(item)
    elif item.is_file():
        with item.open('rb') as stream:
            if stream.read(4) in magic:
                components.add(item)
components.discard(main)
rights_dir = args.output / 'signing-entitlements'
rights_dir.mkdir()
audit = []
for index, item in enumerate(sorted(components, key=lambda value: len(value.parts), reverse=True) + [app]):
    relative = item.relative_to(app)
    original = args.reference_app / relative
    if item == helper:
        original = args.reference_app
    command = ['codesign', '--force', '--sign', args.identity, '--timestamp']
    if original.exists():
        rights = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(original)], capture_output=True, check=True)
        if rights.stdout.strip():
            entitlement = rights_dir / f'{index}.plist'
            entitlement.write_bytes(plistlib.dumps(plistlib.loads(rights.stdout)))
            command += ['--entitlements', str(entitlement), '--generate-entitlement-der']
        details = subprocess.run(['codesign', '-dv', '--verbose=2', str(original)], capture_output=True, text=True, check=True).stderr
        if '(runtime)' in details:
            command += ['--options', 'runtime']
    if item == helper:
        # Same signer and identifier preserve the existing app's Accessibility trust.
        command += ['--identifier', info['CFBundleIdentifier']]
    elif item.name == 'com.shariq.sapphireHelper':
        command += ['--identifier', 'com.shariq.sapphireHelper']
    subprocess.run(command + [str(item)], check=True)
    audit.append(str(relative))
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
(args.output / 'signed-components.json').write_text(json.dumps(audit, indent=2) + '\n')
print(app, flush=True)
