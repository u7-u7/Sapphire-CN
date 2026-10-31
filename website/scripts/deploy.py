#!/usr/bin/env python3
"""通过阿里 Workbench 发布独立静态站点，保留现有 Caddy 配置。"""
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTANCE = 'i-bp1163pp7k7o228siqnp'
DOMAIN = 'sapphire.u7u7.top'


def remote(command):
    subprocess.run(['workbench', 'exec', '-i', INSTANCE, '--command', command, '--timeout', '60'], check=True)


def main():
    release = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    archive = ROOT / f'sapphire-{release}.tar.gz'
    destination = f'/tmp/sapphire-{release}.tar.gz'
    remote(f'test ! -e {destination} && test ! -e /opt/sapphire-site && ! docker inspect sapphire-web >/dev/null 2>&1 && ! ss -ltn | grep -q ":8787 "')
    subprocess.run(['tar', '-czf', str(archive), '-C', str(ROOT), 'dist', 'Caddyfile', 'source-manifest.json'], check=True)
    subprocess.run(['workbench', 'upload', str(archive), destination, '-i', INSTANCE], check=True)
    remote(f'''set -eu
release=/opt/sapphire-site/releases/{release}
mkdir -p "$release" /opt/sapphire-site/backups
tar -xzf {destination} -C "$release"
ln -s "$release" /opt/sapphire-site/current
docker run --rm --network none -v "$release/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker run -d --name sapphire-web --restart unless-stopped --network host -v "$release/dist:/srv:ro" -v "$release/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
''')
    remote('curl -fsS --retry 5 --retry-delay 1 http://127.0.0.1:8787/ -o /dev/null && curl -fsS http://127.0.0.1:8787/faq -o /dev/null')
    # bind mount 指向原 inode，因此追加及回退均原地写入，不能用 mv 替换配置文件。
    remote(f'''set -eu
config=/opt/agent-path/release/deploy/Caddyfile
backup=/opt/sapphire-site/backups/Caddyfile-before-{release}
! grep -Fq '{DOMAIN}' "$config"
cp -p "$config" "$backup"
cat >> "$config" <<'CADDY'

{DOMAIN} {{
    encode zstd gzip
    redir /portal /download 302
    redir /checkout.html /download 302
    reverse_proxy 127.0.0.1:8787 {{
        header_up Host 127.0.0.1:8787
    }}
}}
CADDY
if ! docker exec agent-path-web caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
    cat "$backup" > "$config"
    exit 1
fi
if ! docker exec agent-path-web caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; then
    cat "$backup" > "$config"
    exit 1
fi
curl -fsS http://127.0.0.1:8787/ | grep -q 'Sapphire-CN'
curl -fsS https://learn.u7u7.top/ -o /dev/null
echo 'Sapphire published; existing Agent Path verified'
''')
    print(f'https://{DOMAIN}/')


if __name__ == '__main__':
    main()
