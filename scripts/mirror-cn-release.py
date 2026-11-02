#!/usr/bin/env python3
"""Mirror verified public GitHub assets to OSS; never rewrite the app update feed."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request

REPOSITORY = 'u7-u7/Sapphire-CN'
ROOT = Path(__file__).resolve().parents[1]


def credential_environment():
    env = os.environ.copy()
    # Use normal ossutil credentials first. Reuse the local Workbench AK profile
    # only when no OSS credentials/configuration have been configured.
    if not env.get('OSS_ACCESS_KEY_ID') and not (Path.home() / '.ossutilconfig').exists():
        path = Path.home() / '.workbench/config.json'
        if path.exists():
            config = json.loads(path.read_text())
            profile = config.get('profiles', {}).get(config.get('current'), {})
            if profile.get('mode') == 'AK':
                env['OSS_ACCESS_KEY_ID'] = profile['access_key_id']
                env['OSS_ACCESS_KEY_SECRET'] = profile['access_key_secret']
    return env


def checksum(path, algorithm='sha256'):
    digest = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


class OSS:
    def __init__(self, executable, bucket, region):
        self.executable, self.bucket, self.region = executable, bucket, region
        self.environment = credential_environment()

    def api(self, operation, *arguments, missing_ok=False):
        command = [self.executable, 'api', operation, '--bucket', self.bucket,
                   '--region', self.region, '--output-format', 'json',
                   '--retry-times', '1', *arguments]
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True)
        if result.returncode:
            error = result.stderr + result.stdout
            for key in ['OSS_ACCESS_KEY_ID', 'OSS_ACCESS_KEY_SECRET', 'OSS_SESSION_TOKEN']:
                if self.environment.get(key):
                    error = error.replace(self.environment[key], '[redacted]')
            if missing_ok and 'NoSuchKey' in error:
                return None
            raise RuntimeError(error[:3000])
        # ossutil appends an elapsed-time line after the JSON response.
        return json.JSONDecoder().raw_decode(result.stdout.lstrip())[0]


def verify_object(oss, key, path, digest):
    metadata = oss.api('head-object', '--key', key)
    headers = {k.lower(): v[0] if isinstance(v, list) else v
               for k, v in metadata['Header'].items()}
    if (int(headers['content-length']) != path.stat().st_size
            or headers.get('x-oss-meta-sha256') != digest
            or headers['etag'].strip('"').lower() != checksum(path, 'md5')):
        raise ValueError(f'Existing immutable mirror differs: {key}')


def publish_update_feed(oss, tag):
    if (oss.bucket, oss.region) != ('sapphire-cn', 'cn-hangzhou'):
        raise ValueError('The client trusts only the dedicated Sapphire-CN bucket')
    path = ROOT / 'updates/releases.json'
    payload = path.read_bytes()
    releases = json.loads(payload)
    mirrors = json.loads((ROOT / 'website/content/download-mirrors.json').read_text())
    if len(payload) > 5 * 1024 ** 2 or not releases or releases[0]['tag_name'] != tag:
        raise ValueError('Expected the current compatible update feed')
    for release in releases:
        for asset in release['assets']:
            github = f'https://github.com/{REPOSITORY}/releases/download/{release["tag_name"]}/{asset["name"]}'
            if asset['browser_download_url'] != github:
                raise ValueError('Keep GitHub URLs for older clients')
            if 'mirror_download_url' not in asset:
                if release is releases[0]:
                    raise ValueError('Mirror the newest release before publishing the OSS feed')
                continue
            mirror = mirrors['releases'][release['tag_name']]['assets'][asset['name']]
            expected = f'https://{oss.bucket}.oss-{oss.region}.aliyuncs.com/releases/{release["tag_name"]}/{asset["name"]}'
            if (asset['mirror_download_url'] != expected or mirror['url'] != expected
                    or mirror['size'] != asset['size'] or mirror['digest'] != asset['digest']
                    or mirror['github_url'] != github):
                raise ValueError('Feed mirror differs from verified release')
    key = 'updates/releases.json'
    url = f'https://{oss.bucket}.oss-{oss.region}.aliyuncs.com/{key}'
    # 清单是可变对象；先保留上一份公开清单的私有快照，安装包仍保持不可变。
    if oss.api('head-object', '--key', key, missing_ok=True):
        with urllib.request.urlopen(url, timeout=30) as response:
            previous = response.read(5 * 1024 ** 2 + 1)
        previous_releases = json.loads(previous)
        if (len(previous) > 5 * 1024 ** 2
                or previous_releases[0]['tag_name'] not in [r['tag_name'] for r in releases]):
            raise ValueError('Refusing to discard the previously published newest release')
        digest = hashlib.sha256(previous).hexdigest()
        backup_key = f'updates/history/{digest}.json'
        if oss.api('head-object', '--key', backup_key, missing_ok=True) is None:
            with tempfile.TemporaryDirectory(prefix='sapphire-feed-backup-') as directory:
                backup = Path(directory) / 'releases.json'
                backup.write_bytes(previous)
                oss.api('put-object', '--key', backup_key, '--body', 'file://' + str(backup),
                        '--object-acl', 'private', '--forbid-overwrite')
    oss.api('put-object', '--key', key, '--body', 'file://' + str(path),
            '--object-acl', 'public-read', '--content-type', 'application/json; charset=utf-8',
            '--cache-control', 'public, max-age=60, must-revalidate',
            '--metadata', 'sha256=' + hashlib.sha256(payload).hexdigest())
    with urllib.request.urlopen(url, timeout=30) as response:
        if response.geturl() != url or response.read(len(payload) + 1) != payload:
            raise ValueError('Public OSS feed differs from the local compatible feed')
    print(f'Published and verified OSS update feed: {url}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--bucket', default='sapphire-cn')
    parser.add_argument('--region', default='cn-hangzhou')
    parser.add_argument('--asset-directory', type=Path)
    parser.add_argument('--stage-only', action='store_true', help='Upload privately; do not publish links or change ACLs')
    parser.add_argument('--publish-feed-only', action='store_true', help='Publish the compatible feed after release mirrors are verified')
    parser.add_argument('--manifest', type=Path, default=ROOT / 'website/content/download-mirrors.json')
    args = parser.parse_args()
    if not re.fullmatch(r'v\d+(?:\.\d+){1,2}-cn\.\d+(?:-preview)?', args.tag):
        raise ValueError('Expected a normal CN release tag')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{1,61}[a-z0-9]', args.bucket):
        raise ValueError('Invalid bucket name')
    if not re.fullmatch(r'[a-z]+-[a-z0-9-]+', args.region):
        raise ValueError('Invalid region')
    gh = shutil.which('gh') or str(Path.home() / '.local/bin/gh')
    executable = shutil.which('ossutil') or str(Path.home() / '.local/bin/ossutil')
    release = json.loads(subprocess.check_output([gh, 'api', f'repos/{REPOSITORY}/releases/tags/{args.tag}']))
    if release.get('draft') or not release.get('published_at') or release.get('tag_name') != args.tag:
        raise ValueError('Only published releases can be mirrored')
    prefix = f'https://github.com/{REPOSITORY}/releases/download/{args.tag}/'
    required = {f'Sapphire-CN-{args.tag[1:]}-arm64.dmg',
                f'Sapphire-CN-{args.tag[1:]}-arm64-update.zip', 'SHA256SUMS.txt'}
    allowed = required | {'INSTALL-NOTES.txt'}
    assets = [a for a in release['assets'] if a['name'] in allowed]
    if not required.issubset({a['name'] for a in assets}):
        raise ValueError('Release needs DMG, app-only update ZIP and checksums')
    oss = OSS(executable, args.bucket, args.region)
    if args.publish_feed_only:
        if args.stage_only:
            raise ValueError('Feed publication cannot be combined with private staging')
        publish_update_feed(oss, args.tag)
        return
    if not args.stage_only:
        blocked = oss.api('get-bucket-public-access-block').get('BlockPublicAccess')
        if str(blocked).lower() == 'true':
            raise ValueError('Bucket blocks public access. Review the bucket setting before publishing public release objects.')
    mirrored = {}
    with tempfile.TemporaryDirectory(prefix='sapphire-mirror-') as temporary:
        for asset in assets:
            name = asset['name']
            if (asset.get('state') != 'uploaded' or asset['browser_download_url'] != prefix + name
                    or not 0 < asset.get('size', 0) <= 1024 ** 3
                    or not re.fullmatch(r'sha256:[0-9a-f]{64}', asset.get('digest') or '')):
                raise ValueError(f'Unverified GitHub asset: {name}')
            path = args.asset_directory / name if args.asset_directory else Path(temporary) / name
            if not path.exists():
                path = Path(temporary) / name
                subprocess.run([gh, 'release', 'download', args.tag, '--repo', REPOSITORY,
                                '--pattern', name, '--dir', temporary], check=True)
            digest = asset['digest'].split(':', 1)[1]
            if path.stat().st_size != asset['size'] or checksum(path) != digest:
                raise ValueError(f'Local asset differs from GitHub digest: {name}')
            key = f'releases/{args.tag}/{name}'
            existing = oss.api('head-object', '--key', key, missing_ok=True)
            if existing is None:
                mime = 'application/zip' if name.endswith('.zip') else (
                    'application/x-apple-diskimage' if name.endswith('.dmg') else 'text/plain; charset=utf-8')
                print(f'Uploading private release object: {key}', flush=True)
                oss.api('put-object', '--key', key, '--body', 'file://' + str(path.resolve()),
                        '--object-acl', 'private', '--forbid-overwrite', '--content-type', mime,
                        '--content-disposition', f'attachment; filename="{name}"',
                        '--cache-control', 'public, max-age=31536000, immutable', '--metadata', 'sha256=' + digest)
            verify_object(oss, key, path, digest)
            url = f'https://{args.bucket}.oss-{args.region}.aliyuncs.com/{key}'
            if not args.stage_only:
                oss.api('put-object-acl', '--key', key, '--object-acl', 'public-read')
                # Check the public bytes independently, not merely our metadata.
                with urllib.request.urlopen(url, timeout=60) as response:
                    if response.geturl() != url or int(response.headers['Content-Length']) != asset['size']:
                        raise ValueError(f'Unexpected public response: {name}')
                    actual = hashlib.sha256()
                    for block in iter(lambda: response.read(1024 * 1024), b''):
                        actual.update(block)
                if actual.hexdigest() != digest:
                    raise ValueError(f'Public download SHA-256 mismatch: {name}')
            mirrored[name] = {'url': url, 'size': asset['size'], 'digest': asset['digest'],
                              'github_url': asset['browser_download_url']}
            print(f'Verified {name}: {asset["size"]} bytes', flush=True)
    if args.stage_only:
        print('Private staging complete; no public permissions or website links changed.')
        return
    manifest = json.loads(args.manifest.read_text()) if args.manifest.exists() else {
        'schema_version': 1, 'bucket': args.bucket, 'region': args.region, 'releases': {}}
    if manifest['bucket'] != args.bucket or manifest['region'] != args.region:
        raise ValueError('Manifest belongs to another bucket')
    manifest['releases'][args.tag] = {'verified_at': datetime.now(timezone.utc).isoformat(), 'assets': mirrored}
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    staged = args.manifest.with_suffix('.json.tmp')
    staged.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    staged.replace(args.manifest)
    print(f'Published verified mirror manifest: {args.manifest}')


if __name__ == '__main__':
    main()
