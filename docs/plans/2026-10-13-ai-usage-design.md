# Sapphire AI 额度组件

用户已选择一个「AI 额度」组件同时显示 Codex 与 Claude，放入现有刘海展开组件栏。

## 展示与交互

- 紧凑卡片两行显示平台、剩余额度与重置倒计时；详情展示所有实际报告的窗口、已用比例、重置日期和同步时间。
- 使用现有 `.agent` 历史占位，显示名为「AI 额度」，支持设置开关和拖动排序，布局估宽 260。
- 初始关闭，由用户在设置 → 组件开启；新增字段通过既有 SettingsPersistence 默认值合并兼容旧设置。
- 额度重置时间来自平台；同步刷新间隔为 5/15/30 分钟。未知为 `—`，失效读数不能当作新数据。

## 数据与生命周期

- Codex 优先官方 `codex app-server` stdio 的 `account/read` 和 `account/rateLimits/read`，按实际时长显示额度窗口；不调用模型、登录、退出或消费重置券。
- Claude 使用既有 CLI OAuth 登录，通过只读 Keychain/CLI 凭据获取额度；不自行刷新/写回凭据，不运行消耗额度的模型 ping。
- AIUsageService 独立负责轮询、去重、超时、错误和读数隔离；AppDelegate 订阅设置变化，关闭面板不影响刷新计划。
- 请求最短 5 分钟，Claude 限流冷却至少 15 分钟；离线失败标记旧值，登录失效/账号切换清空旧值。
- 平台凭据不进入日志、设置备份或界面。Codex app-server 内部仍可执行其原生的 managed OAuth 续期。

## 实施与验证

1. 主 agent 修改设置、排序、布局、生命周期和中文资源。
2. 服务 agent 独占 Services/AIUsage 及 fixture 验证脚本。
3. UI agent 独占 Widgets/AIUsage。
4. 主 agent 汇总，检查单周窗口、0.5% 解析、缺字段、重置过期、账号切换、限流、取消及设置兼容。
5. 运行定向 Swift 解析/类型检查和 fixture 验证；按用户规则不自动全量编译或替换已安装应用。

参考：https://github.com/ericjypark/codex-island（MIT，保留版权与许可）；https://learn.chatgpt.com/docs/app-server。

真实账号取数和已安装应用的 UI 效果需要运行验证后才能认定完成。

## 本轮验证记录

- 服务独立 Swift 5 编译及 49 项离线 fixture 通过：窗口解析、未知读数、0.5%、身份变化、凭据过期、401 重读、429 冷却、停止期间晚到结果、官方 RPC 握手、超时和断管保护。
- 使用实际 WidgetLayoutPolicy 验证容量、边界、拖动次序与绕过容量开关，5 项检查通过。
- 使用实际卡片代码做中文静态渲染，正常/未知状态和详情可读；图片使用示例数据。详情内容单独渲染，实际弹窗滚动交互未验收。
- 新增服务、卡片与真实 ProcessRunner/MaterialMetricHeader 已一起通过 Swift 5、macOS 14.6 定向类型检查；实际卡片格式化另有 8 项检查通过。修改文件的 Swift 解析与 git diff --check 通过。
- 默认关闭组件，不自动替换已安装的 Sapphire，也未调用真实额度接口；首次实际取数需安装构建后开启组件并使用现有 CLI 登录。

## 使用与限制

构建安装后，在「设置 → 组件 → 组件显示与排序」开启「AI 额度」。如果屏宽容量不足，可把组件拖到靠前，或调整其他组件。

Codex 需要支持 account/rateLimits/read 的 CLI/app-server 与 ChatGPT 订阅登录。API Key 登录不提供订阅额度。

Claude 默认 macOS 配置读取当前系统用户的 Claude Code Keychain，必要时回退到凭据文件。自定义 CLAUDE_CONFIG_DIR 只读指定目录的 .credentials.json；只存在私有 Keychain 项的自定义配置本版不猜服务名，可能显示登录提示。

服务只查询额度，不调用模型；主程序不写 CLI 凭据。Codex 官方 app-server 可以按自身逻辑续期 managed OAuth。Claude 使用的 usage 接口不是稳定公开 API。

### 重跑离线服务检查

在 Sapphire 仓库根目录运行：

```sh
xcrun swiftc -swift-version 5 -parse-as-library Sapphire/Services/AIUsage/*.swift Sapphire/Services/System/ProcessRunner.swift scripts/verify-ai-usage.swift -o /tmp/sapphire-ai-usage-check
/tmp/sapphire-ai-usage-check
```

预览：[组件示例](ai-usage-preview.png)、[详情示例](ai-usage-details-preview.png)。

## 当前 Claude 第三方配置：DeepSeek

用户选择读取当前第三方余额后，已确认本机 Claude Code 连接 DeepSeek 官方 Anthropic 兼容入口。组件按实际配置读取 DeepSeek GET /user/balance；显示「Claude · DeepSeek」与人民币/美元余额，详情显示总可用、未过期赠金和充值余额。接口没有额度窗口与重置时间字段，因此显示「重置时间未提供」。不读取其他平台，不调用模型，不转换币种。

余额使用 Decimal；未知/缺失字段不造零，账号或端点变化清除旧数据。服务与新增选路共 100 项离线 fixture 通过，余额 UI 7 项格式检查通过。

真实查询验证：Codex 订阅额度及 DeepSeek API 余额查询已完成本地验证。公开文档不保留个人账号读数；额度和余额以当前账号的查询结果为准。安装后的应用 UI 验证单独记录。

依据：https://api-docs.deepseek.com/api/get-user-balance/。

## 编译与安装记录

包含 DeepSeek 余额的完整 Xcode Debug arm64 构建已成功，安装到 /Applications/Sapphire.app。本地签名后 codesign --verify --deep --strict 通过，安装后可执行文件 SHA256 与签名暂存产物一致。已开启 AI 额度，刷新间隔5分钟；设置界面观察到新开关为开启状态，应用进程运行。

安装前保留旧应用与偏好设置备份。备份包采用 .app.backup 后缀，避免 LaunchServices 将其误识别为另一个同 ID 的当前应用，恢复时可改回 .app。

实际覆盖窗口显示核验尚待完成：界面工具对无标题覆盖窗口返回 noWindowsAvailable，已请求用户以 Command 点击刘海展开默认组件栏。不能用成功构建、签名、进程存在或接口点查替代覆盖窗口验收。
