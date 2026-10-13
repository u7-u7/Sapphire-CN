# Helper 冷启动握手超时修复

## 问题与方案

已观察到首次严格验签耗时数秒至十余秒，而健康检查只等待两秒。
旧实现超时后立即强制重连，注册探测也反复强制重连，打断仍在验签的连接并积累校验队列。
最终把正常的冷启动当成 Helper 故障并弹出 SAP-H1。

修复限制在客户端连接生命周期与主应用 Helper 状态管理，保留服务端每条新连接的完整静态、嵌套与动态验签。
不缓存客户端授权，不放开 root Helper 的 ad-hoc 签名限制。

- 每条新连接的首次握手设 30 秒宽限期，使用单调时钟；并发 ping 和协议查询共享宽限期，不对每次探测重新开启 30 秒等待。
- 已完成握手后保留调用方指定的短健康超时。超时只结束请求，不销毁连接；明确 XPC 错误、失效或主动重置仍可重连。
- 首次握手成功后确认回包属于当前连接，防止旧连接迟到响应恢复新连接状态。
- 注册后重试复用连接。后台启动只有明确协议不匹配才重装；协议查询超时为未知，不触发重装。
- 后台启动的 SAP-H1 只保留设置页状态提示；主动安装/修复仍可弹错误提示，登录项授权与缺失注册的提示继续保留。
- 用户主动操作使旧启动探测失效；Reset 在入口同步占位，避免连续点击排入多个重置任务。

## 验证方法

真实匿名 XPC listener 模拟验签等待，编译生产 `XPCClient` 和 `HelperProtocol`，不调用 root 服务或系统设置：

```sh
xcrun swiftc -swift-version 5 -parse-as-library \
  Sapphire/App/XPCClient.swift \
  com.shariq.sapphireHelper/HelperProtocol.swift \
  scripts/verify-helper-handshake.swift -o /tmp/verify-helper-handshake
/tmp/verify-helper-handshake --cold-start
```

覆盖 15 秒验证延迟下的并发短探测、单连接复用、协议查询、无回复的有界等待、不续期、真实拒绝后的重连、短健康超时、迟到回复与主动连接替换。
匿名 listener 测试证明连接时序，不代替实际 Security 验签。

完整应用在最终安装验证时构建；安装包主应用和 Helper 须使用相同有效签名身份并通过深度严格校验。
实际整机重启需要用户自行执行，本轮不主动重启电脑。

## 结果

- 匿名 XPC 验证：14 项检查通过，包括 `--cold-start` 的 15 秒监听端延迟、并发探测和协议查询；仅建立一条连接。
- 最终完整应用构建通过：`/tmp/SapphireHelperHandshakeBuild-20261014-final.log`；初次构建结果包为 `/tmp/SapphireHelperHandshakeBuild-20261014.xcresult`。
- 新主程序 UUID：`1448B3A9-15EB-3D26-9E8A-4E0F12BE590D`。动态依赖与原安装版一致，安装时只替换主程序，保留已有签名 Helper、扩展和资源。
- 同证书重签后严格深度验证通过，已安装到 `/Applications/Sapphire.app`。原包备份到本机 `SapphireBackups/2026-10-14-helper-cold-handshake-005910/Sapphire-before-cold-handshake.app.backup`。
- 初次启动进程 PID 16461；Helper 仍为 PID 57683。新版主线程在已有剪贴板密钥的钥匙串读取上等待系统授权，尚未执行 Helper 握手。匿名 XPC 验证不能代替本次真实握手验收。
- 正在等待用户完成 macOS 钥匙串授权，之后补充真实 ping、协议版本和重启结果；本轮未执行整机重启。
