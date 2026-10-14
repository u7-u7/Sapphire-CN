# Sapphire-CN：中文刘海屏工具与 AI 额度看板

Sapphire-CN 基于 [Sapphire](https://github.com/cshariq/Sapphire)，提供主要界面的简体中文翻译，并增加 Codex、Claude 官方订阅额度和第三方平台余额查询。

**当前版本：`v3.0-cn.1-preview`（开发预览）**。包含中文界面、AI 额度查询和 Helper 冷启动连接修复。

**[下载 DMG 安装包](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/Sapphire-CN-3.0-cn.1-preview-arm64.dmg)** · [ZIP 备用下载](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/Sapphire-CN-3.0-cn.1-preview-arm64.zip) · [发布说明与校验文件](https://github.com/u7-u7/Sapphire-CN/releases/tag/v3.0-cn.1-preview)

适用于 **Apple 芯片 Mac（arm64）**，项目最低部署版本为 **macOS 14.6**。使用安装包无需安装 Xcode；当前没有 Intel 安装包。

**本包使用 Apple Development 开发签名，未完成 Apple 公证。** macOS 默认安全检查可能阻止首次打开，不能当作已公证正式发行版。安装前请阅读[安装包安装](#安装包安装)中的签名限制；需要自行编译或使用自己的签名身份时，阅读[源码安装](#源码安装)。

上游发布页提供的是原版，不包含本分支新增功能。本分支安装包以本仓库 Releases 为准。

## 快速安装与上手

1. **下载并安装**：下载上方 DMG，退出旧版 Sapphire，打开镜像，将 `Sapphire.app` 拖到 `Applications`，从「应用程序」启动。旧版替换前请先备份。
2. **处理首次打开提示**：如被 macOS 拦截，先核对来源和[校验文件](#校验下载文件)，再按[首次打开被系统拦截](#首次打开被系统拦截)中的步骤处理。
3. **完成授权并切换中文**：跟随引导授予所需权限；在「系统设置 → 通用 → 语言与地区 → 应用程序」为 Sapphire 选择「简体中文」，重新启动。详见[首次启动与授权](#首次启动与授权)。
4. **打开面板**：按住 **⌘ Command** 点击刘海区域，点击齿轮进入设置。默认未开启鼠标悬停展开。
5. **开启 AI 额度**：进入「设置 → 小组件 → 小组件可见性和顺序」，启用「AI 额度」，再按[账户与平台配置教程](#配置-ai-额度)完成登录或接口设置。

电池等功能需要 Helper 时，在「设置 → 电池 → 配置」点击「安装」，按系统提示批准后台运行；首次连接可能需要等待 30 秒。钥匙串授权由本人在系统弹窗中处理，选择单次允许后，后续启动可能再次询问。

## 教程目录

- [快速安装与上手](#快速安装与上手)
- [安装前准备](#安装前准备)
- [安装包安装](#安装包安装)
- [源码安装](#源码安装)
- [首次启动与授权](#首次启动与授权)
- [基础使用](#基础使用)
- [配置 AI 额度](#配置-ai-额度)
- [常见问题](#常见问题)
- [更新与卸载](#更新与卸载)
- [开发与验证](#开发与验证)
- [来源与许可证](#来源与许可证)

## 能做什么

| 功能 | 使用方式 |
| --- | --- |
| AI 额度 | 在刘海区域查看 Codex、Claude 的额度窗口、余额、同步状态和服务端返回的重置时间 |
| 第三方余额查询 | 分别配置 Codex、Claude 的供应商查询接口，支持 DeepSeek、Sub2API、NewAPI 和自定义 JSON 模板 |
| 刘海小组件 | 在设置里启用、关闭、调整组件顺序，查看播放信息、日历等内容 |
| 桌面辅助功能 | 按需配置窗口管理、文件托盘、剪贴板、护眼提醒和电池相关功能 |
| 中文界面 | 主要设置、首次启动和权限说明支持简体中文；少量界面提示仍可能显示英文 |

公开源码包含部分功能占位实现。依赖上游订阅、额外服务配置或系统扩展的功能，以实际配置和界面状态为准，不能仅凭构建成功认定全部功能可用。

## 安装前准备

### 运行环境

- 项目最低部署版本为 **macOS 14.6**。
- 已完成构建与运行验收的机器为 **Apple 芯片 Mac**；Intel Mac 尚未完成本分支的完整验收。
- 展示效果以带刘海屏的 MacBook 为主要使用场景，其他屏幕的布局需要自行检查。

### 从源码安装需要什么

1. **完整 Xcode**：近期本机验证使用 Xcode 27.0。仅安装命令行工具不足以构建本工程。
2. **Git**：用于下载和更新源码。
3. **有效代码签名证书及相应开发团队权限**：主程序和 Helper 必须具有匹配的签名身份。使用 Xcode 的自动签名时，团队还必须能配置所用扩展、应用组等能力。
4. **网络连接**：首次构建需要下载 Swift 包依赖；自动签名可能需要访问 Apple 的服务。

没有有效签名身份时，可以先做编译检查，但不能把未签名或 ad-hoc 临时签名应用当成 Helper 功能完整的安装版本。

## 安装包安装

### 下载安装包

打开[本分支开发预览发布页](https://github.com/u7-u7/Sapphire-CN/releases/tag/v3.0-cn.1-preview)，在附件中选择：

| 文件 | 用途 |
| --- | --- |
| [DMG 安装镜像](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/Sapphire-CN-3.0-cn.1-preview-arm64.dmg) | 推荐，打开后拖动应用到“应用程序” |
| [ZIP 应用压缩包](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/Sapphire-CN-3.0-cn.1-preview-arm64.zip) | 备用方式，解压后复制完整应用 |
| [SHA-256 校验文件](https://github.com/u7-u7/Sapphire-CN/releases/download/v3.0-cn.1-preview/SHA256SUMS.txt) | 核对下载文件是否与发布包一致 |

发布页自动提供的源码压缩包用于开发；安装应用请选择上表中的 DMG 或应用 ZIP。安装包只面向 Apple 芯片，不提供 Intel 构建。

### 拖动安装

1. 在苹果菜单「关于本机」确认使用 Apple 芯片及兼容的 macOS 版本。退出已经运行的 Sapphire，并备份旧 `Sapphire.app`。
2. 双击 DMG，在打开的窗口中把 `Sapphire.app` 拖到 `Applications` 图标。使用 ZIP 时，解压后将完整 `Sapphire.app` 复制到「应用程序」。
3. 从 `/Applications/Sapphire.app` 启动，按照[首次启动与授权](#首次启动与授权)完成设置。
4. 用系统的应用语言设置选择简体中文，按住 ⌘ 点击刘海打开组件面板。
5. 在「设置 → 小组件 → 小组件可见性和顺序」启用 AI 额度，然后按下面教程配置自己的账户或查询接口。

该安装方式无需在你的 Mac 上重新编译应用。应用内部版本仍显示 `3.0 (1)`，本仓库发布标签是 `v3.0-cn.1-preview`。

### 开发预览的签名限制

本包已通过严格深度签名验证，主程序与 Helper 使用匹配的 Apple Development 开发签名；本机真实握手已验证，但 Gatekeeper 评估结果为拒绝，尚无 Apple 公证票据。

如果 macOS 阻止首次启动，仅在确认信任本仓库来源后，参考 [Apple 官方打开说明](https://support.apple.com/en-us/102445)，由你本人决定是否允许打开。该流程不保证其他机器一定可以运行；系统仍不允许启动时，可以使用自己的有效签名从源码构建，或等待 Developer ID 签名并公证的正式版本。

无需关闭全局安全保护，也不要把移除签名或改成 ad-hoc 临时签名当作 Helper 的修复方式。项目最低部署版本为 macOS 14.6，其他机器和整机重启后的实际冷启动仍未完成验收。

### 首次打开被系统拦截

若提示「无法验证开发者」或「Apple 无法检查是否包含恶意软件」，并且你确认安装包来自本仓库、校验值一致，可按 [Apple 中文官方说明](https://support.apple.com/zh-cn/102445)操作：

1. 先尝试打开「应用程序」中的 Sapphire，让系统显示拦截提示。
2. 打开「系统设置 → 隐私与安全性」，向下找到 Sapphire 对应的提示；决定继续时，点击「仍要打开」。
3. 按系统要求由本人认证，在再次出现的提示中确认「打开」。

该按钮可能受系统版本或设备管理策略限制；没有对应按钮或仍然无法打开时，请参照 Apple 说明处理。若提示应用损坏或将损坏电脑，请停止打开，按 Apple 对应说明排查。当前开发签名包不能保证在其他 Mac 上成功运行。

### 校验下载文件

把下载的安装包和 `SHA256SUMS.txt` 放在同一目录，在该目录的终端中运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

同时下载 DMG 和 ZIP 时，两项都应显示 `OK`。仅下载其中一项时，已下载文件应显示 `OK`，另一项会提示文件不存在；请核对自己实际下载的那一项。

## 源码安装

### 第一步：安装并初始化 Xcode

安装完整 Xcode，至少打开一次，按照向导处理许可和所需组件。

在终端检查：

```sh
xcode-select -p
xcodebuild -version
```

第一条通常应显示 `/Applications/Xcode.app/Contents/Developer`。如果仍指向命令行工具目录，且你的 Xcode 安装在上述位置，可切换：

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### 第二步：下载源码

在你准备保存项目的目录中运行：

```sh
git clone --depth 1 https://github.com/u7-u7/Sapphire-CN.git
cd Sapphire-CN
open Sapphire.xcodeproj
```

已经有本仓库的用户无需重复下载，更新方法见[更新与卸载](#更新与卸载)。

### 第三步：配置你自己的签名

这一步用于生成可在本机运行的开发版本，不等于制作已公证、可向所有用户分发的安装包。

1. 在 Xcode 的「设置 → 账户」添加自己的 Apple 账户。
2. 在账户的证书管理中创建或确认有效的 `Apple Development` 证书。
3. 选择项目，检查各个会嵌入应用的目标的签名与能力配置，选择自己的开发团队，按团队权限启用自动签名。
4. 重点确认 `Sapphire` 与 `com.shariq.sapphireHelper` 使用匹配的开发团队与签名身份；其他嵌入的扩展目标也需要有效签名。
5. 工程保留了上游团队配置，不能直接沿用。遇到应用组、扩展或描述文件错误，需要先解决团队能力及授权文件配置。
6. 保留 Helper 的空权限声明文件和工程已有重签步骤。不要把主程序的权限声明复制给 root Helper，也不要通过放宽客户端安全校验来绕过签名问题。

可用以下命令检查本机是否存在有效签名身份：

```sh
security find-identity -v -p codesigning
```

若结果是 `0 valid identities found`，请先回到 Xcode 完成证书配置。团队编号从 Xcode 或 Apple 开发者账户查看，不要把证书显示名称末尾的编号直接当作团队编号。

### 第四步：构建开发版本

完成签名配置后，可以在 Xcode 选择 `Sapphire` 方案、运行目标选择本机 Mac，使用调试配置构建。

也可以在仓库目录中运行下面的终端命令。先把 `你的团队编号` 替换成自己在上一步确认的编号：

```sh
SAPPHIRE_TEAM_ID='你的团队编号'

xcodebuild -project Sapphire.xcodeproj -scheme Sapphire \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/SapphireDerivedData \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$SAPPHIRE_TEAM_ID" \
  CODE_SIGN_IDENTITY='Apple Development' \
  CODE_SIGNING_ALLOWED=YES build
```

看到 `BUILD SUCCEEDED` 才表示构建成功。以上命令的应用产物位于：

```text
/tmp/SapphireDerivedData/Build/Products/Debug/Sapphire.app
```

Xcode 图形界面的构建可能使用其他派生数据目录，可以在构建产物上使用「在访达中显示」定位。

如果当前只想检查源码能否编译，使用下列命令即可；它不完成实际安装所需的证书签名：

```sh
xcodebuild -project Sapphire.xcodeproj -scheme Sapphire \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/SapphireDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

本地开发优先使用调试配置。发布配置还包含上游 Crashlytics 上传步骤，需要额外配置，不能视作公开源码的一键发布入口。

### 第五步：检查签名

以下命令对应上面终端构建的固定产物路径。其他路径请自行替换：

```sh
SAPPHIRE_APP='/tmp/SapphireDerivedData/Build/Products/Debug/Sapphire.app'

codesign --verify --deep --strict "$SAPPHIRE_APP"
codesign -dv --verbose=2 "$SAPPHIRE_APP"
codesign -dv --verbose=2 "$SAPPHIRE_APP/Contents/MacOS/com.shariq.sapphireHelper"
```

检查要点：

- 第一条命令成功退出，未报告签名损坏。
- 主程序与 Helper 都有有效签名身份，团队标识匹配；不能只有临时签名或没有团队标识。
- 主程序签名标识为 `com.cshariq.sapphire`，Helper 为 `com.shariq.sapphireHelper`。
- 深度验证通过仅证明签名有效，实际安装后还要确认应用能连接 Helper。

Apple 建议嵌套代码由内向外完成签名。工程已有相应构建步骤，不要把 `codesign --deep` 递归重签当成修复所有权限问题的通用命令。参考 [Apple 签名说明](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)。

### 安装到应用程序

1. 先退出正在运行的 Sapphire。
2. 如果「应用程序」中已有旧版，先在其他目录备份旧 `Sapphire.app`。
3. 将已通过签名检查的 `Sapphire.app` 复制到「应用程序」，最终路径为 `/Applications/Sapphire.app`。
4. 从「应用程序」双击启动，继续完成下面的首次授权。

之后都运行「应用程序」里的这一份，不要同时运行派生数据目录、下载目录和旧备份中的多个版本。

## 首次启动与授权

### 设置简体中文

1. 打开 macOS「系统设置 → 通用 → 语言与地区 → 应用程序」。
2. 添加或选择 `/Applications/Sapphire.app`。
3. 将语言设为「简体中文」，退出并重新启动 Sapphire。

### 完成首次引导

跟随欢迎界面操作。当前引导中唯一列为必需的系统权限是 **辅助功能**；其他权限按需要使用的功能授予即可。

| 权限或系统提示 | 用途 | 如何处理 |
| --- | --- | --- |
| 辅助功能 | 窗口管理、媒体按键及相关交互 | 在「系统设置 → 隐私与安全 → 辅助功能」允许当前安装的 Sapphire |
| 允许在后台运行 | 启动 Helper，支持电池管理和部分系统集成 | 在「系统设置 → 通用 → 登录项与扩展」找到对应后台项并允许；旧系统的页面可能叫「登录项」 |
| 通知、日历、位置、蓝牙 | 对应提醒、日程、天气和设备信息 | 使用对应功能时再授权 |
| 屏幕录制、自动化、完全磁盘访问 | 对应窗口预览、媒体控制、文件等功能 | 按实际功能的提示授权 |
| 钥匙串访问 | 读取已有剪贴板加密密钥或账号查询凭据 | 密码只在 macOS 系统提示中输入；可以选择单次「允许」，也可按自己的偏好选择「始终允许」 |

辅助功能、后台项和钥匙串是不同授权。打开其中一项不代表其他项已经完成。

如果只允许本次钥匙串访问，后续启动再次提示属于正常授权行为；不要为了省去提示而清空钥匙串。系统权限已开启但应用仍认为未授权时，确认授权对象是当前 `/Applications/Sapphire.app`，尤其留意替换签名或同时安装多个版本的情况。

### 确认 Helper 状态

1. 按住 ⌘ 点击刘海区域打开组件面板，再点击齿轮打开设置。
2. 进入「电池 → 配置」，查看顶部辅助服务状态。
3. 未安装时点击「安装」（首次引导中的对应按钮叫「安装辅助服务」），按 macOS 提示批准后台运行。
4. 已批准但仍在启动时，先等待首次验签完成；新版首次连接有 30 秒宽限期。
5. 确认显示辅助服务已运行；某些未译界面可能显示 `Helper Active`。

## 基础使用

1. 按住 ⌘ 点击屏幕顶部刘海区域，打开组件面板；启用悬停展开后，也可以移入鼠标展开。默认配置未开启悬停展开。
2. 点击齿轮进入设置。
3. 打开「小组件 → 小组件可见性和顺序」，启用需要的组件并调整排序。
4. 关闭设置，回到刘海面板查看内容。屏幕空间不足时，可以关闭暂时不用的组件。
5. 音乐、日历、文件托盘、剪贴板、护眼和电池等功能，在对应设置分类中按需配置。

## 配置 AI 额度

### 先开启组件

1. 打开「设置 → 小组件 → 小组件可见性和顺序」。
2. 启用「AI 额度」。
3. 在出现的 AI 额度配置中选择每 5、15 或 30 分钟自动刷新。
4. 回到刘海面板，点击 AI 额度进入详情，查看读数、同步状态和重置时间。
5. 点击刷新按钮可主动查询；手动刷新仍遵守最小请求间隔与服务端限流冷却。

额度详情展开后，鼠标移到下方刷新按钮和滚动区域时会保持面板展开。

### Codex 官方订阅

1. 按 [Codex 官方安装教程](https://learn.chatgpt.com/docs/codex/cli)安装命令行工具。
2. 在终端执行以下命令，使用要查看额度的 ChatGPT 账户登录并确认状态：

```sh
codex login
codex login status
```

3. 回到 Sapphire，保持 Codex 的第三方查询关闭，刷新 AI 额度。

登录方式参考 [OpenAI 官方认证说明](https://learn.chatgpt.com/docs/auth)。本组件通过 Codex 的账号查询读取订阅额度，不创建对话或请求模型。仅使用 API 密钥的账户需要配置对应平台的第三方额度接口。

### Claude 官方订阅

1. 按 [Claude Code 官方安装教程](https://code.claude.com/docs/zh-CN/setup)安装命令行工具。
2. 使用要查看额度的官方账户登录，确认状态：

```sh
claude auth login
claude auth status
```

3. 确认 Claude Code 当前使用官方服务配置，再回到 Sapphire，保持 Claude 的第三方查询关闭，刷新 AI 额度。关闭 Sapphire 的第三方开关不会改变 Claude Code 的供应商配置。
4. 如果系统要求允许读取该账户的钥匙串凭据，由你本人在系统提示中处理。

登录过期时需要在 Claude Code 中重新登录。Sapphire 的刷新按钮只查询额度，不替你登录或更新登录凭据。

### DeepSeek 余额

如果 Claude Code 的当前配置已使用 DeepSeek，Sapphire 会识别相应供应商配置并查询 API 余额，不借用另一个 Claude 官方账户的读数。

也可以在 Claude 的第三方额度配置中选择 DeepSeek 模板，填写供应商地址与正确查询凭据，按照下一节完成测试和保存。

DeepSeek 没有返回重置时间时，界面会显示未提供；余额不会被换算成 Claude 官方订阅的百分比。

### 其他第三方平台

Codex 与 Claude 的查询设置相互独立，请填写与你实际使用的平台对应的一组。

1. 在「设置 → 小组件」中启用 AI 额度，找到「Codex · 第三方额度」或「Claude · 第三方额度」。
2. 打开对应的第三方查询开关，填写平台名称和「当前供应商 API 地址」。
3. 选择 DeepSeek、Sub2API、NewAPI 或自定义 JSON 模板。使用预设时点击「应用模板」；该操作会重新填写部分认证和字段设置。
4. 按供应商文档核对「额度查询地址」。它是余额或额度接口的 HTTPS 地址，不是聊天补全接口；模板提供的地址可能需要修改。
5. 选择认证方式和凭据来源。复用命令行凭据时，供应商地址必须与当前命令行配置一致；使用独立查询凭据时，填写查询密钥或账户访问令牌。
6. 展开「JSON 字段与重置时间」，核对余额、已用、总额、币种、数值除数和重置时间字段。没有返回的字段留空即可。
7. 点击「测试额度查询」，核对预览中的读数和单位。测试使用草稿，不自动保存配置或输入的密钥。
8. 点击「保存查询设置」。
9. 使用独立密钥时，再点击「保存查询密钥」。该按钮只有在配置已经保存且密钥非空时才可用；独立密钥保存在 macOS 钥匙串中。
10. 回到刘海详情，按刷新间隔确认新读数。

| 平台 | 需要特别核对的内容 |
| --- | --- |
| DeepSeek | 当前 API 地址、可查询余额的密钥；没有重置时间时保持未提供 |
| Sub2API | 查询接口和认证由供应商部署决定，不能保证所有平台都使用模板地址 |
| NewAPI | 使用本模板必须填写账户访问令牌和用户编号，不能直接把模型 API 密钥当作账户查询令牌；用户编号输入框虽标为可选，本模板实际必填 |
| 自定义 JSON | 按真实返回值填写点分路径，例如 `data.balance` 或 `balance_infos.0.total_balance` |

NewAPI 模板的默认数值除数为 `500000`，请按平台实际换算规则修改。服务器没有币种信息时，也需要核对回退单位；填写了美元标签不代表系统已经完成人民币与美元的汇率换算。

修改查询地址、认证方式或用户编号后，可能需要为新配置重新保存独立查询密钥。额度查询密钥与目标配置绑定，不会自动借用另一个平台的密钥。

## 常见问题

### 安装包在哪里，为什么系统可能不让打开？

安装包在[本分支发布页](https://github.com/u7-u7/Sapphire-CN/releases/tag/v3.0-cn.1-preview)。当前是 Apple Development 签名、未公证的开发预览，系统可能阻止启动；处理路径见[签名限制](#开发预览的签名限制)。上游原版安装包不包含本分支的新功能。

### 构建提示找不到签名身份、描述文件或应用组怎么办？

检查 Xcode 账户、有效证书、各目标的开发团队与能力配置。工程中的上游团队不能直接替换成任意团队后就保证所有扩展可用。先解决具体的签名错误，再构建安装；`CODE_SIGNING_ALLOWED=NO` 只跳过构建签名，不解决运行时授权。

### 应用已启动，但 Helper 提示 SAP-H1 怎么办？

SAP-H1 表示后台权限已允许，但应用无法连接 Helper，不能据此认定 Helper 进程没有启动。

1. 刚启动时先等待首次验签完成。
2. 检查后台运行批准是否开启。
3. 核对主程序与 Helper 的签名身份，确认没有把未签名或临时签名产物当正式安装版运行。
4. 确实无法恢复时，在「设置 → 电池 → 配置」中手动「重置辅助服务」。

新版会保留等待中的连接，避免因为短超时反复重连；后台启动失败保留状态提示。不要反复点重置，也不要清空整个系统的后台项目数据库。

SAP-H2 对应等待后台批准，SAP-H3 对应辅助服务文件或注册缺失，需按应用中的提示分别处理。

### 为什么一直出现钥匙串提示，或者界面暂时不响应？

应用可能正在等待系统允许读取剪贴板加密密钥或登录凭据。检查 macOS 的钥匙串提示并本人处理。单次「允许」可能使后续启动再次询问；「始终允许」是可选项，不是必需权限。

### AI 额度显示未登录、无法查询或未知怎么办？

- **找不到 Codex 命令行工具**：按官方教程安装后，在终端确认能运行 `codex --version`，再重新启动 Sapphire。
- **官方账户未登录或已过期**：在对应命令行工具中完成登录，确认是要查看额度的账户。
- **第三方认证失败**：确认查询接口要求的是模型密钥还是账户访问令牌，并核对用户编号、认证方式与供应商地址。
- **命令行凭据读取不到**：图形应用可能读取不到只在某个终端会话中设置的环境变量。确认供应商配置已持久保存，或改用独立查询密钥。
- **测试成功但组件没有更新**：确认已保存查询设置；独立密钥还需单独保存，然后等待刷新间隔或限流冷却结束。
- **读数或单位不对**：核对 JSON 字段、数值除数与币种。不能把供应商的原始积分直接当货币。
- **没有重置时间**：服务端没有返回时显示未知或未提供；Sapphire 不推测日期。
- **请求过于频繁**：等待冷却，连续点击刷新不会绕过服务端限流。

## 更新与卸载

**安装包用户和源码用户都请注意：应用内的 Sapphire 更新检查目前仍指向上游仓库，提示中的安装包属于原版，安装后将不再包含本分支新增功能。** 不希望自动下载原版时，可以在「关于」页面的更新偏好中关闭自动下载选项。本分支请使用[本仓库 Releases](https://github.com/u7-u7/Sapphire-CN/releases)或下面的源码更新流程。

### 更新安装包版本

从[本仓库 Releases](https://github.com/u7-u7/Sapphire-CN/releases)获取新的中文安装包。先退出应用并备份旧版，按新的发布说明检查架构、签名与校验值，再替换「应用程序」中的旧版；最后确认后台服务和 AI 额度正常。

### 更新源码安装版

1. 退出 Sapphire，备份当前已签名应用。
2. 进入仓库目录，在没有未提交修改的情况下更新：

```sh
git pull --ff-only
```

3. 使用相同的签名身份重新构建，完成签名检查，再替换「应用程序」中的旧版。
4. 重新启动，确认辅助功能、后台服务和 AI 额度状态。

不要用未签名构建产物直接覆盖已签名安装版。签名身份变化后，系统可能需要重新确认权限或钥匙串访问。

### 卸载

先退出 Sapphire，再把「应用程序」中的 `Sapphire.app` 移到废纸篓。需要关闭后台运行时，在系统的登录项与扩展页面处理对应条目。不要为普通卸载清空整个钥匙串或系统后台项目记录。

## 开发与验证

### Helper 连接边界检查

在仓库目录运行：

```sh
xcrun swiftc -swift-version 5 -parse-as-library \
  Sapphire/App/XPCClient.swift \
  com.shariq.sapphireHelper/HelperProtocol.swift \
  scripts/verify-helper-handshake.swift -o /tmp/verify-helper-handshake

/tmp/verify-helper-handshake --cold-start
```

该检查用真实匿名 XPC 模拟 15 秒验证延迟，覆盖并发握手、超时、拒绝和连接替换等 14 项边界，不调用本机 root Helper。模拟检查通过不能替代实际签名和整机重启验收。

### 维护中文翻译

- 主界面翻译资源：`Sapphire/App/Localizable.xcstrings`。
- 系统权限说明：`Sapphire/App/zh-Hans.lproj/InfoPlist.strings`。
- 新增动态设置标题或说明时，沿用项目现有本地化调用方式。
- 修改后检查中英文显示、长文本布局、按钮含义和实际交互，不把“资源已翻译”当作“页面已验收”。

相关记录：[签名修复](docs/plans/2026-10-13-helper-signature-repair.md)、[冷启动连接修复与验收](docs/plans/2026-10-14-helper-cold-handshake.md)。

## 来源与许可证

- 上游项目：[cshariq/Sapphire](https://github.com/cshariq/Sapphire)，保留原作者与贡献者署名。
- 本分支：[u7-u7/Sapphire-CN](https://github.com/u7-u7/Sapphire-CN)。
- 项目遵循 [AGPL-3.0 许可证](LICENSE)。第三方代码、资源与依赖的许可证以仓库内相应声明为准。
