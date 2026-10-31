#!/usr/bin/env python3
"""增量发布本站文件；先保留旧文件，不重启静态服务或其他站点。"""
import json
import os
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTANCE = 'i-bp1163pp7k7o228siqnp'


def remote(command, capture=False):
    args = ['workbench','exec','-i',INSTANCE,'--command',command,'--timeout','60']
    return subprocess.check_output(args,text=True) if capture else subprocess.run(args,check=True)


def main():
    previous = json.loads(remote('cat /opt/sapphire-site/current/source-manifest.json',True))
    manifest = json.loads((ROOT / 'source-manifest.json').read_text())
    changed = [p for p,v in manifest.items() if previous.get(p,{}).get('deployed_sha256') != v['deployed_sha256']]
    release = 'cn-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    archive = ROOT / f'{release}.tar.gz'
    with tarfile.open(archive,'w:gz') as tar:
        for path in changed:
            tar.add(ROOT/'dist'/path,arcname='dist/'+path)
        tar.add(ROOT/'source-manifest.json',arcname='source-manifest.json')
    target = f'/tmp/{release}.tar.gz'
    remote(f'test ! -e {target}')
    subprocess.run(['workbench','upload',str(archive),target,'-i',INSTANCE],check=True)
    payload = json.dumps(changed)
    remote(f'''set -eu
mkdir -p /opt/sapphire-site/releases/{release}
tar -xzf {target} -C /opt/sapphire-site/releases/{release}
python - <<'PY'
import os,json,tarfile,hashlib,shutil
active=os.path.realpath('/opt/sapphire-site/current')
stage='/opt/sapphire-site/releases/{release}'
changed=json.loads({payload!r})
manifest=json.load(open(stage+'/source-manifest.json'))
for p in changed:
 assert hashlib.sha256(open(stage+'/dist/'+p,'rb').read()).hexdigest()==manifest[p]['deployed_sha256'],p
with tarfile.open('/opt/sapphire-site/backups/before-{release}.tar.gz','w:gz') as backup:
 for p in changed:
  path=active+'/dist/'+p
  if os.path.isfile(path):backup.add(path,arcname='dist/'+p)
 backup.add(active+'/source-manifest.json',arcname='source-manifest.json')
for p in changed:
 destination=active+'/dist/'+p
 if not os.path.isdir(os.path.dirname(destination)):os.makedirs(os.path.dirname(destination))
 shutil.copyfile(stage+'/dist/'+p,destination+'.incoming')
 os.rename(destination+'.incoming',destination)
shutil.copyfile(stage+'/source-manifest.json',active+'/source-manifest.json')
for p,v in manifest.items():
 assert hashlib.sha256(open(active+'/dist/'+p,'rb').read()).hexdigest()==v['deployed_sha256'],p
print('Published %s changed assets; all %s hashes verified' % (len(changed),len(manifest)))
PY
''')
    print('https://sapphire.121.41.102.231.sslip.io/')


if __name__ == '__main__':
    main()
