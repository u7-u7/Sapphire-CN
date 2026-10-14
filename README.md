# 💎 Sapphire-CN

中文刘海屏工具，随手查看 **Codex / Claude 订阅额度与第三方平台余额**。基于 [Sapphire](https://github.com/cshariq/Sapphire)。

📦 **[下载 DMG](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/Sapphire-CN-3.0-cn.1-preview-arm64.dmg)** · [ZIP 备用包](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/Sapphire-CN-3.0-cn.1-preview-arm64.zip) · [发布说明与校验文件](https://github.com/u7-u7/Sapphire-CN/releases/tag/v3.0-cn.1-preview)

**`v3.0-cn.1-preview` · Apple 芯片 arm64 · 项目最低 macOS 14.6 · 无需 Xcode**

> ⚠️ 当前为 Apple Development 签名、未经 Apple 公证的开发预览。Gatekeeper 实测拒绝，首次打开可能被拦截；其他 Mac 与整机重启尚未验收。上游原版安装包不含本分支功能。

## 能做什么

| | 功能 |
| --- | --- |
| 📊 AI 额度 | Codex、Claude 订阅额度、同步状态与服务端重置时间 |
| 💰 平台余额 | DeepSeek、Sub2API、NewAPI、自定义 JSON 接口 |
| 🧩 刘海组件 | 播放信息、日历、组件排序 |
| 🖥️ 桌面工具 | 窗口管理、文件托盘、剪贴板、护眼、电池管理 |
| 🇨🇳 中文界面 | 主要界面与权限说明汉化，少量提示仍为英文 |

部分公开源码为占位实现；订阅、系统扩展等功能需额外配置。

## 安装包安装

1. **下载**：选择上方 DMG 或应用 ZIP；发布页的 `Source code` 是源码。当前无 Intel 安装包。
2. **安装**：退出并备份旧版。打开 DMG，把 `Sapphire.app` 拖到 `Applications`；ZIP 则解压后复制完整应用。
3. **启动**：从 `/Applications/Sapphire.app` 打开，完成[首次授权](#首次启动与授权)。被拦截时见[处理步骤](#首次打开被系统拦截)。
4. **切换中文**：「系统设置 → 通用 → 语言与地区 → 应用程序」添加 Sapphire，选择「简体中文」并重启应用。
5. **打开面板**：按住 **⌘ Command 点击刘海**，点击 ⚙️ 进入设置；默认未开启悬停展开。

应用内版本显示 `3.0 (1)`，发布标签为 `v3.0-cn.1-preview`。

### 首次打开被系统拦截

确认信任来源且[校验一致](#校验下载文件)后，遇到「无法验证开发者」等提示，可按 [Apple 官方说明](https://support.apple.com/zh-cn/102445)操作：

1. 尝试打开 Sapphire，让系统显示拦截提示。
2. 前往「系统设置 → 隐私与安全性」，找到 Sapphire，点击「仍要打开」。
3. 由本人完成系统认证，确认「打开」。

按钮可能受设备管理策略限制，此流程不保证其他 Mac 可以运行。提示应用损坏或将损坏电脑时，停止打开并按 Apple 说明排查。不要关闭全局安全保护或移除应用签名。

### 校验下载文件

将安装包与 [SHA256SUMS.txt](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/SHA256SUMS.txt) 放在同一目录，在该目录运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

已下载的文件应显示 `OK`；只下载一种格式时，另一项会提示文件不存在。

## 首次启动与授权

🔐 跟随引导授权，当前必需项为**辅助功能**；其他权限按功能开启。

| 权限 | 用途与位置 |
| --- | --- |
| 辅助功能 | 窗口管理等；「系统设置 → 隐私与安全 → 辅助功能」 |
| 后台运行 | Helper；「系统设置 → 通用 → 登录项与扩展」（旧系统为「登录项」） |
| 钥匙串 | 剪贴板密钥、查询凭据；本人在系统弹窗处理，单次「允许」后可能再次询问，「始终允许」可选 |
| 日历、通知、位置、蓝牙 | 对应功能使用时授权 |
| 屏幕录制、自动化、完全磁盘访问 | 按窗口预览、媒体控制等功能提示授权 |

需要 Helper 时：**设置 → 电池 → 配置 → 安装**，批准后台运行，等待首次握手（宽限期 30 秒），确认显示辅助服务已运行或 `Helper Active`。首次引导中的按钮叫「安装辅助服务」。

## 基础使用

- **展开面板**：⌘ 点击刘海；可在设置中启用悬停展开。
- **配置组件**：⚙️ → 小组件 → 小组件可见性和顺序，启用并调整排序。
- **其他工具**：在对应分类配置音乐、日历、文件托盘、剪贴板和电池等功能。

## 配置 AI 额度

📊 在「设置 → 小组件 → 小组件可见性和顺序」启用 **AI 额度**，选择 5 / 15 / 30 分钟刷新。回到面板，点击额度查看详情；手动刷新仍受请求间隔与限流约束。

### Codex 官方订阅

按 [官方教程](https://learn.chatgpt.com/docs/codex/cli)安装 Codex CLI，登录要查看额度的账户：

```sh
codex login
codex login status
```

回到 Sapphire，**关闭 Codex 第三方查询**并刷新。只使用 API 密钥的账户请配置平台查询接口。详见 [OpenAI 认证说明](https://learn.chatgpt.com/docs/auth)。

### Claude 官方订阅

按 [官方教程](https://code.claude.com/docs/zh-CN/setup)安装 Claude Code，再登录：

```sh
claude auth login
claude auth status
```

确认 Claude Code 使用官方服务配置，在 Sapphire **关闭 Claude 第三方查询**后刷新。关闭此开关不会修改 CLI 的供应商配置；登录过期需在 CLI 重新登录。

### DeepSeek 与第三方平台

Claude Code 当前使用 DeepSeek 时会自动识别，也可手动配置。Codex、Claude 各自的第三方设置独立。

1. 在「设置 → 小组件」找到「Codex · 第三方额度」或「Claude · 第三方额度」，开启查询。
2. 填写平台名称、当前供应商 API 地址，选择模板并点击「应用模板」（会重填部分设置）。
3. 核对 **HTTPS 额度查询地址、认证方式、凭据来源**。这里填余额接口；复用 CLI 凭据时，供应商地址须与 CLI 一致；使用独立凭据时，先填写查询密钥或账户令牌。
4. 在「JSON 字段与重置时间」核对字段路径、数值除数和币种；未返回的字段留空。
5. 点击「测试额度查询」，确认读数后点击 **「保存查询设置」**。
6. 使用独立凭据时，再点击 **「保存查询密钥」**，存入钥匙串；随后回到面板刷新。

> 🔑 测试不会保存。独立密钥必须在设置保存后另行保存；修改地址、认证或用户编号后，可能需要重新保存密钥。

| 平台 | 配置要点 |
| --- | --- |
| DeepSeek | 使用可查询余额的密钥；余额不换算成 Claude 订阅百分比 |
| Sub2API | 接口与认证以供应商部署为准，模板地址可能需调整 |
| NewAPI | **账户 Access Token + User ID**，不能用模型 API Key；User ID 虽标可选，此模板实际必填。默认除数 `500000` 须核对 |
| 自定义 JSON | 按真实响应填路径，如 `data.balance`、`balance_infos.0.total_balance` |

币种标签不代表汇率换算；服务端未返回重置时间时显示未提供。

## 常见问题

### Helper 提示 SAP-H1

表示后台已批准但连接失败，不代表进程没启动。依次检查：

1. 等待首次验签，确认后台运行已批准。
2. 确认主程序与 Helper 签名身份匹配，未改成未签名或 ad-hoc 临时签名。
3. 仍无法恢复，再到「设置 → 电池 → 配置」手动「重置辅助服务」。

新版保留等待中的连接，避免短超时触发反复重连。不要连续重置或清空系统后台数据库。SAP-H2 为等待批准，SAP-H3 为文件或注册缺失。

### 钥匙串反复询问或界面卡住

检查是否有系统钥匙串弹窗等待本人处理；单次授权可能在下次启动再次询问。权限已开仍报错时，确认授权对象是当前 `/Applications/Sapphire.app`。

### AI 额度查询失败

| 现象 | 处理 |
| --- | --- |
| 找不到 CLI / 未登录 | 确认 CLI 可运行、登录未过期，再重启 Sapphire |
| 第三方认证失败 | 核对令牌类型、User ID、认证方式与地址 |
| 读不到 CLI 凭据 | GUI 可能读不到终端临时环境变量；持久保存配置或改用独立查询密钥 |
| 测试成功但没更新 | 保存设置及独立密钥，等待刷新或限流冷却 |
| 数值、币种异常 | 核对 JSON 路径、除数与单位 |

## 更新与卸载

⚠️ **应用内更新指向上游原版**，会覆盖本分支功能。中文版请从[本仓库 Releases](https://github.com/u7-u7/Sapphire-CN/releases)更新；可在「关于」关闭自动下载。

- **安装包更新**：退出并备份旧版 → 核对新包 → 替换「应用程序」中的应用 → 确认权限、Helper 与额度。
- **源码更新**：工作区无未提交修改时运行 `git pull --ff-only`，使用相同身份重新构建签名后替换。签名变化可能触发重新授权。
- **卸载**：退出后将应用移到废纸篓，按需关闭对应后台项；不用清空钥匙串或系统后台记录。

## 源码安装

🛠️ 需要完整 Xcode、Git 和有效签名身份。主程序、Helper 与嵌入扩展需正确签名；未签名编译不能验证 Helper 可用。

完整命令与签名步骤见 **[开发指南](docs/development.md#源码安装)**。

## 开发与验证

🧪 [开发指南](docs/development.md#开发与验证)包含 Helper 的 14 项 XPC 边界检查与翻译维护说明。

实测记录：[签名修复](docs/plans/2026-10-13-helper-signature-repair.md) · [冷启动修复](docs/plans/2026-10-14-helper-cold-handshake.md) · [发行验证](docs/releases/v3.0-cn.1-preview.md)。

## 来源与许可证

基于 [cshariq/Sapphire](https://github.com/cshariq/Sapphire)，保留原作者与贡献者署名。本分支为 [u7-u7/Sapphire-CN](https://github.com/u7-u7/Sapphire-CN)，遵循 [AGPL-3.0](LICENSE)；第三方资源以各自声明为准。
