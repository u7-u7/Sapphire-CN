# Sapphire-CN 官网与阿里云部署

## 目标与范围

用户要求复刻 sapphire-app.tech 的视觉，并明确必须使用当前项目。网站源码位于当前 Sapphire-CN 仓库的 website/，内容、截图、下载和发行信息以本项目真实资料为准。macOS 客户端代码不变。

## 实现

复用原站 CSS、主题切换、玻璃导航、渐变按钮、背景点阵和滚动动画；通过 templates/ 保存上游公开模板，adapt-project.py 生成项目官网。首屏和 AI 额度/剪贴板区域使用 docs/images 中的真实截图，读数明确标为示例。音乐、窗口和电池视频保留上游同类功能演示标记。

安装版本来自 updates/releases.json，下载固定指向公开 CN4 预发布资产。更新页读取由本地更新清单生成的 project-releases.json，避免 GitHub latest 漏掉预发布。GitHub 统计、issues 和反馈使用 u7-u7/Sapphire-CN。FAQ 根据 README 编写。上游付费计划、OTP 与 Stripe 入口替换为本项目安装教程，不宣称私有后台复刻完成。

## 部署与回退

使用 alibabacloud-workbench-cli 管理现有 ECS i-bp1163pp7k7o228siqnp / cn-hangzhou。独立 sapphire-web 静态服务绑定 127.0.0.1:8787，现有 Caddy 为 sapphire.121.41.102.231.sslip.io 增加独立代理并签发 HTTPS 证书。原有 learn.u7u7.top 配置原文保留，使用热加载，不重启服务。

后续增量发布对比 SHA256，先备份旧文件，再逐文件原子替换。配置和静态文件回退资料均在 /opt/sapphire-site/backups/。临时域名可换为用户自有域名。

## 验证

未新增测试用例。已验证本地页面引用、JS 语法、主题切换、FAQ 展开、公开 CN4 发行记录与资产、线上页面/本地哈希一致、全部79个静态文件远端哈希、视频206 Range、HTTPS和旧账号/结算地址重定向。原有站点保持可访问。
