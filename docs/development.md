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
