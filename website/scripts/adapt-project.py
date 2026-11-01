#!/usr/bin/env python3
"""复用上游页面视觉，内容和下载以当前仓库 README、更新清单为准。"""
import hashlib
import html
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent
DIST = ROOT / 'dist'
TEMPLATES = ROOT / 'templates'
REPO = 'https://github.com/u7-u7/Sapphire-CN'
SITE = 'https://sapphire.u7u7.top'
RELEASES = json.loads((PROJECT / 'updates/releases.json').read_text())
LATEST = RELEASES[0]
VERSION = LATEST['tag_name']
DOWNLOAD_BASE = f'{REPO}/releases/download/{VERSION}/'
DMG = DOWNLOAD_BASE + f'Sapphire-CN-{VERSION[1:]}-arm64.dmg'
ZIP = DOWNLOAD_BASE + f'Sapphire-CN-{VERSION[1:]}-arm64-update.zip'
def migration_card():
    return '<div class="cn-card"><h2 class="!mt-0">旧用户需要手动安装一次 CN6</h2><p><strong>CN6 更换为新开发团队签名（462JAMGP66）。CN4 及更早版本、CN5 临时签名版用户，均需先退出应用、备份原应用，再手动安装 CN6；旧版本无法通过同团队签名校验自动升级到 CN6。</strong></p><p>手动迁移后，后续同一新团队签名版本可继续使用应用内更新。签名校验保持启用。若后台辅助服务仍属于旧团队，请在设置 → 电池 → 配置中重新配置辅助服务，并检查系统设置中的后台运行和相关权限。</p><p>本版为 Apple Development 签名、未公证的开发预览。公开源码中的系统扩展等占位功能不会因重新签名而变为完整实现。</p></div>'


def footer():
    return f'''<footer class="main-footer border-t border-[var(--color-border-color)] bg-[var(--color-surface)] relative z-10">
      <div class="max-w-6xl mx-auto px-6 py-16 grid md:grid-cols-3 gap-12">
        <div><div class="flex items-center gap-3 text-xl font-extrabold"><img id="footer-logo" src="/sapphire-light.png" width="32" height="32" alt="Sapphire-CN">Sapphire-CN</div><p class="mt-4 text-sm text-[var(--color-text-secondary)]">刘海之间，尽在掌握。<br>中文适配 · AI 额度 · 桌面效率</p></div>
        <div class="space-y-3 text-sm"><h4 class="font-bold mb-4">项目</h4><a class="block" href="/about">二开说明</a><a class="block" href="/download">安装与下载</a><a class="block" href="/changelog">更新记录</a><a class="block" href="{REPO}">GitHub 源码</a></div>
        <div class="space-y-3 text-sm"><h4 class="font-bold mb-4">帮助</h4><a class="block" href="/faq">常见问题</a><a class="block" href="/issues">问题反馈</a><a class="block" href="{REPO}/blob/main/README.md">中文使用教程</a><a class="block" href="/privacy">数据与隐私</a></div>
      </div><div class="max-w-6xl mx-auto px-6 pb-10 text-xs text-[var(--color-text-secondary)]">基于 <a href="https://github.com/cshariq/Sapphire">Shariq Charolia 与贡献者的 Sapphire</a> 独立二次开发，由 u7-u7/Sapphire-CN 维护，非上游官方网站。<a href="/about">二开说明与致谢</a> · <a href="{REPO}/blob/main/LICENSE">项目许可证</a></div>
    </footer>'''


def shared(source):
    source = re.sub(r'<footer\b.*?</footer>', footer(), source, flags=re.S)
    source = re.sub(r'<script type="application/ld\+json">.*?</script>', '', source, flags=re.S)
    source = source.replace('https://github.com/cshariq/Sapphire/releases/latest/download/Sapphire.pkg', DMG)
    source = source.replace('https://github.com/cshariq/Sapphire', REPO)
    source = source.replace('https://api.github.com/repos/cshariq/Sapphire', 'https://api.github.com/repos/u7-u7/Sapphire-CN')
    # Attribution is the only upstream repository link intentionally retained.
    source = source.replace(f'href="{REPO}">Shariq', 'href="https://github.com/cshariq/Sapphire">Shariq')
    source = source.replace('https://sapphire-app.tech/portal', REPO + '/blob/main/README.md')
    source = source.replace('https://sapphire-app.tech', SITE)
    source = re.sub(r'\bSapphire\b(?!-CN)', 'Sapphire-CN', source)
    source = source.replace('https://github.com/cshariq/Sapphire-CN', 'https://github.com/cshariq/Sapphire')
    source = source.replace('Shariq Charolia 的 Sapphire-CN', 'Shariq Charolia 的 Sapphire')
    source = source.replace('Shariq Charolia 与贡献者的 Sapphire-CN', 'Shariq Charolia 与贡献者的 Sapphire')
    source = source.replace(REPO + '/releases/latest', REPO + '/releases/tag/' + VERSION)
    source = source.replace('fetch(`${REPO_URL}/releases/latest`)', f'fetch(`${{REPO_URL}}/releases/tags/{VERSION}`)')
    source = source.replace('lang="en"', 'lang="zh-CN"')
    for old, new in [('Changelog', '更新记录'), ('Issues', '问题反馈'), ('FAQ', '常见问题'), ('Account', '使用教程'), ('Subscribe', '安装指南'), ('Download for macOS', '下载 macOS 版'), ('Download', '下载'), ('View on GitHub', '在 GitHub 查看'), ('/subscribe', '/download')]:
        source = source.replace(old, new)
    source = re.sub(r'<a\b[^>]*href="https://discord.gg/[^>]*>.*?</a>', '', source, flags=re.S)
    source = source.replace('</head>', '<style>.cn-copy{line-height:1.9}.cn-shot{display:block;width:100%;height:auto}.cn-note{font-size:12px;line-height:1.8;color:var(--color-text-secondary)}.cn-content h2{font-size:24px;font-weight:800;margin:32px 0 16px}.cn-content p,.cn-content li{line-height:1.9;color:var(--color-text-secondary)}.cn-content a{color:#a78bfa}.cn-content ol{list-style:decimal;padding-left:24px}.cn-content li{margin:12px 0}.cn-card{padding:28px;border:1px solid var(--color-card-border);border-radius:24px;background:var(--color-card-bg)}</style></head>')
    return source


def content_page(template, title, subtitle, content):
    source = shared((TEMPLATES / template).read_text())
    source = re.sub(r'<title>.*?</title>', f'<title>{title} - Sapphire-CN</title>', source)
    source = re.sub(r'(<meta (?:name|property)="(?:description|og:description|twitter:description)" content=")[^"]*', lambda m:m[1]+html.escape(subtitle), source)
    source = re.sub(r'(<meta (?:name|property)="(?:og:title|twitter:title)" content=")[^"]*', lambda m:m[1]+html.escape(title+' - Sapphire-CN'), source)
    body = f'<main class="page-content space-y-12 cn-content"><div class="text-center"><h1 class="text-4xl md:text-6xl font-extrabold tracking-tight mb-6">{title}</h1><p>{subtitle}</p></div>{content}</main>'
    return re.sub(r'<main\b.*?</main>', body, source, count=1, flags=re.S)


def feature(identifier, badge, title, text, media, reverse=False):
    media_html = f'<img class="cn-shot" src="/assets/{media}" alt="{html.escape(title)}" loading="lazy">' if media.endswith('.png') else f'<video class="clean-video-element" src="/assets/{media}" autoplay loop muted playsinline controls preload="metadata"></video><p class="cn-note mt-3 text-center">上游同类功能演示；中文分支以实际界面为准。</p>'
    return f'''<section id="feature-{identifier}" class="relative py-28 md:py-40 px-6 max-w-7xl mx-auto"><div class="grid md:grid-cols-2 gap-16 items-center">
      <div class="space-y-6 {'md:order-2' if reverse else ''}"><div class="text-xs uppercase tracking-widest font-bold text-purple-400">{badge}</div><h2 class="apple-headline text-4xl md:text-6xl tracking-tight">{title}</h2><p class="apple-subheadline cn-copy text-lg">{text}</p></div>
      <div class="clean-video-frame rounded-3xl p-3 bg-[var(--color-secondary)] border border-[var(--color-card-border)]">{media_html}</div></div></section>'''


def homepage():
    source = shared((TEMPLATES / 'index.html').read_text())
    source = source.replace('The Notch,<br />Reimagined.', '刘海之间，<br />尽在掌握。')
    source = source.replace('Sapphire-CN neatly displays current activities around the notch on newer MacBooks and includes a suite of convenient features to enhance your productivity and well-being.', '音乐、AI 额度与桌面工具，汇聚在 Mac 的刘海之间。Sapphire-CN 为熟悉的体验，加入中文适配、Codex / Claude 额度与第三方平台余额查询。')
    source = source.replace('apple-scrub-text apple-subheadline', 'apple-subheadline cn-copy')
    source = re.sub(r'<video src="/assets/sapphire-demo.mp4"[^>]*></video>', '<img src="/assets/notch-overview.png" class="cn-shot" alt="Sapphire-CN 音乐、AI 额度和专注面板，读数为示例">', source)
    source = source.replace('bg-black aspect-video border', 'bg-black border')
    source = source.replace('<!-- GitHub Stats -->', f'<p class="cn-note pt-2">{VERSION} · Apple 芯片 arm64 · macOS 14.6 起<br>未公证开发预览 · <a href="/download" class="underline">安装说明</a> · 截图读数为示例</p><!-- GitHub Stats -->')
    source = source.replace('<!-- GitHub Stats -->', '<p class="cn-note">基于 Sapphire 的独立中文增强分支，非上游官方版本 · <a href="/about" class="underline">了解二开内容</a></p><!-- GitHub Stats -->')
    source = source.replace('<!-- GitHub Stats -->', '<p class="cn-note">CN6 已切换新团队签名，旧版本用户需要手动安装一次· <a href="/download" class="underline">查看 CN6 下载与迁移说明</a></p><!-- GitHub Stats -->')
    start = source.index('        <!-- 1. BLIP AGENT')
    end = source.index('    </main>', start)
    sections = [
        feature('ai-quota', '为 AI 工作流而生', '额度与余额，<br>抬眼即见。', '在一个组件里查看 Codex、Claude 订阅额度、同步状态与服务端重置时间。支持 DeepSeek、Sub2API、NewAPI 和自定义 JSON 余额查询；按你的账户和供应商配置。', 'notch-overview.png'),
        feature('clipboard', '桌面效率工具', '复制过的，<br>随时找回。', '剪贴板历史、文件托盘与常用桌面工具融入刘海面板。减少来回切换，让手头的工作保持连贯。', 'clipboard-history.png', True),
        feature('music', '刘海组件', '音乐与日历，<br>各就其位。', '播放信息、日历与专注组件集中展示。按住 ⌘ 点击刘海即可展开，在设置中启用所需组件、调整可见性和顺序。', 'Music.mp4'),
        feature('snap-zones', '桌面窗口管理', '窗口有序，<br>思路更清晰。', '使用窗口管理与布局工具安排桌面，配合文件托盘和剪贴板，整理日常多窗口工作。', 'Snap-Zones.mp4', True),
        feature('battery', 'Helper 连接修复', '后台连接，<br>更从容一些。', '中文分支修复 Helper 启动连接，保留首次握手等待，减少短超时反复重连。电池管理需要按应用提示安装辅助服务并批准后台运行。', 'Battery.mov'),
        f'''<section id="feature-cn" class="py-28 px-6 max-w-5xl mx-auto text-center"><p class="text-purple-400 text-xs font-bold tracking-widest mb-6">为中文用户继续打磨</p><h2 class="apple-headline text-4xl md:text-6xl mb-8">熟悉的 Mac，<br>更顺手的中文体验。</h2><p class="apple-subheadline cn-copy text-lg max-w-3xl mx-auto">主要界面与权限说明汉化，保留少量英文提示。CN6 补齐 160 条中文翻译并切换新团队签名；旧用户需手动安装一次，后续同团队版本支持应用内更新。部分公开源码为占位实现，订阅和系统扩展等功能需要额外配置。</p><a href="/faq" class="apple-secondary-btn mt-8">了解使用与功能范围</a></section>''',
        f'''<section id="final-cta-section" class="py-32 px-6 text-center"><h2 class="apple-headline text-4xl md:text-6xl mb-6">让刘海，多一点可能。</h2><p class="apple-subheadline mb-10">下载当前项目的 Sapphire-CN 开发预览版。</p><div class="flex flex-wrap justify-center gap-4"><a class="apple-cta-btn" href="{DMG}"><span class="material-symbols-outlined">download</span>下载 macOS 版</a><a class="apple-secondary-btn" href="{REPO}">在 GitHub 查看</a></div></section>'''
    ]
    source = source[:start] + '\n'.join(sections) + '\n' + source[end:]
    items = [('hero-section','home','概览'),('feature-ai-quota','monitoring','AI 额度'),('feature-clipboard','content_paste','剪贴板'),('feature-music','music_note','音乐'),('feature-snap-zones','grid_view','窗口'),('feature-battery','battery_charging_full','电池'),('feature-cn','translate','中文')]
    dock = '<nav class="apple-dock" id="section-dock" aria-label="功能导航">' + ''.join(f'<a class="dock-pill" href="#{i}" data-section="{i}"><span class="material-symbols-outlined">{icon}</span><span class="dock-label">{label}</span></a>' for i,icon,label in items) + '</nav>'
    source = re.sub(r'<nav class="apple-dock".*?</nav>', dock, source, flags=re.S)
    source = re.sub(r'<title>.*?</title>', '<title>Sapphire-CN · 刘海之间，尽在掌握</title>', source)
    source = source.replace('Sapphire-CN transforms the camera notch on modern MacBooks into an interactive component — Blip Agent, Face ID on Mac, live sports & market telemetry, and more.', 'Sapphire-CN 中文增强版：Codex / Claude 额度、第三方平台余额、音乐与日历刘海组件、剪贴板和桌面效率工具。')
    (DIST / 'index.html').write_text(source)


def script():
    source = (TEMPLATES / 'script.js').read_text().replace('cshariq/Sapphire', 'u7-u7/Sapphire-CN')
    begin = source.index('        const appMatrixContainer')
    end = source.index('        const featureSections', begin)
    source = source[:begin] + '''        gsap.fromTo('.hero-title', {opacity:0,y:30}, {opacity:1,y:0,duration:1});
        gsap.fromTo('.hero-cta', {opacity:0,y:20}, {opacity:1,y:0,duration:1,delay:0.2});
        gsap.fromTo('.hero-video-frame', {opacity:0,scale:0.94}, {opacity:1,scale:1,duration:1,delay:0.4});
        ScrollTrigger.create({trigger:'#feature-ai-quota', start:'top 85%', endTrigger:'#final-cta-section', end:'top 95%', onToggle:self=>{if(sectionDock)sectionDock.classList.toggle('is-dock-visible', self.isActive);}});
''' + source[end:]
    source = source.replace("const response = await fetch('https://api.github.com/repos/u7-u7/Sapphire-CN/releases');", "const response = await fetch('/project-releases.json');")
    source = source.replace('Beta builds are available exclusively to Basic, Pro & Ultra subscribers', 'CN 开发预览版公开下载；安装前请阅读安装说明')
    source = source.replace('Upgrade Plan', '安装说明').replace('href="/subscribe"', 'href="/download"')
    source = source.replace('renderRelease(stableRelease, false)', 'renderRelease(stableRelease, Boolean(stableRelease.prerelease))')
    source = source.replace("fetch(`${REPO_URL}/releases/latest`)", f"fetch(`${{REPO_URL}}/releases/tags/{VERSION}`)")
    source = source.replace(REPO + '/releases/latest', REPO + '/releases/tag/' + VERSION)
    (DIST / 'script.js').write_text(source)


def main():
    shutil.copyfile(TEMPLATES / 'style.css', DIST / 'style.css')
    for name in ['notch-overview.png', 'clipboard-history.png']:
        shutil.copyfile(PROJECT / 'docs/images' / name, DIST / 'assets' / name)
    homepage()
    script()
    about = f'''<div class="cn-card"><h2 class="!mt-0">项目来源</h2><p>Sapphire-CN 是基于 <a href="https://github.com/cshariq/Sapphire">Shariq Charolia 与贡献者开发的 Sapphire</a> 的独立二次开发分支，由 <a href="{REPO}">u7-u7/Sapphire-CN</a> 维护。本网站展示和提供下载的是中文增强分支，并非上游官方网站或官方中文版。</p></div>
    <div class="cn-card"><h2 class="!mt-0">本分支做了哪些改进？</h2><ul class="list-disc pl-6"><li>主要界面与权限说明中文适配。</li><li>Codex / Claude 官方订阅额度、同步状态与服务端重置时间展示。</li><li>DeepSeek、Sub2API、NewAPI 与自定义 JSON 平台余额查询。</li><li>Helper 启动连接与验证码通知修复。</li><li>本仓库 GitHub 应用内更新通道，包含公开 CN 预发布。</li></ul></div>
    <div class="cn-card"><h2 class="!mt-0">下载与功能范围</h2><p>本站下载指向 Sapphire-CN 的 GitHub Release。上游原版安装包不包含本分支新增功能。部分公开源码为占位实现，订阅、系统扩展等功能需要额外配置；支持情况以 <a href="{REPO}/blob/main/README.md">本项目使用说明</a>和实际版本为准。</p></div>
    <div class="cn-card"><h2 class="!mt-0">致谢与源码</h2><p>感谢 Shariq Charolia 与 Sapphire 上游贡献者。网站视觉沿用上游设计，同类功能演示素材保留来源说明；中文分支截图来自本项目。原作者与贡献者署名予以保留，项目许可见 <a href="{REPO}/blob/main/LICENSE">仓库 LICENSE</a>，第三方资源遵循各自声明。</p><div class="flex flex-wrap gap-4 mt-6"><a class="apple-secondary-btn" href="https://github.com/cshariq/Sapphire">上游项目</a><a class="apple-secondary-btn" href="{REPO}">Sapphire-CN 源码</a></div></div>'''
    about_page = content_page('faq.html','二次开发说明','独立维护的中文增强分支，保留上游署名与来源。',about)
    about_page = about_page.replace(f'{SITE}/faq', f'{SITE}/about').replace('href="/faq" class="header-nav-link is-active"', 'href="/faq" class="header-nav-link"')
    (DIST / 'about.html').write_text(about_page)
    faq = json.loads((ROOT / 'content/project-faq.json').read_text())
    faq_html = '<div class="space-y-4">' + ''.join(f'<details class="cn-card" {"open" if i==0 else ""}><summary class="font-bold cursor-pointer">{html.escape(q["question"])}</summary><p class="mt-4">{html.escape(q["answer"])}</p></details>' for i,q in enumerate(faq)) + '</div>'
    (DIST / 'faq.html').write_text(content_page('faq.html','常见问题','从当前项目文档整理，帮助你安装和配置 Sapphire-CN。',faq_html))
    install = f'''<div class="cn-card"><h2 class="!mt-0">{VERSION}</h2><p>Apple 芯片 arm64 · macOS 14.6 起 · 无需 Xcode。当前为 Apple Development 签名、未公证开发预览，无 Intel 安装包。</p><div class="flex flex-wrap gap-4 mt-6"><a class="apple-cta-btn !text-white" href="{DMG}">下载 DMG</a><a class="apple-secondary-btn" href="{ZIP}">ZIP 备用包</a><a class="apple-secondary-btn" href="{DOWNLOAD_BASE}SHA256SUMS.txt">校验文件</a></div></div>
    <div class="cn-card"><h2 class="!mt-0">安装与首次打开</h2><ol><li>下载 DMG，把 Sapphire.app 拖入 Applications；如已安装旧版，先退出并备份。</li><li>打开应用。如被系统拦截，请核对来源和 SHA256，按 <a href="https://support.apple.com/zh-cn/102445">Apple 官方说明</a>在隐私与安全性中由本人允许打开。</li><li>在系统设置 → 通用 → 语言与地区 → 应用程序中，为 Sapphire 选择简体中文。</li><li>按住 ⌘ 点击刘海，在设置中启用所需组件和 AI 额度。按功能提示开启辅助功能和后台运行等权限。</li></ol></div>
    <div class="cn-card"><h2 class="!mt-0">迁移后的应用内更新</h2><p>手动安装 CN6 后，可通过设置 → 关于 → Sapphire 更新检测后续同一新团队签名版本；下载后仍需本人确认安装。<a href="{REPO}/blob/main/README.md">查看完整中文教程</a>。</p></div>'''
    download = content_page('subscribe.html','安装与下载','下载本项目的中文增强版本。',migration_card() + install)
    (DIST / 'download.html').write_text(download)
    (DIST / 'subscribe.html').write_text(download)
    privacy = f'''<div class="cn-card"><h2 class="!mt-0">静态项目网站</h2><p>本站提供项目介绍、安装说明和公开更新记录，不提供账户注册或收款表单。源码、安装包与问题反馈均连接本项目 GitHub。</p><h2>额度查询与本地凭据</h2><p>应用按你配置的官方订阅或第三方平台接口查询数据。独立查询密钥通过应用的“保存查询密钥”存入 macOS 钥匙串；测试查询不会自动保存。不要在网站反馈中提交访问令牌、密钥或验证码。</p><h2>权限与功能</h2><p>辅助功能、后台运行、日历、通知、位置、蓝牙等权限按实际使用的功能授权。详细行为以 <a href="{REPO}">当前项目源码和使用教程</a>为准。</p><h2>外部服务</h2><p>下载和问题反馈访问 GitHub；应用中的第三方额度查询访问你配置的供应商服务。相应服务自行处理收到的请求。</p></div>'''
    (DIST / 'privacy.html').write_text(content_page('privacy.html','数据与隐私','了解本站与应用的使用边界。',privacy))
    for name in ['issues.html','changelog.html']:
        page = shared((TEMPLATES / name).read_text())
        if name == 'changelog.html':
            page = re.sub(r'(<main\b[^>]*>)', lambda m: m[1] + migration_card(), page, count=1)
        for old,new in [('Release 更新记录','更新记录'),('Latest Stable Release','当前版本'),('Beta Preview Channel','开发预览'),('Previous Releases','历史版本'),('Discover new features, performance refinements, and software updates for Sapphire-CN on macOS.','本项目的发行说明、功能改进与中文增强版本。')]:
            page=page.replace(old,new)
        page=page.replace('Basic, Pro & Ultra Exclusive','公开开发预览')
        (DIST / name).write_text(page)
    (DIST / 'project-releases.json').write_text(json.dumps(RELEASES,ensure_ascii=False,indent=2)+'\n')
    # 内容变化时更新脚本 URL，让已访问原复刻站的浏览器立即使用当前项目逻辑。
    digest = hashlib.sha256((DIST / 'script.js').read_bytes()).hexdigest()[:12]
    for page in DIST.glob('*.html'):
        page.write_text(page.read_text().replace('src="script.js"', f'src="script.js?v={digest}"'))
    manifest=json.loads((ROOT / 'source-manifest.json').read_text())
    for path in DIST.rglob('*'):
        if not path.is_file():continue
        relative=str(path.relative_to(DIST))
        entry=manifest.setdefault(relative,{'source':'current Sapphire-CN project'})
        entry['deployed_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        entry['deployed_bytes']=path.stat().st_size
    (ROOT / 'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Adapted website to u7-u7/Sapphire-CN {VERSION}')


if __name__ == '__main__':
    main()
