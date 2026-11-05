# 💎 Sapphire-CN 中文教程

🌐 **[项目网站](https://sapphire.u7u7.top/)** · [二开说明与致谢](https://sapphire.u7u7.top/about) · 网站源码与部署说明见 [`website/`](website/README.md)。

🔗 本项目基于 [Sapphire](https://github.com/cshariq/Sapphire) 二次开发，增加中文适配、AI 额度查询与 Helper 连接修复。

📦 **[下载 DMG](https://sapphire-cn.oss-cn-hangzhou.aliyuncs.com/releases/v3.0-cn.11-preview/Sapphire-CN-3.0-cn.11-preview-arm64.dmg)** · [ZIP 安装包](https://sapphire-cn.oss-cn-hangzhou.aliyuncs.com/releases/v3.0-cn.11-preview/Sapphire-CN-3.0-cn.11-preview-arm64-update.zip) · [发布说明](https://github.com/u7-u7/Sapphire-CN/releases/tag/v3.0-cn.11-preview)

下载优先使用阿里云 OSS 镜像，文件与 GitHub 原包 SHA-256 一致。[GitHub 备用 DMG](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.11-preview/Sapphire-CN-3.0-cn.11-preview-arm64.dmg) · [GitHub 备用 ZIP](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.11-preview/Sapphire-CN-3.0-cn.11-preview-arm64-update.zip)。CN9 起应用内检查和下载更新优先使用 OSS，失败时回退 GitHub。CN6–CN8 升级 CN11 这一次仍走 GitHub，CN9–CN10 优先使用 OSS，也可从镜像手动安装。

> **升级方式**：CN6–CN10 用户可通过“设置 → 关于 → Sapphire 更新”获取 CN11。CN4 及更早版本、CN5 临时签名版用户需要先退出并备份原应用，再手动安装一次 CN11，迁移到团队 `462JAMGP66`；如 Helper 连接失败，请重新配置辅助服务并检查后台运行权限。

Apple 芯片 · 项目最低 macOS 14.6 · DMG 直接安装，无需 Xcode 或 App Store。🔓 当前未公证，首次如被拦截，按[教程](README.md#首次打开被系统拦截)在「隐私与安全性」手动允许。

CN11 同应用连续通知立即合并刷新，单次展示 6 秒；有其他应用等待时连续占用最多 12 秒。来源应用在前台时不重复提醒。传统通知记录模式仍可用，需要完全磁盘访问权限，可能受 macOS 写入记录延迟影响。

实时接管为**默认关闭的实验功能**，需辅助功能权限及来源应用的原生“桌面”横幅。未知或歧义来源保留原生；实时模式遵循系统专注和屏幕共享静音策略，不从数据库补弹被系统静音的正文。传统模式若要避免双重提醒，可单独关闭来源应用的“桌面”；实时模式需将其开启。安装包不会自动修改这些系统设置。

**真实横幅接管与隐藏期间崩溃后的窗口坐标恢复尚未验收，不能视为稳定功能。** 详见 [CN11 发布说明](docs/releases/3.0-cn.11-preview.md)和[通知配置](README.md#通知上岛)。


- 🚀 [安装与首次打开](README.md#安装包安装)
- 🔐 [系统授权](README.md#首次启动与授权)
- 📊 [AI 额度配置](README.md#配置-ai-额度)
- 🔧 [常见问题](README.md#常见问题)
- 🔄 [更新与卸载](README.md#更新与卸载)
- 🛠️ [源码构建与开发](docs/development.md)

完整教程统一维护在 **[中文首页](README.md)**。
