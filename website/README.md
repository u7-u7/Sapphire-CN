# Sapphire-CN 项目网站

线上地址：https://sapphire.u7u7.top/

网站位于当前 `u7-u7/Sapphire-CN` 工程内，沿用 https://sapphire-app.tech/ 的深色点阵、玻璃导航、渐变按钮、主题切换和滚动动画。内容、下载、更新和反馈使用本项目；不改动 macOS 客户端代码。本站是独立二开分支的网站，非上游官方网站；二开说明与致谢见 `/about`。

## 内容来源与构建

- `../README.md`：功能范围、安装方法、权限与兼容性。
- `../updates/releases.json`：CN6 起使用新团队 462JAMGP66 签名更新通道；不使用可能遗漏预发布的 GitHub latest 下载地址。
- 主下载切换 CN6；首页、下载页、FAQ 和更新记录均说明旧用户需手动迁移一次。CN5 临时签名测试版保留在 GitHub 历史发布，不加入应用内更新清单。
- `../docs/images/`：真实刘海与剪贴板截图；界面读数仅作示例。
- `content/project-faq.json`：根据当前项目整理的 FAQ。
- `templates/`：原站公开 HTML、CSS 与 JavaScript 视觉模板。
- `scripts/sync-source.py`：取得上游模板并本地化字体、动画库、图标和演示视频，随后自动适配本项目。原站缺失图标使用轻量兜底。
- `scripts/adapt-project.py`：使用本地模板和现有项目资料生成 `dist/`，不访问网络。
- `source-manifest.json`：来源与最终静态文件 SHA256。

首次运行 `python3 scripts/sync-source.py`。之后内容调整运行 `python3 scripts/adapt-project.py`，再运行 `python3 scripts/preview.py` 预览 http://127.0.0.1:8788/ 。不新增测试用例；验证页面引用、JavaScript 语法和真实浏览器交互。

`dist/` 和发布归档属于生成产物，已忽略。核心入口为首页、`/about`、`/download`、`/faq`、`/changelog`、`/issues` 和 `/privacy`。`/subscribe` 保留为安装页面兼容入口；旧 `/portal` 与 `/checkout.html` 在公网重定向至安装页，不导向上游付费服务。

## 阿里云部署

- Workbench skill：`alibabacloud-workbench-cli`。
- ECS：`i-bp1163pp7k7o228siqnp` / `cn-hangzhou`，公网 `121.41.102.231`。
- 独立容器：`sapphire-web`，监听 `127.0.0.1:8787`。
- 站点目录：`/opt/sapphire-site/current/dist`；主机发布归档与增量包在 `/opt/sapphire-site/releases/`。
- 配置入口：现有 `agent-path-web` Caddy 容器；配置 `/opt/agent-path/release/deploy/Caddyfile`。仅追加独立 host 并热加载，不重启现有服务。
- 初次发布：`python3 scripts/deploy.py`，需新目录/容器/端口均未占用。
- 后续发布：`python3 scripts/deploy-update.py`，与远端清单比对后仅上传变化文件，先备份再逐文件原子替换，并校验所有哈希，不重启服务。
- 回退资料：`/opt/sapphire-site/backups/` 下保存 Caddy 配置和每次增量发布前的旧文件。原始完整发布包保留在 `/tmp/sapphire-20261031T163401Z.tar.gz`。

正式域名使用 `sapphire.u7u7.top`，解析至上述阿里云 ECS；权威 DNS 由 Cloudflare 托管。旧 sslip.io 临时域名迁移后重定向到正式域名。官方 GitHub 安装包仍由 GitHub 下载。未复制上游 OTP、Stripe 或其他私有业务后台；网站不显示其付费计划。
