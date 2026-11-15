# 随机静态网页审查与测试报告

版本：v2.3.0，开发分支：`feat/random-self-domain-pages`。基于 `main@4c30dbd`（v2.2.2），保留两种安装模式、中文菜单、命令、执行调度、续期、安全策略和清理归属机制。没有在生产 VPS 部署。

后续 v2.3.1 按用户要求增加显式的已有网页更换入口（菜单 27 / `website-random`），默认更新仍保留网页。以下保留 v2.3.0 的原验收记录，新功能见 [网页更换审查与测试](SITE_REPLACEMENT_REPORT.md)。

## 实现范围

- 仅自有域名新安装时生成网页。六种不同布局：个人手记、技术笔记、工作室、视觉画廊、阅读记录、行走随笔；随机组合八组配色、三组系统字体、标题、段落顺序、宽度、圆角及内联 SVG。
- 一次本地 Python 标准库进程生成完整 HTML，无新依赖、外部下载或服务。所有样式和图形内嵌，链接仅为有效页面锚点，无脚本、表单、iframe、图片、外部字体或第三方接口。
- 输出仍为原 `/var/www/vless-reality-self/index.html`，文件 644、网站目录 755；私有工作目录内暂存，非空且进程成功才通过原 `self_publish` 发布并记录 SHA-256。退出清理暂存文件，渲染或发布失败明确触发安装回滚。
- 已有归属校验通过的网页直接复用，不调用渲染器，不因更新、续期、重启、域名/地址切换或安全配置升级改变。修改过、无法确认归属或符号链接文件拒绝覆盖。
- 不增加网页模板管理菜单/命令、模板元数据、素材目录、端口、定时任务或额外访问日志。原 `security-apply` 仍是 Nginx 安全配置更新，与网页内容无关。

随机化减少完全相同的 HTML 与外观，不保证全局唯一，也不证明服务不可识别或能阻止第三方使用公开 SNI。网页中不嵌入域名、节点地址、认证资料或公开的本项目专用标记。

## 修改文件

| 文件 | 内容 |
| --- | --- |
| `install.sh` | v2.3.0；新安装一次性渲染、已有网页保护、渲染失败回滚 |
| `README.md`、本报告、`SELF_DOMAIN_SECURITY_REPORT.md` | 使用行为、兼容、性能与清理边界 |
| `tests/site_pages.bash` | 全布局/深浅配色、资源约束、锚点、权限、稳定性、旧网页/用户文件保护和创建失败 |
| `tests/self_lifecycle.bash` | 渲染与发布失败回滚；域名成功/失败变更均保留网页 |
| `tests/self_update.bash` | 旧版网页在核心升级后保持不变 |
| `tests/integration/self_tls.bash` | 实际 H2 返回文件逐字节一致；地址切换/限速/安全配置更新保持页面；实际卸载 |
| `tests/integration/acme_client.bash` | 真实签发、dry-run 和 deploy hook 后页面保持不变 |
| `tests/integration/site_browser.py` | 可选的隔离 Chromium 显示检查；非运行依赖，不在 VPS 安装浏览器 |

## 速度与清理

14 个受控布局/配色样本的首次创建（含暂存、权限与归属记录）中位数 **46.5 ms**，HTML **4,037–4,819 字节**，均低于测试上限 16 KiB。这是本地开发样本；不代表真实 VPS 整次安装时间。随机源仅在测试进程替换以覆盖布局，生产无测试参数或固定种子。

重复调用不再启动 Python，线上访问由 Nginx 直接读静态文件，无每次请求生成开销。保留 v2.2.2 的 apt 短期成功复用、双解析器并发及最多 16 个 SNI 持续探测任务；TLS/证书校验、续期 dry-run 和原超时不减。

新增内容全部位于原网页文件或原私有工作目录。卸载使用原标记、SHA-256、符号链接、未知文件和共享引用检查，确认归属后清理网页、暂存与项目证书/配置/日志/入口。不会为了“无残留”删除共享软件包、其他站点/证书、系统 journal、用户自备 Token 文件或修改过的数据；触发保护时明确提示，保留管理记录供处理。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 14 个 HTML 样本 | 通过六种布局、深浅配色、自包含资源、有效锚点、无私密字段、大小和权限约束 |
| 页面稳定与保护 | 通过重复调用不重生成、旧网页不改、手工修改/链接拒绝覆盖、失败/空输出不发布且清理暂存 |
| 隔离 Chromium | 通过 14 个样本 × 1280/390 px，共 28 次；无横向溢出、整页布局正常、导航可用、原生产 CSP 生效、无外部资源/控制台错误 |
| Bash / ShellCheck / 全部原回归 | 通过逐个 Bash 文件语法检查、install.sh ShellCheck 零诊断及全部单元/故障测试；systemd unit 在容器中验证通过 |
| Debian 12/13 真实 Nginx / Xray | 通过原 REALITY 握手、Nginx -t、Xray 配置检查、TLS 1.3 / X25519 / H2、首页内容逐字节匹配、SNI/Host 拒绝、合法与错误认证、四种 Encryption 配置、地址切换/限速/安全配置更新后页面保持 |
| Certbot / Pebble | 通过真实 HTTP-01 签发、renew dry-run、reload hook 与页面保持 |
| 故障回滚与卸载 | 通过新增渲染/发布失败及原故障回滚、用户文件保护；两代 Debian 实际停止服务并清理节点、网站、证书、Token 副本、私有日志、账号和入口，443/8443 无监听，重复卸载安全返回 |

人工查看了桌面画廊、深色页面和手机手记/行走页面。曾发现布局选择类与列表类重名导致整页变窄，已改用独立选择器并新增浏览器整页宽度与 display 断言，复测通过。

## 尚未实测

- 生产域名的 Let’s Encrypt、Cloudflare DNS-01 和长期续期：未使用用户凭据或部署生产 VPS，隔离 Pebble 不等同生产签发。
- 真实外部网络访问生产节点、长期运行和端口映射：没有连接生产 VPS。容器中的真实协议测试不能代表外部网络。
- 所有浏览器/字体、arm64、各 Ubuntu 组合：显示实测为隔离 Chromium，真实协议为 Debian 12/13 amd64；使用标准 HTML/CSS 和系统字体回退。

## 复现

基础单元与容器步骤见 [安全报告](SELF_DOMAIN_SECURITY_REPORT.md#复现)。新增页面检查无需 root 或网络：

```bash
bash tests/site_pages.bash
# 可选：只在开发机输出样本并检查显示，不是节点管理命令
bash tests/site_pages.bash --preview /tmp/vless-site-previews
# 开发机需自行准备 Python Playwright 与 /usr/bin/chromium
python3 tests/integration/site_browser.py /tmp/vless-site-previews --screenshots /tmp/vless-site-visuals
```

GitHub Actions 双 Debian 矩阵自动运行页面结构与原回归、实际 Nginx/Xray 和隔离 ACME 测试。浏览器显示检查为本地开发附加验证，不作为生产依赖。
