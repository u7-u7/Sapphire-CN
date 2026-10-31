# 线上交付记录

业务日期：2026-11-01（Asia/Shanghai）。

- 网站：https://sapphire.121.41.102.231.sslip.io/
- 当前项目：u7-u7/Sapphire-CN，版本 v3.0-cn.4-preview。
- 本地源码：当前仓库 website/；README.md 和 README.zh-CN.md 已增加官网入口。
- 首次完整发布：sapphire-20261031T163401Z.tar.gz（UTC时间标识）。
- 项目适配增量：cn-20261031T164304Z、cn-20261031T164416Z。
- 所有79个静态文件远端 SHA256 与本地一致；线上页面对照见 public-verification.json。
- HTTPS 已由 Caddy/Let's Encrypt 自动签发，未跳过证书验证。
- 旧 /portal 和 /checkout.html 均302到 /download。
- 原有 Agent Path 配置原文保留且站点可访问，服务未重启。
- 浏览器确认 CN 首页、真实截图、CN4下载链接及发行说明；主题切换与 FAQ 展开通过。
- 桌面1440px和手机390px宽度检查无横向溢出；浏览器尺寸已恢复。
- 当前临时域名依赖 sslip.io。安装包由当前项目 GitHub Release 提供。

截图：deployed-home.jpg。
