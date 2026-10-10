# Sapphire 简体中文本地化

这是 [Sapphire](https://github.com/cshariq/Sapphire) 的简体中文本地化版本。保留上游英文作为默认语言；macOS 为 Sapphire 选择简体中文时，应用会读取 `zh-Hans` 翻译。

## 本地运行

1. 用 Xcode 打开 `Sapphire.xcodeproj`，选择 `Sapphire` scheme。
2. 按项目原有签名与权限配置构建、运行。首次启动按引导授予所需权限。
3. 在 macOS「系统设置 → 通用 → 语言与地区 → 应用程序」为 Sapphire 选择「简体中文」，重新启动应用。

当前翻译覆盖设置导航、首次启动、权限说明、主要设置页、主界面与常见功能页的 1,674 条文案；其他功能页面中尚未翻译的文字会回退为英文。

构建后建议在中英文环境中逐页检查文案、长文本布局和权限弹窗。

## 翻译维护

- `Sapphire/App/Localizable.xcstrings`：简体中文界面文案。英文原文是键，未翻译项回退英文。
- `Sapphire/App/zh-Hans.lproj/InfoPlist.strings`：macOS 权限弹窗说明。
- 设置分类及简介通过 `SettingsSection` 查表本地化，保留英文搜索词；首次启动和设置页中传入组件的动态文案需显式查表。

新增界面文案时，优先使用 SwiftUI 的字面量 `Text("English text")` 或 `String(localized:)`。普通 `String` 传给 `Text(value)` 时不会自动查翻译表，应在显示处使用 `NSLocalizedString`。品牌名、协议名、路径、快捷键与格式占位符应保持原义。

项目原始许可证为 [AGPL-3.0](LICENSE)，请继续遵守其要求。
