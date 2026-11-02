# CN9：应用内更新使用 OSS

用户要求自动更新也走阿里云 OSS。本版递增主应用 build 至 9，沿用团队 462JAMGP66 签名，不改变安装授权、归档、版本及同团队校验。

CN9 优先请求 OSS `updates/releases.json`，连接或响应失败时请求原 GitHub Raw 地址。ETag 和缓存来源绑定，不能拿另一来源缓存响应复用 304。清单中保留旧客户端使用的 GitHub `browser_download_url`，另加已核验的 `mirror_download_url`。CN6–CN8 升级 CN9 仍需通过 GitHub 一次，也可从网站手动安装；CN9 起使用 OSS 更新。

下载器仅接受专用 Bucket HTTPS 地址，并要求镜像路径与 GitHub 的发行标签和文件名完全对应、有 SHA-256。优先下载镜像，网络或 HTTP 失败最多回退 GitHub 一次。用户取消不回退，摘要或归档校验失败不静默换源。旧 session 的完成回调不能清除新下载。GitHub CDN 重定向和原校验继续保留。

发布时先公开 GitHub Release 和完整签名附件，再上传并逐文件校验 OSS 镜像，生成兼容清单，发布 OSS 与 GitHub 两份清单，最后更新网站。OSS 清单短缓存，安装包路径不可覆盖不同内容。验证 URL 白名单、旧新清单解码、镜像与原包摘要、构建、归档、真实签名和跨版本 designated requirement。
