# VLESS + REALITY + Vision 节点管理脚本

这是参照 [Soulleslie/anytls-](https://github.com/Soulleslie/anytls-) 的交互和运维思路编写的 Xray-core 管理脚本，用于在 Debian/Ubuntu VPS 上安装 **VLESS + REALITY + XTLS Vision**。

普通模式不要求自有域名或申请证书，也无需开放 TCP 80；安装时选择支持 TLS 1.3 的第三方伪装域名。自有域名模式会额外部署 Nginx 和 Let’s Encrypt 证书，将普通 HTTPS 请求回落到自己的本地网站。

## 功能

- 从 `XTLS/Xray-core` 官方 GitHub Release 获取最新稳定版
- 使用 GitHub Release 的 SHA-256 digest 校验安装包
- 支持 `amd64` 和 `arm64` 的 Debian/Ubuntu
- 安装前检测现有 Xray 文件和服务，不覆盖已有配置
- 自动生成 UUID、X25519 密钥和 Short ID
- 自动比较候选伪装域名的 TLS 1.3 握手耗时，选择可用且较快的 SNI
- 可单独查看当前 VPS 实测延迟最低的候选域名，不修改节点
- 输出标准 `vless://` 客户端导入链接
- 中文菜单管理启动、停止、重启、日志和状态
- 修改端口、SNI、UUID、REALITY 密钥和节点名称
- 可选开启 TCP Fast Open，并在菜单或命令行切换
- 可选开启 VLESS Encryption；生成成对参数并更新客户端导入链接
- 自有域名模式：Nginx 本机 HTTPS 网站、Let’s Encrypt 证书与隔离自动续期
- 升级失败、配置修改失败和首次安装失败时回滚
- 卸载时只清理本脚本拥有的文件

## 安装前准备（普通模式）

1. 使用带公网 IPv4 的 Debian 或 Ubuntu VPS，以 root 身份执行。
2. 在云服务商安全组中放行准备使用的 TCP 端口。若使用系统防火墙，也需放行该端口。
3. 选择端口时直接回车使用 TCP 443；若已占用，脚本会提示重新输入其他端口（例如 8443）。
4. 安装时伪装域名直接回车，会立即测速并显示实测延迟最低的域名，然后再提示输入节点名称；也可以手动输入一个支持 TLS 1.3 的域名。自动优选从脚本内的 68 个候选域名并发初筛，跳过证书或 TLS 1.3 验证失败的站点，再复测全部通过初筛的域名，选两次握手平均耗时最低的站点。这个耗时是 **VPS 到伪装站点** 的耗时，不是客户端到 VPS 的延迟。若候选全部不可用，请手动指定域名。
5. 选择是否开启 TCP Fast Open 和 VLESS Encryption；两者直接回车都默认关闭。开启 VLESS Encryption 后可选择 `native`、`xorpub`、`random`，直接回车默认 `native`。安装后可分别通过菜单第 17、19 项切换。

## 两种安装模式

- **普通 REALITY**：菜单 1 或原命令 `install`，第三方 SNI、任意空闲 TCP 端口、自动优选行为保持兼容，不安装 Nginx/Certbot。
- **自有域名 REALITY（偷自己）**：菜单 20 或 `install-self`。Address、SNI、证书域名相同；Xray 在 `0.0.0.0:443` 接入，REALITY target 固定为 `127.0.0.1:8443`，普通 HTTPS 请求回落到本机静态 Nginx 网站。此模式不允许修改节点端口，也不允许 `sni auto` 切到第三方域名。

自有域名的所有功能都内嵌在 `install.sh`；不需要下载额外管理模块。建议使用 Debian 12/13、Ubuntu 24.04 或更新的受支持版本，Nginx 至少 1.19.4（未知 SNI 拒绝功能），curl 必须包含 HTTP2。旧系统若仓库 Nginx 过旧会安全中止，不自动添加第三方软件源。

## 一键安装

使用下面的方式下载并运行。不要使用 `curl | bash`，因为脚本需要从终端读取安装参数，并会作为管理脚本保留在 VPS 上。

```bash
wget -O /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/main/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

尚未合并的自有域名开发分支可用以下命令验证（建议全新的测试 VPS）：

```bash
wget -O /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/feat/self-domain-reality/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

完整的本地验证与未实测项目见 [开发与测试报告](docs/SELF_DOMAIN_TEST_REPORT.md)。主分支只有在 Pull Request 审查合并后才包含新功能。

使用 curl：

```bash
curl -fL -o /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/main/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

脚本安装完成后会创建快捷命令：

```bash
vless-reality
```

如果旧版脚本在菜单选择 `1` 后直接返回主菜单，请重新执行上面的下载命令获取最新版。v1.0.1 已修正安装前检查在正常机器上错误退出的问题。

v1.0.2 进一步加强安装记录写入、配置修改回滚和 Xray 升级回滚。已下载旧版脚本的 VPS 需要重新执行下载命令，才能使用这些修复。

v1.0.3 修正已停止的节点在修改端口、SNI、UUID 或密钥后被意外启动的问题；状态页会读取实际配置中的 Vision flow。客户端导入链接也改为原子写入，修改配置后若无法保存新链接会恢复旧配置。

v1.0.4 防止“升级 Xray”误将较新的本机版本降级。项目测试还包含真实 Xray 客户端与服务端的本地 REALITY + Vision 握手验证。

v1.0.5 将可识别的中断临时文件纳入卸载清理，包括客户端链接临时文件、Xray 升级暂存程序和带有本脚本标记的临时目录。

v1.0.6 安装时直接回车固定选择 TCP 443；若端口已占用，会要求手动输入其他端口。

v1.0.7 修正卸载中途失败时安装记录过早删除的问题；若节点文件已清理但仍留下本脚本的菜单入口，可再次运行 `vless-reality uninstall` 清理入口。

v1.0.8 支持清理只剩管理脚本或只剩快捷命令的状态；配置缺失时仍可进入菜单重试卸载。首次安装失败的回滚会先确认服务停止，避免删除仍在运行的节点文件。

v1.1.0 增加伪装域名自动优选；全部候选不可用时会停止并提示手动指定域名。

v1.2.0 加入 65 个候选域名，共 68 个；自动优选改为限量并发初筛和最快 5 个复测，并清理测速中断留下的临时目录。

v1.2.1 自动优选会复测所有通过初筛的域名，并选择平均握手耗时最低的站点；安装提示明确说明直接回车与手动填写域名的选择。

v1.3.0 增加菜单“查看当前测速延迟最低的域名”和 `sni-best` 命令；显示域名与两次握手的平均耗时，不修改节点配置。

v1.3.1 修正安装提示顺序：伪装域名回车后立即显示测速选中的域名，再询问节点名称，并在确认页显示实际域名。

v1.4.0 增加 TFO 开关：同时设置 Xray 入站和内核服务端 TFO，状态页显示生效情况；关闭或卸载时恢复本脚本修改前的内核值。

v1.4.1 在切换 TFO、重启 Xray 前提示：如果 SSH 连接经过当前节点，远程会话可能中断。

v1.4.2 通过 systemd 后台任务切换 TFO；即使 SSH 因 Xray 重启而断开，任务也会继续执行并完成验证或回滚。

v1.4.3 增加可选 RealityChecker 管理入口；按架构下载官方发布包、校验 SHA-256、安装程序并记录归属，卸载节点时一并清理。

v1.4.4 补齐 RealityChecker 的单域名、空格分隔批量域名和 CSV 文件检测，并在菜单第 18 项提供三个入口。

v1.4.5 修正 RealityChecker v2.2.3 将 RealiTLScanner CSV 的 `TLS` 列误当域名的问题：按 `CERT_DOMAIN` 列名提取域名，生成临时兼容文件后再检测。

v1.5.0 增加 VLESS Encryption 开关：通过 `xray vlessenc` 生成配对参数，写入服务端配置和客户端链接；切换由 systemd 后台任务完成，失败时恢复原配置。

v1.6.0 增加 VLESS Encryption 的 `native`、`xorpub`、`random` 三种模式；安装时选择，安装后可从菜单或命令行修改。默认 `native`。

v1.6.1 开启服务端 TFO 时，在新生成的导入链接中附带客户端可选参数 `tfo=1`；切换 TFO 后刷新链接。

v1.6.2 移除菜单第 18 项 RealityChecker、安装提示和检测命令；其他菜单编号保持不变。卸载节点仍会清理旧版本由本脚本安装的 RealityChecker 及可识别暂存文件。

v2.0.0 新增自有域名安装、隔离 Certbot 自动续期、本地 Nginx HTTPS、检测与同步域名管理；保留普通模式及旧命令。

## 非交互安装

参数顺序为端口、伪装域名、节点名称：

```bash
/root/vless-reality-setup.sh install 443 www.amazon.com Reality-SG
```

需要自动优选 SNI 时，将第二个参数改为 `auto`：

```bash
/root/vless-reality-setup.sh install 443 auto Reality-SG
```

末尾可加 `on`，用于在安装时开启 TFO；省略时默认关闭：

```bash
/root/vless-reality-setup.sh install 443 auto Reality-SG on
```

第五个参数可指定 VLESS Encryption，省略时默认关闭；第六个参数指定模式，省略时默认 `native`。以下示例关闭 TFO、开启 `xorpub` 模式的 VLESS Encryption：

```bash
/root/vless-reality-setup.sh install 443 auto Reality-SG off on xorpub
```

## 自有域名首次安装

先准备一个自己控制的域名，例如 `node.example.com`，将 **A 记录唯一指向 VPS 当前公网 IPv4**。不要配置 CNAME，不要开启任何 CDN；Cloudflare 必须为 **DNS only（灰云）**。本实现仅提供 IPv4 入口，因此域名下的 AAAA 必须删除。脚本分别询问 Cloudflare 和 Google 公共解析器，遇到不一致、无记录、错误地址、CNAME、AAAA 或解析错误时停止，不会替你修改 A/AAAA。

通过 VPS 直连 SSH 运行上方一键命令，选择菜单 **20**，依次输入域名、验证方式、通知邮箱、节点名称和可选开关。公网 TCP 443 必须空闲，本机 TCP 8443 也必须空闲；脚本不修改防火墙、SSH 规则和云安全组。

### Cloudflare DNS-01（推荐）

选择 `cloudflare`。域名的权威 DNS 必须由 Cloudflare 托管。为该 Zone 创建专用 API Token，按插件要求赋予 **Zone:DNS:Edit 和 Zone:Zone:Read**，将资源范围限制为该 Zone；不要使用 Global API Key。Token 会隐藏输入并保存到 root 专用的 `/etc/vless-reality-self/cloudflare.ini`，权限 600。Certbot 插件仅临时添加/清理 ACME TXT 记录，不开启 CDN，不修改 A 记录。无需开放公网 80。

非交互示例（不要把 Token 写进命令行或 shell history）：

```bash
# 先用编辑器创建 /root/cloudflare.ini：
# dns_cloudflare_api_token = <你的受限 Token>
chmod 600 /root/cloudflare.ini
VLESS_CF_CREDENTIALS=/root/cloudflare.ini /root/vless-reality-setup.sh install-self node.example.com cloudflare admin@example.com Reality-Self off off
```

脚本复制凭据而不删除用户提供的源文件；源文件由用户自己管理。不要把它上传到仓库。

### HTTP-01

不由 Cloudflare 托管的域名可选择 `http`：

```bash
/root/vless-reality-setup.sh install-self node.example.com http admin@example.com Reality-Self off off
```

需自行放行公网 **TCP 80 和 443**。80 被占用会中止，以免破坏现有 Web 服务。Nginx 长期保留专用的 `/.well-known/acme-challenge/` 入口，以便后续续期；其余 HTTP 路径返回 404，不生成 HTTPS 跳转。申请前会回访公网 IP 对应的挑战路径，之后由 ACME CA 进行真正的外部 HTTP-01 验证。其他 DNS 提供商的 DNS-01 需要对应插件，本脚本不会假设 Cloudflare Token 能管理其他提供商。

非交互安装视为接受 Let’s Encrypt 服务条款。参数在名称之后依次是 `TFO:on|off`、`VLESS加密:on|off`、`native|xorpub|random`；加密关闭时省略最后一个模式参数。

### 端口、网站和现有 Nginx

- Xray：公网 IPv4 TCP 443，非 root 的 `xray` 用户运行。
- 项目 HTTPS 网站：Nginx **只绑定 `127.0.0.1:8443`**，仅 TLS 1.3，支持 X25519 和 ALPN h2，首页 HTTP/2 200，不跳转。
- Nginx 的拒绝握手默认站点会阻止未知或缺少 SNI 的 TLS 请求；静态站点不提供任意目标的反向代理。
- 可与已运行且无端口冲突的标准 Debian/Ubuntu Nginx 共存，只添加专属 `conf.d/vless-reality-self.conf`。不改主配置或已有站点。已有 Nginx 若启用了其他站点但处于停止状态，会拒绝自动启动，避免意外开放那些入口。非标准主配置未 include `conf.d/*.conf` 时停止。
- 本次全新安装 Nginx 时，暂时抑制包安装自动启动，并记录/暂存软件包默认站点入口；卸载恢复入口。系统软件包不删除，以免影响后续使用它的软件。

### 证书续期与告警

所有项目证书、账户、续期配置、工作文件和私有日志位于 `/etc/vless-reality-self/`，与 `/etc/letsencrypt` 隔离。专用 `vless-reality-cert.timer` 每日两次带随机延迟地执行 Certbot renew；共享 `certbot.timer` 不会被修改，也不会重复续期本项目的独立目录。

成功续期执行 `nginx -t && systemctl reload nginx`；不重启 Xray，不停止 TCP 443。首次安装必须通过 `certbot renew --dry-run` 和独立执行的 deploy hook 检查，才会显示自动续期成功。每次自动续期和测试的结果/时间均可查询；不足 14 天或失败会写入 systemd 日志并触发告警服务。Certbot 原始输出存入 root 私有日志，Cloudflare Token 会被日志脱敏处理。

```bash
vless-reality cert status
vless-reality cert renew-test
journalctl -u vless-reality-cert -u vless-reality-cert-alert --no-pager
systemctl list-timers vless-reality-cert.timer
```

可自行创建 `/etc/vless-reality-cert-alert`（root 所有、权限 700、普通可执行文件）对接自己的通知系统，脚本会以域名作为唯一参数调用它。该扩展是用户自行管理的文件，项目不会删除它。**证书自动续期不等于域名注册自动续费**。

### 自有域名管理与检测

```bash
vless-reality show                 # 域名 Address + 域名 SNI 的受保护链接
vless-reality website              # 本地网站状态
vless-reality check-self           # 完整检查
vless-reality sni new.example.com  # 同步修改 DNS 检查、证书、Nginx、Xray 和链接
vless-reality refresh-ip           # 只核对当前 DNS，绝不把 Address 改成 IP
```

域名修改由独立 systemd 任务执行，失败恢复旧站点、配置、证书引用、安装记录、链接和续期测试记录。旧证书保留在专用目录便于回滚，卸载时一起清理。失败日志为 `journalctl -u vless-reality-self-change`。更换域名后重新导入链接。

`check-self` 区分通过、失败、警告和未验证。它实际检测 DNS、本地 TLS/证书/X25519/H2、HTTP/2 200、错误 SNI 拒绝、443 HTTPS 回落、正确 target/Vision、续期任务和实际 Xray 客户端代理 HTTPS 请求（测试目的站为 Debian 官网）。公网 IP 回访和节点客户端请求的检测源均为 VPS 本机，**不等于外部网络验证**。如果公网 IP 不支持回环访问，该项会失败；应检查 VPS 的 NAT/回环路由，不能伪装通过。

从其他网络访问 `https://node.example.com` 并导入节点测试。还可设置 `VLESS_EXTERNAL_CHECK=/root/external-check`（root:700 普通可执行程序），由自己的外部验证工具完成 HTTPS 和 VLESS 两项检查，程序收到域名/IP 参数，成功返回 0。未配置时会明确显示“外部网络未验证”。本项目不会把完整节点链接传给未知在线检测服务。

### 回滚与卸载边界

安装前拒绝已有 Xray、项目目录和端口冲突。失败回滚、正常卸载均涵盖本项目的 Nginx 站点、静态网站、专用证书/账户、Token 副本、专用 timer/service/deploy hook、工作目录、私有日志及节点文件。文件清单通过 SHA-256 校验归属；站点被修改、网站目录有额外文件、管理目录出现符号链接或常见其他 Web 配置引用本项目资源时，会停止删除并报告，便于管理员先解除共享/恢复文件再重试。

不删除其他站点、`/etc/letsencrypt` 里的证书、共享 Certbot timer、用户提供的凭据源文件、外部告警脚本、系统软件包、系统 journal、DNS 或防火墙规则。用户中途新增到保留目录的内容需自行确认，不会为了“零残留”递归删除未知数据。卸载可重试，包括节点已删除但自有域名目录尚未清理的情况。

### 安全说明

启用注册商 MFA、Registrar Lock、域名自动续费和 DNS 修改提醒；按 DNS 提供商/注册商支持情况启用 DNSSEC。保护 DNS Token，限制 Zone 和权限，泄漏后立即撤销。

公开域名无法阻止第三方把它填写为他们自己的 REALITY SNI。VLESS 访问由 UUID、REALITY 参数及可选加密参数控制；本站回落只提供静态文件，不提供开放代理。不要公开节点链接或 REALITY 私钥。

已调查 Xray 官方的 `limitFallbackUpload/Download`：官方指出回落限速会增加特征，不建议一键脚本统一设置。因此默认不添加未经需要的限速指纹，使用本机静态网站、SNI 拒绝、请求体/超时约束减少回落滥用。遇到实际流量攻击应在了解影响后配置主机/上游防护。

官方参考：[Xray REALITY](https://xtls.github.io/config/transports/reality.html)、[Nginx HTTPS](https://nginx.org/en/docs/http/configuring_https_servers.html)、[Nginx HTTP/2](https://nginx.org/en/docs/http/ngx_http_v2_module.html)、[Certbot 续期](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)、[Cloudflare DNS 插件](https://certbot-dns-cloudflare.readthedocs.io/en/stable/)。

## 常用命令

```text
vless-reality show                 显示 vless:// 导入链接
vless-reality status               检查服务、配置、端口和伪装站点
vless-reality port 8443            修改监听端口
vless-reality sni www.apple.com    修改 REALITY 伪装域名
vless-reality sni auto             重新测量并优选伪装域名
vless-reality sni-best             显示当前测速延迟最低的域名，不修改节点
vless-reality tfo                  显示状态，交互式切换 TFO
vless-reality tfo on               开启 TFO
vless-reality tfo off              关闭 TFO
vless-reality vlessenc             查看状态，交互式切换 VLESS Encryption
vless-reality vlessenc on          开启 VLESS Encryption
vless-reality vlessenc on xorpub   切换至 xorpub 模式（random 同理）
vless-reality vlessenc off         关闭 VLESS Encryption
vless-reality uuid                 重新生成 UUID
vless-reality rotate-keys          轮换 REALITY 密钥和 Short ID
vless-reality rename Reality-US    修改节点名称
vless-reality refresh-ip           刷新链接中的公网 IPv4
vless-reality update               升级 Xray-core
vless-reality log -f               实时查看日志
vless-reality uninstall            卸载并清理
```

安装前也可以运行 `/root/vless-reality-setup.sh sni-best` 查看测速结果；该命令只显示候选域名，不会安装或修改节点。

## TCP Fast Open

TFO 默认关闭。开启时，脚本设置 Xray 入站的 `sockopt.tcpFastOpen`，并开启内核参数 `net.ipv4.tcp_fastopen` 的服务端位。内核设置写入 `/etc/sysctl.d/99-vless-reality-tfo.conf`，重启后仍生效。关闭或卸载时，只清理带有本脚本标记的设置文件，并尽可能恢复修改前的内核值；若内核值后来被其他程序改动，脚本会保留当前值并提示。

TFO 只影响新建 TCP 连接。服务端开启 TFO 时，新生成的 `vless://` 链接会附带 `tfo=1`，关闭时不附带。该参数是部分客户端识别的扩展参数，不在通用 VLESS 分享链接字段中；导入后请检查客户端是否真的开启 TFO，不识别的客户端需手动开启。部分网络对 TFO 的兼容性较差，因此默认关闭。

切换 TFO 会重启 Xray。如果 SSH 连接经过这个 VLESS 节点，重启可能切断当前 SSH 会话；建议通过 VPS 的直连 SSH 操作。切换由 systemd 后台任务完成，断线后任务仍会继续。重连后运行 `vless-reality status` 核对结果；失败详情可用 `journalctl -u vless-reality-tfo -n 30 --no-pager` 查看。

## VLESS Encryption

默认关闭，客户端 `encryption=none` 与服务端 `decryption=none` 对应；REALITY 仍会加密客户端到 VPS 的传输。开启时脚本调用 Xray 官方 `xray vlessenc`，选用较短的 X25519 认证参数对（混合密钥交换仍包含 ML-KEM），将服务端 `decryption` 写入 Xray 配置，并把配套的客户端 `encryption` 记录在节点安装记录和新 `vless://` 链接中。REALITY、Vision 和 TFO 设置不变。

三种模式只改变 VLESS Encryption 握手数据的外观，必须在客户端和服务端保持一致：

| 模式 | 区别 |
| --- | --- |
| `native`（默认） | 使用原始格式；适合当前外层已有 REALITY 的节点。 |
| `xorpub` | 在原始格式上隐藏公钥部分。 |
| `random` | 隐藏记录头，流量外观看起来更像随机数据。 |

安装后运行菜单第 19 项可输入新模式，也可执行 `vless-reality vlessenc on random` 等命令切换。仅运行 `vless-reality vlessenc on` 时，已开启的节点保持原模式，未开启的节点使用 `native`。

开启或关闭后旧客户端链接会失效，运行 `vless-reality show` 获取新链接并重新导入；客户端必须支持 VLESS Encryption。建议使用 VPS 直连 SSH 或服务商控制台操作；切换会重启 Xray，若 SSH 经过此节点，可能断线。后台任务会继续执行并验证或回滚。重连后用 `vless-reality status` 查看结果，失败日志见 `journalctl -u vless-reality-enc -n 30 --no-pager`。卸载节点时会清理这些参数和链接。

卸载会先停止并禁用本脚本创建的 Xray 服务，然后恢复本脚本设置的 TFO 内核参数，删除 Xray 程序、由本脚本安装的 RealityChecker、配置、安装记录、节点链接、管理脚本、快捷命令、配置备份和可识别的中断临时文件，最后核验服务与专用账号是否仍存在。任一步失败会报错，并尽可能保留安装记录，便于修正问题后重试。

若 `/usr/local/etc/xray` 中有后来新增的其他文件，脚本会保留这些文件及所在目录并提示，不会递归删除。基础工具（如 `curl`、`jq`）、systemd 日志、云安全组规则、系统防火墙规则和客户端中的节点不会删除；这些并非本脚本独占的文件或设置。

导入链接同时保存在 `/root/vless-reality-link.txt`，其中包含 UUID，请不要发布到 GitHub、聊天或截图中。

## 客户端要求

客户端需要支持 VLESS、REALITY、`xtls-rprx-vision` 和 uTLS 指纹。导入后应确认这些关键参数：

```text
network: tcp
security: reality
flow: xtls-rprx-vision
fingerprint: chrome
SNI: 安装时选择的伪装域名
public key / short id: 使用脚本输出值
```

## 文件位置

```text
/usr/local/bin/xray                     Xray-core
/usr/local/etc/xray/config.json         服务端配置
/etc/systemd/system/xray.service        systemd 服务
/root/vless-reality-setup.sh            管理脚本
/usr/local/bin/vless-reality            快捷命令
/root/vless-reality-link.txt            客户端导入链接
```

本脚本不会自动修改 UFW、iptables、云安全组或 DNS。
