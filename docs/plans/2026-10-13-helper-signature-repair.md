# SAP-H1 本机签名修复

## 原因

原安装包主应用和 Helper 均为 ad-hoc 签名，没有 TeamIdentifier。
Helper 实际由 launchd 以 root 启动，但 `CodesignCheck.trustedSignerMatches`
明确拒绝 root Helper 接受 ad-hoc 客户端，因此出现 XPC 拒绝。
SAP-H1 只表示“后台已批准但 ping 失败”，不能据此判断 Helper 未启动。
Reset Helper 重注册后仍使用相同签名，失败时自动重启，因而再次出现弹窗。

## 执行

- 保留源码与客户端安全校验，未调整辅助功能等系统隐私权限。
- 原包已备份到本机 `SapphireBackups/2026-10-13-helper-signature-233820/Sapphire-before-helper-signature.app.backup`。
- 在同目录 Staged 中，用本机有效 Apple Development 证书重新签名主应用和 Helper。
- 两者 TeamIdentifier 均为 `9CN6NKVEFU`；Helper 保留空 entitlements 和 hardened runtime。
- `codesign --verify --deep --strict` 验证通过后，安装到 `/Applications/Sapphire.app` 并重启。
- 应用后续自动重注册了 Helper，launchctl 的身份约束已更新为相同 TeamIdentifier。

## 验证证据

- 23:39:00：主应用 PID 53071 首次 ping 成功，协议版本 11 / 11。
- 首次证书校验存在多秒等待，超过当前 ping 的两秒超时，会触发自动重注册。
- 23:43:30：新注册 Helper PID 57683 与主应用 PID 57922 成功连接，首次 ping 成功，协议版本 11 / 11。
- 23:43:18 的 `-67065`（errSecCSNoSuchCode，找不到请求的 guest）关联已退出的旧客户端 PID 56628，不能归为新客户端持续拒绝。
- 23:45:09：再次重启后的主应用 PID 61085 首次 ping 成功，协议版本 11 / 11；Helper 仍为 PID 57683，无再次重注册。
- 原签名授权问题已修复。系统重启后的冷启动未验证；两秒 ping 超时与冷启动严格验签之间仍存在时序风险，本次未改动该逻辑。

## 后续安装约束

后续本地构建安装时，应继续用同一个有效代码签名证书签名主应用和 Helper。
重新用 `codesign --sign -` 安装会丢失签名身份并重新触发 root Helper 拒绝。
不应移除 root ad-hoc 限制，也不应重置全系统后台项目数据库。

本次没有修改应用源码，没有执行完整编译；验证的是现有安装包签名与真实 XPC 连接。
