# 第三方额度查询

用户已选择在 Sapphire 为 Codex、Claude 分别配置第三方额度查询地址，并提供模板和测试按钮。

## 已确认设计

- 每个平台保存查询配置：供应商名称、当前模型地址（绑定）、完整 HTTPS 查询 URL、模板、认证方式、凭据来源、单位与换算除数、JSON 点路径、可选重置格式。
- 支持 DeepSeek、Sub2API、NewAPI 模板，以及自定义只读 GET/JSON 字段映射。NewAPI 使用账户 Access Token 与 User ID，默认除数 500000 可调。
- 表单使用草稿；测试只返回预览，保存查询设置后才进入正常轮询。
- 独立密钥进入 Keychain，按平台、模型地址、查询地址、认证方式和用户 ID 绑定，不进入 Settings 或普通备份。
- 官方订阅与现有 DeepSeek 自动读取保留；API key 模式未配置通用查询时提示填写查询地址。
- 余额、已用、总额、剩余、次数和不限量分别保留语义；未知不造零，重置时间仅来自实际字段。

## 工程分工与验证

- 查询 agent：新增配置类型、共用 GET 客户端与离线协议 fixture。
- 设置 agent：独占新设置视图，草稿/测试/密钥保存。
- 显示 agent：独占额度卡片通用化。
- 主 agent：Settings 持久化、CLI 绑定解析、Keychain、服务门禁、生命周期、资源与最终集成。

沿既有 AIUsageService 的请求间隔与 429 冷却；测试和自动查询共享门禁，不通过保存/切换开关绕过限流。配置改变或账号切换清掉旧读数，晚到响应不能写回新配置。

Codex 只读取标准 auth.json、config.toml 的命名 provider/profile 与 env_key，不执行 api_key_helper 或 shell。CLI 在运行时传入的参数或本机不可读取的环境变量，可能需要用户提供独立查询密钥；不猜测其他账号。

本轮先做源代码、离线客户端/生命周期验证和局部类型检查。完整构建/安装与真实第三方查询需单独记录实际结果；已有安装回执不代表这版新配置已安装。

参考 CC Switch：provider 级 usage_script、NewAPI/Sub2API 模板、request/extractor 协议。Sapphire 本版使用声明式 JSON 映射，不运行任意 JS。

## 实施与安装结果

客户端64项、既有服务100项、CLI绑定/Keychain scope/服务集成20项，以及显示格式17项离线检查通过。新客户端、服务、设置表单和显示组件一起通过Swift 5/macOS14.6定向类型检查，完整Xcode Debug arm64构建成功。

已本地签名并更新 /Applications/Sapphire.app，严格递归签名校验通过，可执行文件 SHA256 与暂存产物匹配。安装前已备份旧版和偏好设置。

用户填写的通用第三方查询未运行真实接口。新配置默认禁用，既有官方/DeepSeek自动读取保留；当前安装的查询表单仍需UI核实。

使用：设置 → 小组件 → AI额度 → Codex/Claude第三方额度。编辑本地草稿，填当前模型地址及查询地址，应用模板、确认认证与单位，测试后保存查询设置；独立查询key需在配置已保存后存入Keychain。改变查询目标不会复用旧目标的key。

模板：DeepSeek /user/balance；Sub2API /v1/usage；NewAPI /api/user/self（账户Access Token＋User ID，默认scale500000可调）。自定义为只读HTTPS GET与JSON点路径映射，可选ISO8601/Unix秒/毫秒重置字段。

Codex支持文件中的命名provider与profile，当前应用可读环境中的env_key；不执行api_key_helper，也不读取运行中CLI的私有进程环境。暂不自动导入CC Switch查询脚本，不执行JS。
