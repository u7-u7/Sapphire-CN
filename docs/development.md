# 🛠️ Sapphire-CN 开发指南

[← 返回安装与使用教程](../README.md)

## 源码安装

### 准备环境

1. **完整 Xcode**：近期本机验证使用 Xcode 27.0。仅安装命令行工具不足以构建本工程。
2. **Git**：用于下载和更新源码。
3. **有效代码签名证书及相应开发团队权限**：主程序和 Helper 必须具有匹配的签名身份。使用 Xcode 的自动签名时，团队还必须能配置所用扩展、应用组等能力。
4. **网络连接**：首次构建需要下载 Swift 包依赖；自动签名可能需要访问 Apple 的服务。

没有有效签名身份时，可以先做编译检查，但不能把未签名或 ad-hoc 临时签名应用当成 Helper 功能完整的安装版本。

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

已经有本仓库的用户无需重复下载，更新方法见[更新与卸载](../README.md#更新与卸载)。

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
4. 从「应用程序」双击启动，按[首次启动与授权](../README.md#首次启动与授权)完成设置。

之后都运行「应用程序」里的这一份，不要同时运行派生数据目录、下载目录和旧备份中的多个版本。

## 开发与验证

### 系统通知上岛

通知监听复用系统通知数据库，覆盖所有应用的系统通知，不需要逐个应用开发适配器。需要 Sapphire 的“完全磁盘访问权限”，应用自身发送通知的权限不能替代该权限。通知设置页显示连接状态，并提供“重新连接”和“显示所有应用通知”。旧安装保留原有验证码过滤设置，需要通过该按钮显式切换到全应用范围。

离线回归仅使用合成记录，不读取个人通知：

```sh
xcrun swiftc -swift-version 5 -parse-as-library \
  Sapphire/Services/Miscellaneous/NotificationDelivery.swift \
  scripts/verify-notification-delivery.swift -o /tmp/verify-notification-delivery
/tmp/verify-notification-delivery
```

实机验收应覆盖：不同应用的普通通知、连续通知、OTP 去重、单条关闭与超时、关闭通知总开关、授权失败后恢复、系统通知数据库重建、锁屏及全屏。原生横幅保持系统设置；系统静默策略与隐藏预览策略需要单独验证。应用自绘弹窗不属于此监听范围。通过离线回归及编译检查不等于已经通过上述实机验收。

连续消息修复采用按应用合并：同应用的新消息刷新当前弹窗并重新计时，其他应用各保留最新一条。普通提醒为 6 秒，有其他应用等待时限制同一应用连续占用至 12 秒。iMessage 输入回复期间保留当前消息，结束输入后刷新最新消息。去重同时比较正文及投递时间，关闭和超时按展示版本匹配，避免旧回调误关闭新内容。

健康连接的补偿检查为 1 秒，权限或连接失败时退避重试；保留数据库、WAL 和目录监听，事件合并为 50ms。新通知使用独立活动订阅。实际到达时间仍受 macOS 通知落盘与主线程负载影响，不能把该检查间隔解释为端到端延迟保证。Debug 诊断仅记录延迟、队列长度和展示状态更新，不记录来源、标题、正文或验证码。

来源应用正在前台时，其通知不会入队；切回该应用时，当前展示及排队中的同来源通知会清除，离开后不会补播。判断使用 `NSWorkspace` 的实时前台应用，支持相同 bundle identifier 和应用包内的通知助手。

需要只显示灵动岛提醒时，在 macOS“系统设置 → 通知 → 对应应用”关闭“桌面”，保持“允许通知”和“通知中心”开启。此设置由 macOS 按应用保存，退出 Sapphire 后仍然生效；新安装的应用需要单独配置。不要用关闭通知总开关、全局勿扰或现有 FocusNotificationSuppressor 代替：后者还会关闭通知中心及锁屏展示，超出隐藏右侧横幅的范围。

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

相关记录：[签名修复](plans/2026-10-13-helper-signature-repair.md)、[冷启动连接修复与验收](plans/2026-10-14-helper-cold-handshake.md)。


## CN 应用内更新发行约定

- GitHub 标签使用 `v3.0-cn.N-preview`（正式 CN 标签也可省略 `-preview`）。签名前把主应用 Info 的 `SapphireCNReleaseVersion` 设置为去掉 `v` 的相同值，并递增主应用 `CURRENT_PROJECT_VERSION`，例如 CN4 对应 `3.0 (4)`。不能复用旧 build，否则旧 Helper 会拒绝同营销版本升级。
- CN9 起主更新器优先读取 `https://sapphire-cn.oss-cn-hangzhou.aliyuncs.com/updates/releases.json`，失败时回退 `https://raw.githubusercontent.com/u7-u7/Sapphire-CN/main/updates/releases.json`；两处使用同一兼容清单，包含公开预发布。缓存/ETag 与来源绑定；CN6–CN8 仍从原 GitHub 通道升级。
- 发布 DMG，以及**只包含完整 `Sapphire.app` 的 `-update.zip`**。更新 ZIP 不得包含 `Applications → /Applications` 外链；该链接只能放在手动安装 DMG 中。ZIP 也可解压后手动安装。
- 更新器优先选择架构匹配的 `-update.zip`，核对 GitHub 资产大小和摘要，安装时核对 CN 发行标识、版本/build 单调升级、原生架构及真实同团队签名。不要用关闭这些校验来修复打包问题。
- 主程序与 Helper 的签名身份应一致。旧 Helper 接收的 `expectedVersion` 仍是实际营销版本（如 `3.0`），无需为 CN 标签更改 XPC 协议。
- 已发 CN1–CN3 的检查地址写死上游，用户首次需要手动安装包含新源的版本，不能声称旧二进制可仅靠远端发版自动换源。

- Release 公开且资产上传完成后，运行 `python3 scripts/update-cn-release-feed.py v3.0-cn.N-preview`，再提交并推送 `updates/releases.json` 到 `main`。脚本从真实 release 提取资产大小和 GitHub SHA-256，拒绝草稿、未完成上传或缺摘要的资产；不要手写测试版本或把草稿地址放进正式清单。


### CN6 新团队签名迁移

CN6 起发布签名团队为 `462JAMGP66`，主应用 build 为 6。旧 CN4 团队为 `9CN6NKVEFU`；CN4 及更早版本和 CN5 临时签名版均需手动安装一次 CN6。后续同一新团队签名版本沿用现有应用内更新，不放宽签名检查。构建、打包、验证边界见 [CN6 发行记录](releases/3.0-cn.6-preview.md)。

本次先用 `CODE_SIGNING_ALLOWED=NO` 完成 Debug arm64 编译，再由内向外用新证书统一签名所有代码。权限声明以已发布 CN4 各组件为对照保留，Helper 使用工程内空权限声明；安全时间戳启用。主应用采用 CN4 安装包已有的权限范围，不声称获得系统扩展等未配置能力。发布前对解包产物执行真实 Security framework 严格验签并核对团队、标识、版本及摘要。


### CN7 权限入口修复

CN7 继续使用团队 `462JAMGP66`，主应用 build 为 7。发布过程沿用 CN6 的签名和归档验证；额外核对 CN6 与 CN7 的标识、团队及 designated requirement 一致，build 单调递增。权限入口修复与验证范围见 [CN7 发行记录](releases/3.0-cn.7-preview.md)。


### CN8 Codex 内置 CLI 识别修复

CN8 主应用 build 为 8，继续使用团队 `462JAMGP66`。CLI 发现覆盖系统及用户 Applications 目录中的 Codex/ChatGPT 桌面应用布局；用户目录动态读取，本地 bin 与 Homebrew 优先级保留。108 项离线额度检查和排除兼容软链后的本机 GUI PATH 检查通过。发行验证范围见 [CN8 记录](releases/3.0-cn.8-preview.md)。


### CN9 OSS 更新通道

CN9 主应用 build 9，签名团队继续为 `462JAMGP66`。镜像路径必须匹配同一 CN 标签和文件名，仅信任专用 Bucket；旧字段 `browser_download_url` 保留 GitHub URL，新增 `mirror_download_url` 指向经摘要核验的镜像。网络/HTTP 失败可回退 GitHub 一次，取消或校验失败不静默换源。

公开 GitHub Release 并上传附件后，先运行 `scripts/mirror-cn-release.py <tag>` 核验公开镜像，再运行 `scripts/update-cn-release-feed.py <tag>` 生成兼容清单，最后运行 `scripts/mirror-cn-release.py <tag> --publish-feed-only` 发布 OSS 清单；提交并推送 GitHub 清单，重新生成和部署网站。运行 `python3 scripts/verify-update-source.py` 可离线验证 URL 策略、旧清单兼容、回退与取消状态。发行记录见 [CN9](releases/3.0-cn.9-preview.md)。


### CN10 系统通知上岛

CN10 主应用 build 为 10，发行标识为 `3.0-cn.10-preview`，沿用团队 `462JAMGP66` 的证书与 CN9 各组件的权限声明，按既有流程由内向外签名。更新清单继续使用 OSS 优先、GitHub 回退。安装包不包含本机测试偏好设置，不自动修改其他用户的完全磁盘访问权限或原生通知横幅。功能、权限、已验证范围及限制见 [CN10 发行记录](releases/3.0-cn.10-preview.md)。

### CN11 本地实时接管验证

CN11 按用户后续指令发布为开发预览，验证边界见 [CN11 发行记录](releases/3.0-cn.11-preview.md)。实时模式初始关闭，设置页单独开启；来源应用需保留 macOS 桌面临时横幅。只有来源、布局和恢复看护均可验证时才移走原生浮层，其他情况保留原生。实时模式不从通知数据库补弹被专注或共享策略静音的消息，传统数据库模式仍可用。

本地测试包需额外嵌入 `Contents/MacOS/SapphireNotificationRecovery`，使用主程序同团队、同 identifier 的有效签名；不能与 root Helper 混用。该同用户进程仅执行受约束的通知窗口移动及恢复。原坐标以 0600 窗口元数据日志保存，不保存通知正文。缺少看护或握手失败时不接管。

编译后用签名有效的同团队应用作权限声明参考，输出目录必须尚不存在：

```sh
python3 scripts/package-notification-local.py \
  --built-app /tmp/SapphireCNLocalizationBuild/Build/Products/Debug/Sapphire.app \
  --reference-app /Applications/Sapphire.app \
  --output /tmp/SapphireCN11Local \
  --identity '你的有效签名身份'
```

纯模型及恢复协议检查：

```sh
swiftc -swift-version 5 Sapphire/Services/Miscellaneous/NotificationRealtimeModel.swift scripts/verify-notification-realtime.swift -o /tmp/verify-notification-realtime
/tmp/verify-notification-realtime
swiftc -swift-version 5 -D NOTIFICATION_RECOVERY_TESTING Sapphire/Services/Miscellaneous/NotificationWindowRecovery.swift scripts/verify-notification-recovery.swift -o /tmp/verify-notification-recovery
/tmp/verify-notification-recovery
```

公开构建不启用受控诊断入口。需专门验收时额外传入 `SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG CN11_NOTIFICATION_DIAGNOSTICS"`。该 Debug 验收入口只生成本应用的受控通知及脱敏 AX 样本，支持正常复位、父进程强杀或暂停、看护强杀及双方退出后的冷启动恢复。直接从终端执行会使用终端的 TCC 归属；真实授权检查应从 LaunchServices 启动。一次性测试请求放在当前用户临时目录的 `SapphireCN11TestLaunch-UID.json`（0600），内容为 `{"--test-session":"UUID","--scenario":"inspect"}`；60 秒内启动时消费，不适用于 Release。样本和元数据位于 `SapphireCN11SelfTests/UUID`。共享屏幕允许通知仅可在明确临时授权后更改，结束立即恢复。

主程序死亡或主线程心跳超时后由看护恢复；看护死亡由主程序恢复。若整个进程组都被杀，需下次启动按日志恢复，无法即时复位。辅助功能撤回或通知中心无响应时保留记录并重试，设置页显示恢复未完成。真实跨应用、未知布局、通知中心展开、多屏和休眠验收完成前，不应默认开启或进入公开更新清单。
