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
- 两种模式均可切换客户端连接地址为 IP / 自己的域名，保留 SNI 和认证参数，无需重启服务
- 可选开启 TCP Fast Open，并在菜单或命令行切换
- 可选开启 VLESS Encryption；生成成对参数并更新客户端导入链接
- 自有域名模式：Nginx 本机 HTTPS 网站、Let’s Encrypt 证书与隔离自动续期
- 自有域名安全检查：SNI/Host 严格匹配、实际认证拒绝测试、DNS 变化与 CAA 检查
- 自有域名可选回落限速：默认关闭，开启前核实当前 Xray 是否识别官方参数
- 升级失败、配置修改失败和首次安装失败时回滚
- 卸载时只清理本脚本拥有的文件

## 安装前准备（普通模式）

1. 使用带公网 IPv4 的 Debian 或 Ubuntu VPS，以 root 身份执行。
2. 在云服务商安全组中放行准备使用的 TCP 端口。若使用系统防火墙，也需放行该端口。
3. 选择端口时直接回车使用 TCP 443；若已占用，脚本会提示重新输入其他端口（例如 8443）。
4. 安装时伪装域名直接回车，会立即测速并显示实测延迟最低的域名，然后再提示输入节点名称；也可以手动输入一个支持 TLS 1.3 的域名。自动优选从脚本内的 68 个候选域名并发初筛，跳过证书或 TLS 1.3 验证失败的站点，再复测全部通过初筛的域名，选两次握手平均耗时最低的站点。这个耗时是 **VPS 到伪装站点** 的耗时，不是客户端到 VPS 的延迟。若候选全部不可用，请手动指定域名。
5. 选择是否开启 TCP Fast Open 和 VLESS Encryption；两者直接回车都默认关闭。开启 VLESS Encryption 后可选择 `native`、`xorpub`、`random`，直接回车默认 `native`。安装后可分别通过菜单第 16、17 项切换。

## 两种安装模式

- **普通 REALITY**：菜单 1 或原命令 `install`，第三方 SNI、任意空闲 TCP 端口、自动优选行为保持兼容，不安装 Nginx/Certbot。
- **自有域名 REALITY（偷自己）**：菜单 2 或 `install-self`。默认 Address、SNI、证书域名相同；可在安装后将客户端 Address 切换为 VPS 公网 IP，SNI 和证书域名仍匹配。Xray 在 `0.0.0.0:443` 接入，REALITY target 固定为 `127.0.0.1:8443`，普通 HTTPS 请求回落到本机静态 Nginx 网站。此模式不允许修改节点端口，也不允许 `sni auto` 切到第三方域名。

自有域名的所有功能都内嵌在 `install.sh`；不需要下载额外管理模块。建议使用 Debian 12/13、Ubuntu 24.04 或更新的受支持版本，Nginx 至少 1.19.4（未知 SNI 拒绝功能），curl 必须包含 HTTP2。旧系统若仓库 Nginx 过旧会安全中止，不自动添加第三方软件源。

## 一键安装

使用下面的方式下载并运行。不要使用 `curl | bash`，因为脚本需要从终端读取安装参数，并会作为管理脚本保留在 VPS 上。

```bash
wget -O /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/main/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

需要对比开发分支时，可用以下命令验证（建议全新的测试 VPS）：

```bash
wget -O /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/feat/self-domain-security/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

部署和加固在同一个脚本中，无需另外安装防护程序。日常安装和更新使用上面的 `main` 地址。完整验证与未实测项目见 [安全审查与测试报告](docs/SELF_DOMAIN_SECURITY_REPORT.md) 和 [基础部署测试报告](docs/SELF_DOMAIN_TEST_REPORT.md)。

使用 curl：

```bash
curl -fL -o /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/main/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

脚本安装完成后会创建快捷命令：

```bash
vless-reality
```

## 已有节点如何更新

GitHub 更新不会自动修改 VPS 上已运行的节点。原来通过本项目旧命令安装的普通节点可继续使用，无需卸载或重新导入链接。要获得新版菜单和管理功能，以 root 身份更新管理脚本即可：

```bash
(
    set -e
    vless_update_file="$(mktemp /root/.vless-reality-setup.XXXXXX)"
    trap 'rm -f -- "$vless_update_file"' EXIT
    curl -fL --connect-timeout 10 --max-time 60 -o "$vless_update_file" https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/main/install.sh
    bash -n "$vless_update_file"
    chmod 700 "$vless_update_file"
    mv -f -- "$vless_update_file" /root/vless-reality-setup.sh
    /root/vless-reality-setup.sh status
)
```

先下载并检查语法，再原子替换；下载失败时保留旧管理脚本，临时文件在退出时清理。此操作只替换管理脚本并查询状态，不重启 Xray，不修改 UUID、REALITY 密钥、端口、SNI、TFO、Encryption 或现有链接，也不会自动安装 Nginx/Certbot。

如需升级 Xray 核心，另行执行 `vless-reality update`；核心升级会按原流程验证和重启，应使用直连 SSH。已有 v2.0 自有域名节点更新脚本后，继续执行下方的 `security-apply` 和 `security-check`。

普通模式不会在更新脚本时自动变成自有域名模式。只有决定切换时，先准备 DNS、保存需要的节点信息，再卸载原节点并选择菜单 2 重新部署；新安装会生成新的认证参数，需要重新导入链接。已有节点会阻止直接覆盖安装。

v2.1.1 起，交互菜单按安装、节点管理、高级功能、自有域名管理、其他分组，编号连续为 **1–26**，`00` 退出；卸载位于第 **26** 项。RealityChecker 仍已移除，新第 18 项为网站状态。`install-self`、`show`、`uninstall` 等命名命令保持兼容。历史的命令行数字参数沿用旧映射并显示提示，因此不要用它们代替新交互菜单编号；自动化请使用命名命令。

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

v2.1.0 增加严格的 SNI/Host/:authority 过滤、REALITY 安全约束、实际负向认证测试、可选随机回落限速、DNS 基线/CAA 检查和旧站点安全模板升级。密钥及认证资料不通过外部进程参数传递；保留所有旧菜单编号，第 18 项仍不恢复。

v2.1.1 将交互菜单重排为连续的 1–26，修复 20 插入 1/2 之间及跳号的问题，同步选择分派、输入提示、卸载后的退出逻辑和文档；命名命令与历史数字命令行参数语义保持兼容。

v2.1.2 修正 NAT VPS 公网地址回访的判定：仅对确认 NAT 且尚未建立 TCP 的超时/拒绝保留“公网待验证”部署，退出码 3，其他实际失败仍回滚。菜单/状态显示待验证记录，记录随卸载清理；菜单清屏保留滚动历史，回滚不再打印预期的 Xray unit 不存在提示。

v2.2.0 将菜单第 12 项扩展为“服务器地址管理”，提供 IP、域名和保持当前选择的公网 IP 刷新；新增 `addr` 命令，旧 `refresh-ip` 和历史数字命令仍兼容。两种安装模式均可使用，地址选择单独保存，修改 UUID、密钥、加密模式或升级 Xray 后继续保留。地址保存失败回滚，新增暂存文件纳入卸载清理。验证范围见 [地址切换测试报告](docs/ADDRESS_TEST_REPORT.md)。

v2.2.1 增加自有域名交互输入的格式/DNS 检查和完整域名二次确认，失败可重新输入；部署前再次检查，未通过时不读取 Token、不安装 Nginx/Certbot、不创建项目文件。显式命令参数保持无人值守，但同样必须预检。DNS 错误显示解析器、域名、记录类型和 NXDOMAIN/SERVFAIL 等状态；回滚不再打印尚未创建的证书 timer 查询提示，真实清理失败仍报错。

v2.2.2 优化内部执行速度：同一次执行链复用已成功刷新的 apt 索引，两个 DNS 解析器并发检查，SNI 优选在 16 个名额内持续补充探测任务。保留原有菜单、命令、默认值、68 个候选、全部有效候选复测、超时、证书续期验证及回滚/卸载。旧 Bash 保留原批次调度。测量范围与复现见 [性能与兼容性报告](docs/PERFORMANCE_REPORT.md)。

## 执行速度优化

v2.2.2 的优化只调整内部调度。普通模式、自有域名、IP/域名切换、TFO、VLESS Encryption、证书续期和安全检查的功能保持不变：

- 需要分阶段安装依赖时，当前执行链已成功运行的 `apt-get update` 可复用；失败不缓存，下次需要安装依赖的新执行链仍会刷新。不创建长期索引缓存或跳过软件包安装。
- 两个公共 DNS 解析器同时检查，各自仍核对 A、AAAA、CNAME 和公网 IP；每次重新查询，不缓存 DNS/IP 结果，失败标准与诊断优先级保持一致。
- SNI 初筛/复测不再整批等待慢站点，完成任务后补充下一个，并发仍最多 16；68 个候选和两次有效握手的平均耗时排序规则不变。Bash 5.1 以前沿用原批次等待。

TLS/证书校验、官方 SHA-256、实际 VLESS 握手、`renew --dry-run`、Cloudflare DNS 传播等待及原超时均保留。固定延迟替身对照中，DNS 和 SNI 调度耗时约降低 49% 和 63%；这不是整次安装速度承诺，实际仍受软件源、下载、DNS、站点和证书机构响应影响。

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

通过 VPS 直连 SSH 运行上方一键命令，选择菜单 **2**。先输入完整域名，例如 `node.example.com`，不带 `https://`、端口、路径或空格。格式或 DNS 检查失败时可重新输入，输入 `0` 返回；通过后显示完整域名，要求再次输入确认，两次一致才继续询问验证方式、通知邮箱、节点名称和可选开关。公网 TCP 443 必须空闲，本机 TCP 8443 也必须空闲；脚本不修改防火墙、SSH 规则和云安全组。

域名预检前仅可能安装基础工具和 `dnsutils`；预检通过前不读取/保存 Cloudflare Token，不安装 Nginx/Certbot，不创建本项目的配置、网站或证书目录。正式部署前再次校验，非交互 `install-self` 同样执行，失败直接退出；显式命令参数不额外弹出二次输入。依赖安装后继续复核 DNS，期间解析改变或验证失败仍回滚。

错误提示区分 `NXDOMAIN`（域名/子域名不存在）、`SERVFAIL`（检查 NS/DNSSEC/服务状态）、`REFUSED`、查询未完成，以及实际 A 与期望公网 IP 不一致。它们不能单凭一条日志判断为 Token 错误。若输错的另一个有效域名也指向本机，DNS 无法判断用户原意，仍需认真核对两次输入的完整域名。旧版失败安装遗留的系统 Nginx 默认站点仍需人工确认，脚本不会自动删除或启动已有站点。

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
- Nginx 默认站点拒绝未知或缺少 SNI 的 TLS 握手。正确 SNI 的 HTTP Host / HTTP/2 :authority 还须匹配本域名（允许大小写差异及 `:443`、本地检测用 `:8443`）；不匹配返回 421。静态站仅提供 GET/HEAD，不提供任意目标转发。
- 可与已运行且无端口冲突的标准 Debian/Ubuntu Nginx 共存，只添加专属 `conf.d/vless-reality-self.conf`。不改主配置或已有站点。已有 Nginx 若启用了其他站点但处于停止状态，会拒绝自动启动，避免意外开放那些入口。非标准主配置未 include `conf.d/*.conf` 时停止。
- 本次全新安装 Nginx 时，暂时抑制包安装自动启动，并记录/暂存软件包默认站点入口；卸载恢复入口。系统软件包不删除，以免影响后续使用它的软件。

### 证书续期与告警

所有项目证书、账户、续期配置、工作文件和私有日志位于 `/etc/vless-reality-self/`，与 `/etc/letsencrypt` 隔离。专用 `vless-reality-cert.timer` 每日两次带随机延迟地执行 Certbot renew；共享 `certbot.timer` 不会被修改，也不会重复续期本项目的独立目录。

成功续期执行 `nginx -t && systemctl reload nginx`；不重启 Xray，不停止 TCP 443。首次安装必须通过 `certbot renew --dry-run` 和独立执行的 deploy hook 检查，才会显示自动续期成功。每次自动续期和测试的结果/时间均可查询；不足 14 天或失败会写入 systemd 日志并触发告警服务。原有续期任务还会核对 DNS 直连及已确认基线；DNS 变化会告警，但仍尝试续期，不改 DNS、不封禁访问。Certbot 原始输出存入 root 私有日志，Cloudflare Token 会被日志脱敏处理。

```bash
vless-reality cert status
vless-reality cert renew-test
journalctl -u vless-reality-cert -u vless-reality-cert-alert --no-pager
systemctl list-timers vless-reality-cert.timer
```

可自行创建 `/etc/vless-reality-cert-alert`（root 所有、权限 700、普通可执行文件）对接自己的通知系统，脚本会以域名作为唯一参数调用它。该扩展是用户自行管理的文件，项目不会删除它。**证书自动续期不等于域名注册自动续费**。

### 自有域名管理与检测

```bash
vless-reality show                 # 按当前 IP/域名选择生成受保护链接
vless-reality website              # 本地网站状态
vless-reality check-self           # 完整检查
vless-reality security-check       # 安全配置、认证拒绝、DNS/CAA、权限和带宽样本
vless-reality security-apply       # 旧版自有域名站点应用当前安全模板，支持失败回滚
vless-reality sni new.example.com  # 同步修改 DNS 检查、证书、Nginx、Xray 和链接
vless-reality refresh-ip           # 刷新公网 IP 缓存，保持当前 IP/域名选择
```

菜单 14 修改自有域名时同样先检查 DNS、再次输入完整域名确认。显式 `sni 新域名` 保持无人值守，在前台预检失败时保留原节点，不启动修改任务；后台实际应用前仍会复核 DNS。域名修改由独立 systemd 任务执行，失败恢复旧站点、配置、证书引用、安装记录、链接和续期测试记录。旧证书保留在专用目录便于回滚，卸载时一起清理。失败日志为 `journalctl -u vless-reality-self-change`。更换域名后重新导入链接。

`check-self` 区分通过、失败、警告和未验证。它实际检测 DNS、本地 TLS/证书/X25519/H2、HTTP/2 200、错误 SNI 拒绝、SNI/Host 一致性、本机 443 和公网地址 443 的 HTTPS 回落、正确 target/Vision、续期任务和实际 Xray 客户端代理 HTTPS 请求（测试目的站为 Debian 官网）。公网 IP 回访和节点客户端请求的检测源均为 VPS 本机，**不等于外部网络验证**。

从其他网络访问 `https://node.example.com` 并导入节点测试。还可设置 `VLESS_EXTERNAL_CHECK=/root/external-check`（root:700 普通可执行程序），由自己的外部验证工具完成 HTTPS 和 VLESS 两项检查，程序收到域名/IP 参数，成功返回 0。未配置时会明确显示“外部网络未验证”。本项目不会把完整节点链接传给未知在线检测服务。

### NAT VPS：公网地址回访超时

有些 VPS 的网卡只有私网 IPv4，公网地址通过服务商 NAT 映射。外部能访问公网 443，不代表 VPS 自己也能经 NAT 回访该地址；回访失败也不能证明外部一定能访问。

v2.1.2 只在以下条件下把本机公网回访记为**未验证**：公网 IP 不在本机地址中，路由经网关，源地址是本机配置的 RFC1918/CGNAT 私网地址，而且 curl 的 TCP 连接尚未建立便超时/被拒绝。证书、TLS、HTTP/2、HTTP 状态等错误仍记为失败；无法确认 NAT 时保持原来的失败处理。

安装时，本地监听、443/8443 HTTPS、证书、认证、DNS 和续期检查全部通过，且只有上述 NAT 回访未验证，脚本会保留服务、证书和私有节点链接，明确显示**本地部署已保留，公网可用性待验证**，返回退出码 **3**。这不等于完整验证成功，也不证明公网端口已正确映射。其他实际失败，包括外部验证程序失败，仍自动回滚。

遇到待验证状态时：

1. 不重复安装；先确认服务商的公网 TCP 443 映射/安全组。
2. 从其他网络直连 `https://自己的域名`，避免通过这台 VPS 的代理再绕回自己的域名。
3. 导入已生成的链接，使用支持 REALITY/Vision 的客户端访问外部网站，实际验证节点。
4. 可配置自己的 `VLESS_EXTERNAL_CHECK` 再运行 `check-self`。该程序必须实际验证外部 HTTPS 和 VLESS；成功后记录外部程序验证通过。未配置时，脚本不会把人工测试或本机回访当成已自动完成的外部验证。

`status` 和主菜单显示最近的待验证状态；结果保存在 root:600 的 `/etc/vless-reality-self/network-check.json`，不含 UUID、私钥或节点链接，卸载时一并清理。更换域名后需重新检查，旧域名的记录不会被当作新域名的验证结果。独立 `check-self` 在无其他失败、但上述 NAT 公网回访仍待验证时同样返回 3；0 表示本次检查没有失败/上述待验证条件，不能据此把未执行的外部测试算作通过。

HTTP-01 仍需满足 TCP 80 入口检查和真正的 ACME 签发/续期验证；NAT 识别不会绕过证书申请或续期检查。

### 安全检查与旧版本升级

已有普通节点更新管理脚本后仍使用原来的命令。已有 v2.0 自有域名节点，按“已有节点如何更新”替换管理脚本后执行：

```bash
vless-reality security-apply
vless-reality security-check
```

`security-apply` 仅更新本项目拥有的 Nginx 站点，验证 TLS、SNI 和 Host 过滤后才提交，不改变 UUID、密钥或证书。站点已被手工修改或共享时停止，避免覆盖用户配置；回滚失败保留备份并报错。更新 Xray 的 `update` 命令只更新核心，不能代替更新管理脚本或站点模板。

`security-check` 检查实际进程 UID、443 套接字归属、8443 绑定、配置/链接权限、密钥配对、DNS、证书和续期状态。先确认合法节点实际请求成功，再尝试错误 UUID、Short ID、公钥；测试准备失败标为未验证，不将网络故障当作安全通过。不输出私钥或完整节点链接。节点状态/安全结果保存在 root 专用目录。

首次安装保存两个解析器一致的 A/AAAA/CNAME、最近的权威 NS 和有效 CAA 基线，忽略 TTL。变化只说明需要核对，不能断言账户被盗。确认是自己修改后可执行 `vless-reality security-check --accept-dns` 接受新基线；这不会修改 DNS。CAA 会按父域继承查询：禁止 LE 的 issue 记录报错，无限制或附带验证方式/账户约束时提示核查；不会自动添加记录。若只签发 LE，可由用户按域名整体需求配置 `CAA 0 issue "letsencrypt.org"`，不要影响其他服务所需的 CA。

连接数和全机 1 秒带宽样本仅用于排查，可能包含其他进程/重复统计的虚拟接口，不是攻击判断。默认提示阈值为 1000 条连接、100 MiB/s，可通过 `VLESS_WARN_CONNECTIONS`、`VLESS_WARN_MIBPS` 调整；不会自动封禁。

### 可选回落限速

```bash
vless-reality fallback-limit status
vless-reality fallback-limit on
vless-reality fallback-limit off
```

默认关闭。开启会提示可识别的流量特征，并通过当前 Xray 的 typed 配置转换确认 `limitFallbackUpload` / `limitFallbackDownload` 确实被识别；仅 JSON 配置检查通过不足以证明支持。不支持时拒绝应用，核心升级也会重新确认支持。

每次从关闭改为开启时，上传/下载方向分别随机选择 8–16 MiB 的起限阈值、约 0.5–2 MiB/s 的每连接速率和 1–2 倍速率的 burst。普通 HTTPS 属于回落流量，超过阈值会变慢；认证成功的 VLESS Vision 连接不属于限速对象。**这不是全机总带宽限制，也不能抵御多连接或链路级 DDoS**。切换需要重启 Xray，后台临时任务会在 SSH 断开后继续验证正常 HTTPS 和合法节点，失败回滚；没有新增常驻防护服务或端口。

Nginx 保留请求体、超时、持久连接次数等温和约束。`xver=0` 下 Nginx 看到的回落源均为本机回环，按源 IP 限制请求会把所有浏览器共用一个额度，所以不默认设置此类限流，也不信任客户端伪造的 X-Forwarded-For。

### 回滚与卸载边界

安装前拒绝已有 Xray、项目目录和端口冲突。失败回滚、正常卸载均涵盖本项目的 Nginx 站点、静态网站、专用证书/账户、Token 副本、专用 timer/service/deploy hook、工作目录、私有日志、安全/DNS 记录、检测客户端、配置备份和私密参数暂存文件，以及 Xray、专用账号、链接、管理脚本和快捷命令；同时清除项目 unit 的 systemd 失败状态。文件清单通过 SHA-256 校验归属；站点被修改、网站目录有额外文件、管理目录出现符号链接或常见其他 Web 配置引用本项目资源时，会停止删除并报告，便于管理员先解除共享/恢复文件再重试。

不删除其他站点、`/etc/letsencrypt` 里的证书、共享 Certbot timer、用户提供的凭据源文件、外部告警脚本、系统软件包、系统 journal、DNS 或防火墙规则。用户中途新增到保留目录的内容需自行确认，不会为了“零残留”递归删除未知数据。卸载可重试，包括节点已删除但自有域名目录尚未清理的情况。

### 安全说明

启用注册商 MFA、Registrar Lock、域名自动续费和 DNS 修改提醒；按 DNS 提供商/注册商支持情况启用 DNSSEC。保护 DNS Token，限制 Zone 和权限，泄漏后立即撤销。

公开域名无法阻止第三方把它填写为他们自己的 REALITY SNI。VLESS 访问由 UUID、REALITY 参数及可选加密参数控制；本站回落只提供静态文件，不提供开放代理。不要公开节点链接或 REALITY 私钥。

UUID 必须有效且非全零，Short ID 使用安全随机的非零 8 字节值；target、xver、SNI 和 Vision 的约束在自有域名配置提交及核心升级前复核。私钥和认证资料使用受保护文件传给工具，不放进外部进程命令行；配置 root:xray 640、目录 750、链接 root:600。自有域名管理拒绝 `bash -x`，防止跟踪输出泄漏密钥。UUID/密钥轮换后旧链接失效，须重新导入。

回落限速默认关闭，可在了解指纹和网站速度影响后主动开启。SNI/Host 过滤只限制本机回落站点的行为，不能判断别人使用公开域名的意图；仍允许正确域名的正常 HTTPS 请求。遇到实际流量攻击应结合主机/上游防护。

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
vless-reality addr                 查看服务器地址，终端内可选择 IP / 域名 / 刷新 IP
vless-reality addr ip              连接地址改用本机当前公网 IPv4
vless-reality addr domain          改用当前自有域名，或普通模式已保存的连接域名
vless-reality addr domain node.example.com  普通模式指定自己的连接域名
vless-reality refresh-ip           刷新公网 IPv4 缓存和链接，保持 IP/域名选择
vless-reality update               升级 Xray-core
vless-reality log -f               实时查看日志
vless-reality uninstall            卸载并清理
```

安装前也可以运行 `/root/vless-reality-setup.sh sni-best` 查看测速结果；该命令只显示候选域名，不会安装或修改节点。

## 服务器连接地址：IP / 域名切换

运行 `vless-reality`，选择 **12「服务器地址管理」**：

```text
1. 连接地址改用公网 IP
2. 连接地址改用域名
3. 刷新公网 IP（保持当前地址模式）
00. 返回
```

两种安装模式都支持。它只改变客户端链接中的 Address，保留端口、REALITY SNI/target、UUID、公钥、Short ID、Vision、TFO 和 VLESS Encryption；不重启 Xray 或 Nginx，也不重新申请证书。切换后重新导入新链接，已导入的客户端不会自动更新。

| 当前安装模式 | 改用 IP | 改用域名 |
| --- | --- | --- |
| 普通 REALITY（第三方 SNI） | 使用当前 VPS 公网 IPv4，SNI 继续用第三方网站 | 填**自己控制且 A 直连 VPS** 的连接域名，不是第三方伪装域名；原第三方 SNI/target 保持不变 |
| 自有域名 REALITY | 使用当前 VPS 公网 IPv4，SNI/网站/证书仍用自己的域名 | 沿用当前自有域名 SNI；真正更换网站域名仍使用菜单 14 或 `sni 新域名` 同步更新 |

普通模式的连接域名也须满足：两个公共解析器一致、唯一 A 指向本机公网 IPv4、无 CNAME、无 AAAA、无 CDN/Cloudflare 橙云。不满足时拒绝切换并保留旧地址。旧普通节点缺少 `dig` 时仅补装 `dnsutils`，不会安装 Nginx/Certbot，也不会改变安装模式；解析记录由用户自行管理。

自有域名模式切换为 IP 后，仍需维护原域名解析、网站和证书自动续期。DNS 检查失败时可以改用 IP，但会明确警告；切回域名必须重新通过 DNS 检查。第三方模式改用 IP 时保留已保存的连接域名，之后可直接用 `addr domain` 切回。

`refresh-ip` 重新查询当前公网 IPv4，更新本地缓存及链接；它不会让服务商分配新 IP，也不会修改 DNS。当前选 IP 时更新链接中的 IP；当前选域名时先检查 DNS，继续保留域名。公网 IP 未变化时不会改变地址选择。

旧六/七/八行安装记录自动兼容，默认仍是普通模式用 IP、自有域名模式用域名；新记录增加地址模式和连接域名字段。选择会随管理操作保留。地址写入前备份安装记录和私有链接，两者保存失败时恢复；回滚也失败则保留备份并报错。成功操作清理备份，异常残留由卸载按归属清理，不新增常驻服务或端口。

地址切换不会清除 NAT 公网回访“待外部验证”提示，也不能替代外部 HTTPS 和真实节点测试。

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

安装后运行菜单第 17 项可输入新模式，也可执行 `vless-reality vlessenc on random` 等命令切换。仅运行 `vless-reality vlessenc on` 时，已开启的节点保持原模式，未开启的节点使用 `native`。

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
