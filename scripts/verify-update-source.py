#!/usr/bin/env python3
"""Offline checks against the real updater URL policy and feed publisher."""
import ast
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Sapphire/App Settings/UpdateChecker.swift').read_text()
policy = source[source.index('enum SapphireUpdateSource {'):source.index('\nenum AppVersionOrdering')]
model = source[source.index('struct GitHubReleaseAsset:'):source.index('\nstruct GitHubRelease:')]

def method(text, marker):
    start = text.index(marker)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

# Exercise actual delegate/cancellation methods with the network-start boundary stubbed.
callbacks = '\n'.join(method(source, marker) for marker in [
    '    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)',
    '    private func retryDownloadFromFallback(', '    func cancelDownload()'])
harness = (ROOT / 'scripts/verify-update-download-state.swift').read_text().replace('// ACTUAL_CALLBACKS', callbacks)

with tempfile.TemporaryDirectory(prefix='sapphire-update-policy-') as directory:
    swift = Path(directory) / 'main.swift'
    swift.write_text('import Foundation\nlet currentAppVersion="3.0"\n' + policy + model + '\n'
                     + (ROOT / 'scripts/verify-update-source.swift').read_text() + '\n' + harness)
    subprocess.run(['swift', str(swift)], check=True)

spec = importlib.util.spec_from_file_location('feed', ROOT / 'scripts/update-cn-release-feed.py')
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)
releases = json.loads((ROOT / 'updates/releases.json').read_text())
manifest = json.loads((ROOT / 'website/content/download-mirrors.json').read_text())
result = feed.add_verified_mirrors(copy.deepcopy(releases), manifest)
mirrored = next(r for r in result if r['tag_name'] in manifest['releases'])
asset = mirrored['assets'][0]
assert asset['browser_download_url'].startswith('https://github.com/u7-u7/Sapphire-CN/')
assert asset['mirror_download_url'].startswith(feed.MIRROR_BASE)
checks = 2
for field, value in [('url', asset['mirror_download_url'] + '?x=1'), ('size', 1),
                     ('digest', 'sha256:' + '0' * 64), ('github_url', 'https://evil.example/')]:
    bad = copy.deepcopy(manifest)
    bad['releases'][mirrored['tag_name']]['assets'][asset['name']][field] = value
    try:
        feed.add_verified_mirrors(copy.deepcopy(releases), bad)
    except ValueError:
        checks += 1
    else:
        raise AssertionError(f'Accepted mismatched mirror {field}')
legacy = feed.add_verified_mirrors(copy.deepcopy(result), {})
assert all('mirror_download_url' not in a for r in legacy for a in r['assets'])
checks += 1
for name in ['mirror-cn-release.py', 'update-cn-release-feed.py', 'verify-update-source.py']:
    ast.parse((ROOT / 'scripts' / name).read_text())
print(f'PASS: {checks} compatible-feed checks; Python syntax valid; no network or credentials used')
