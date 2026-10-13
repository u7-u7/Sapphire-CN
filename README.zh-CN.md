# Sapphire-CN

这是 [Sapphire](https://github.com/cshariq/Sapphire) 的简体中文本地化版本。保留上游英文作为默认语言；macOS 为 Sapphire 选择简体中文时，应用会读取 `zh-Hans` 翻译。

## AI 额度组件

在「设置 → 小组件」启用「AI 额度」。组件同时展示 Codex 和 Claude 的查询结果，点击进入详情查看额度窗口、余额、重置时间、同步状态和刷新按钮。详情打开期间，鼠标移到下方操作区不会触发刘海收起。

- **Codex 官方订阅**：先在终端执行 `codex login`，通过 CLI 的 app-server 读取账号额度。API Key 模式需使用平台自己的额度查询接口。
- **Claude 官方订阅**：读取已有 Claude Code 登录凭据查询订阅额度。
- **DeepSeek**：识别 Claude CLI 的 DeepSeek 配置后，可查询 API 余额。余额接口未返回重置时间时，显示「重置时间未提供」。
- **其他第三方平台**：分别为 Codex / Claude 保存查询配置，需填写当前模型地址、额度查询地址、认证方式和 JSON 字段路径。提供 DeepSeek、Sub2API、NewAPI、自定义 JSON 模板；「测试」预览结果，「保存查询设置」启用配置。第三方 API Key 本身不能确定通用的额度查询地址。

NewAPI 通常需要独立的账户查询 Token 和用户 ID；Sub2API 的具体接口和认证取决于供应商部署。使用供应商提供的 HTTPS 查询地址，并核对返回字段及额度单位。服务端未提供重置时间或额度字段时，组件保留未知状态。

独立查询密钥保存在 macOS Keychain，按平台和查询目标绑定。测试不会自动保存配置或密钥；独立密钥需在配置保存后单独存入 Keychain。遇到限流时显示上次数据和重试提示。

## 终端构建

安装 Xcode 工具链后，无需打开 Xcode 窗口即可编译：

```sh
xcodebuild -project Sapphire.xcodeproj -scheme Sapphire -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/SapphireDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

这条命令生成未签名的调试应用，适合检查代码和中文资源。需要实际使用系统扩展、权限等功能时，仍须按项目要求完成签名。

## 本地运行

1. 按项目原有签名与权限配置构建、运行。首次启动按引导授予所需权限。
2. 在 macOS「系统设置 → 通用 → 语言与地区 → 应用程序」为 Sapphire 选择「简体中文」，重新启动应用。

当前翻译覆盖设置导航、首次启动、权限说明、主要设置页、主界面与常见功能页的 1,674 条文案；其他功能页面中尚未翻译的文字会回退为英文。

构建后建议在中英文环境中逐页检查文案、长文本布局和权限弹窗。

## 翻译维护

- `Sapphire/App/Localizable.xcstrings`：简体中文界面文案。英文原文是键，未翻译项回退英文。
- `Sapphire/App/zh-Hans.lproj/InfoPlist.strings`：macOS 权限弹窗说明。
- 设置分类及简介通过 `SettingsSection` 查表本地化，保留英文搜索词；首次启动和设置页中传入组件的动态文案需显式查表。

新增界面文案时，优先使用 SwiftUI 的字面量 `Text("English text")` 或 `String(localized:)`。普通 `String` 传给 `Text(value)` 时不会自动查翻译表，应在显示处使用 `NSLocalizedString`。品牌名、协议名、路径、快捷键与格式占位符应保持原义。

项目原始许可证为 [AGPL-3.0](LICENSE)，请继续遵守其要求。
