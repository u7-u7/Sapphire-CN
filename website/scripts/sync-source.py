#!/usr/bin/env python3
"""取得公开页面并将渲染资源固化到本地，保留真实账户服务的官方入口。"""
import concurrent.futures
import hashlib
import json
import re
import subprocess
import sys
import urllib.request
import urllib.error
from pathlib import Path
from urllib.parse import urljoin, urlparse

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'
ORIGIN = 'https://sapphire-app.tech/'
RAW = 'https://raw.githubusercontent.com/cshariq/Sapphire/main/Assets/'
PAGES = ['', 'subscribe', 'faq', 'changelog', 'issues', 'privacy']
VENDORS = {
    'https://cdn.tailwindcss.com': 'vendor/tailwind.js',
    'https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js': 'vendor/gsap.min.js',
    'https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/ScrollTrigger.min.js': 'vendor/ScrollTrigger.min.js',
    'https://unpkg.com/@studio-freight/lenis@1.0.42/dist/lenis.min.js': 'vendor/lenis.min.js',
    'https://cdn.jsdelivr.net/npm/marked/marked.min.js': 'vendor/marked.min.js',
}
MANIFEST = {}


def download(url, relative):
    path = DIST / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    resolved_source = url
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        # 原站指向的 GitHub main 已有缺失素材；客户端检出的同名原始素材可保留演示。
        fallback = ROOT.parent / 'Assets' / url.removeprefix(RAW)
        if error.code == 404 and url.startswith(RAW + 'app-icons/') and not fallback.is_file():
            # 原站这些图标本身返回404，用轻量字母图标兜底，不让生产页面出现破图。
            label = Path(relative).stem[:1].upper()
            data = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><rect width="48" height="48" rx="12" fill="#334155"/><text x="24" y="32" text-anchor="middle" fill="white" font-family="sans-serif" font-size="26">{label}</text></svg>'.encode()
            resolved_source = 'generated fallback; upstream returns 404'
            print(f'Original icon missing: {relative}', flush=True)
        elif error.code != 404 or not url.startswith(RAW) or not fallback.is_file():
            raise RuntimeError(f'Cannot retrieve {url}: {error}') from error
        else:
            data = fallback.read_bytes()
            resolved_source = str(fallback)
            print(f'Using existing original asset: {fallback.name}', flush=True)
    path.write_bytes(data)
    MANIFEST[relative] = {'source': resolved_source, 'upstream': url, 'source_sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    return data


def localize_fonts(url, relative):
    css = download(url, relative).decode()
    for remote in set(re.findall(r'url\((https://[^)]+)\)', css)):
        name = 'vendor/fonts/' + hashlib.sha256(remote.encode()).hexdigest()[:16] + Path(urlparse(remote).path).suffix
        download(remote, name)
        css = css.replace(remote, '/' + name)
    (DIST / relative).write_text(css)


def main():
    DIST.mkdir(parents=True, exist_ok=True)
    sources = {}
    for page in PAGES:
        relative = (page + '.html') if page else 'index.html'
        sources[relative] = download(urljoin(ORIGIN, page), relative).decode()
    for name in ['style.css', 'script.js', 'favicon.svg', 'sapphire-light.png', 'sapphire-dark.png']:
        download(urljoin(ORIGIN, name), name)
    script = (DIST / 'script.js').read_text()
    assets = set(re.findall(re.escape(RAW) + r'[^\s\"\'<>]+', '\n'.join(sources.values()) + script))
    jobs = [(remote, 'assets/' + remote[len(RAW):]) for remote in assets] + list(VENDORS.items())
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda job: download(*job), jobs))
    fonts_url = 'https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;700;800&display=swap'
    symbols_url = 'https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0'
    localize_fonts(fonts_url, 'vendor/fonts.css')
    localize_fonts(symbols_url, 'vendor/symbols.css')
    for relative, html in sources.items():
        html = re.sub(r'\s*<link rel="preconnect"[^>]+>', '', html)
        html = re.sub(r'\s*<meta name="google-adsense-account"[^>]+>', '', html)
        html = re.sub(r'\s*<script async src="https://www.googletagmanager.com[^>]*></script>\s*<script>.*?</script>', '', html, flags=re.S)
        html = html.replace(symbols_url, '/vendor/symbols.css')
        html = html.replace(RAW, '/assets/')
        html = html.replace('href="/portal"', 'href="https://sapphire-app.tech/portal"')
        html = html.replace('href="./checkout.html?', 'href="https://sapphire-app.tech/checkout.html?')
        for remote, local in VENDORS.items():
            html = html.replace(remote, '/' + local)
        (DIST / relative).write_text(html)
    (DIST / 'script.js').write_text(script.replace(RAW, '/assets/'))
    css = (DIST / 'style.css').read_text().replace(fonts_url, '/vendor/fonts.css')
    (DIST / 'style.css').write_text(css)
    for relative, entry in MANIFEST.items():
        entry['deployed_sha256'] = hashlib.sha256((DIST / relative).read_bytes()).hexdigest()
    (ROOT / 'source-manifest.json').write_text(json.dumps(MANIFEST, indent=2) + '\n')
    templates = ROOT / 'templates'
    templates.mkdir(exist_ok=True)
    for path in [*DIST.glob('*.html'), DIST / 'script.js', DIST / 'style.css']:
        if path.name in sources or path.name in ('script.js', 'style.css'):
            (templates / path.name).write_bytes(path.read_bytes())
    print(f'Synced {len(MANIFEST)} assets, {sum(p.stat().st_size for p in DIST.rglob("*") if p.is_file()):,} bytes')
    subprocess.run([sys.executable, str(ROOT / 'scripts/adapt-project.py')], check=True)


if __name__ == '__main__':
    main()
