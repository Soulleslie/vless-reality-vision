# 自有域名部署与防滥用安全审查报告

日期：2026-11-14。合并交付分支：`feat/self-domain-security`，版本 v2.1.0。

基础为 `main@2d706c2`（v1.6.2），包含此前自有域名部署分支截至 `92f2aa5` 的全部修改，以及本次加固。所有功能仍内嵌在 `install.sh`，未部署生产 VPS。交付与合并状态见 [PR #2](https://github.com/Soulleslie/vless-reality-vision/pull/2)。基础部署细节见 [原测试报告](SELF_DOMAIN_TEST_REPORT.md)；本报告补充安全审查及当前验收结果。

v2.1.1 后续将交互菜单改为连续 1–26，部署、安全策略与命名命令不变。当前菜单编号以 README 为准；历史命令行数字参数仍按旧映射分派。新增终端回归测试覆盖顺序、输入分派、卸载退出及兼容性。

v2.1.2 根据 NAT VPS 现场反馈修正公网地址回访分类。只有已确认 NAT 且未建立 TCP 的超时/拒绝会记为未验证；本地全部检查通过后保留部署并返回 3，菜单/状态持续提示公网待验证。TLS/证书/H2/HTTP、本地认证、续期和真实外部程序失败仍回滚。新增 `tests/nat_validation.bash`、保留/回滚生命周期用例及两版真实协议环境中的 NAT 超时注入；验证记录 root:600、不含节点认证资料，随项目卸载。外部 HTTP 端口测试不能替代生产 HTTPS/REALITY 客户端验证，后者尚待实际部署后执行。菜单清屏保留滚动历史，便于找回首次失败信息。

## 修改文件

| 文件 | 修改内容 |
| --- | --- |
| `install.sh` | 双模式安装、Nginx、隔离 Certbot/续期、元数据兼容、严格 SNI/Host、安全策略、DNS/CAA、可选回落限速、真实认证检查、权限保护、回滚和卸载 |
| `README.md` | 安装/升级、两种 ACME 方式、全部新增命令、安全边界、卸载范围 |
| `docs/SELF_DOMAIN_TEST_REPORT.md` | 基础部署测试报告，并指向本次加固报告 |
| `docs/SELF_DOMAIN_SECURITY_REPORT.md` | 本报告 |
| `tests/marker.bash` | 兼容旧的六/七行记录和新八行模式标记 |
| `tests/self_domain.bash` | DNS、端口、模式、链接与普通模式兼容 |
| `tests/self_lifecycle.bash` | 签发/服务/续期故障、同步域名切换、安全模板回滚、卸载保护 |
| `tests/self_update.bash` | 核心升级保留自有域名 target，保留旧记录兼容 |
| `tests/security.bash` | 危险配置拒绝、认证资料不进入 jq 参数、限速回滚、CAA、DNS 历史基线 |
| `tests/uninstall.bash` | 中断的检测客户端、认证参数临时文件及旧组件清理 |
| `tests/systemd_units.bash` | systemd-analyze 验证 timer/service/告警 unit |
| `tests/integration/Dockerfile` | 两代 Debian 的一次性真实协议环境 |
| `tests/integration/self_tls.bash` | 实际 Nginx/Xray、正负认证、Host、限速、站点升级及实际卸载 |
| `tests/integration/acme.bash`、`acme_client.bash`、`pebble.json` | 真实 Certbot 与隔离 Pebble 的 HTTP-01 签发、续期和 reload hook |
| `.github/workflows/tests.yml` | Debian Bookworm/Trixie 双矩阵运行以上检查；仅测试容器增加查看非 root fd 所需的 SYS_PTRACE；checkout 固定到官方 v7.0.1 commit（Node.js 24），消除旧运行时弃用提示 |

## 安全审查与实现

### 固定入口与认证

- 自有域名仅允许 `0.0.0.0:443`、TCP、VLESS、REALITY、Vision，以及字面量 target `127.0.0.1:8443`、xver 0、唯一匹配域名的 serverNames。
- 配置提交前拒绝错误 target、空/不匹配 SNI、空或全零 Short ID、空/全零/重复 UUID、非 Vision 客户端及开启 masterKeyLog。生成的 Short ID 为随机 8 字节，密钥和 UUID 使用 Xray/系统随机生成器。
- 核心更新前检查自有域名策略；若已有可选限速，还检查新二进制确实识别字段。更新不覆盖站点模式、域名 Address/SNI 或 loopback target。
- 配置 root:xray 640、目录 750，链接 root:600；实际校验进程 UID 和套接字归属。公钥与私钥的配对通过读取受保护配置计算，私钥不出现在参数或结果中。
- 修复审查发现的进程参数暴露：生成配置、UUID/密钥/Encryption 修改和检测客户端不再使用 `jq --arg` 传递私密认证值。使用 600 临时文件传递，成功/失败清理；中断遗留文件由卸载识别清理。自有域名命令拒绝 `bash -x`。

### Nginx 的 SNI 与 HTTP 过滤

- 未知 SNI/无 SNI 使用默认 server 的 `ssl_reject_handshake on` 拒绝。
- 正确 SNI 还要通过 `$http_host` 与 `$host` 的检查；HTTP/2 :authority 映射同样覆盖。缺少/错误 Host、SNI/Host 不一致和绝对请求 URI 中的其他域名返回 421。允许正常域名大小写差异和合法端口。
- 静态站没有 proxy_pass、正向代理或可由用户指定的上游，只允许 GET/HEAD，保留请求体和超时限制。Nginx 仅绑定 IPv4 回环 8443，TLS 1.3、X25519、h2，首页 200，不跳转。
- `xver=0` 时全部回落连接在 Nginx 中都来自回环。按源 IP 设置请求/并发额度会误把所有用户合并，不默认启用，也不信任 X-Forwarded-For。保留有限持久连接时间/次数等约束。
- 旧开发版本通过 `security-apply` 更新已归属模板，实际验证 TLS/SNI/Host 和合法节点后提交。等待 Nginx 新 worker 加载，避免相同证书的 reload 被过早判定成功。失败回滚，回滚不成功保留备份并明确报错。

### 官方可选回落限速

- `fallback-limit` 默认关闭，不改变普通模式默认行为。开启前提示可识别特征和普通网站受影响。
- 除 `xray run -test` 外，调用当前二进制 `convert pb -debug` 检查实际 typed 配置里的字段和值，防止“未知字段被忽略”却误判支持。调试结果含密钥，只写入私有暂存文件，处理后删除，不打印到日志。升级核心也执行能力校验。
- 两个方向分别使用随机阈值/速率/burst，避免全用户统一固定限速特征；每条未认证回落连接达到约 8–16 MiB 后，约 0.5–2 MiB/s。不是全机总限速，不能阻止大量连接或链路级 DDoS。
- 切换前后真实验证 HTTPS 和合法 VLESS，失败恢复旧配置。使用可收集的 systemd 临时任务应对 SSH 中断；不新增常驻防护服务、监听端口或额外续期任务。

### DNS、证书与告警

- 两个公共解析器校验唯一 A 指向当前 VPS、无 CNAME、无 AAAA。仅 IPv4 入口，因此不假装支持未配置的 IPv6。不会修改用户 DNS。
- 保存 TTL 无关的 A/AAAA/CNAME、最近 NS 和继承后的 CAA 基线，后续变化报告警告。`security-check --accept-dns` 仅在用户确认后更新本地基线，仍须满足直连检查。
- CAA 按父域查找有效记录，两解析器须一致；禁止 LE 的 issue 报错，没有限制或附加账户/验证方式约束时警告，未知 critical 标签标为未验证。CAA 检测不代表域名注册账户安全已获验证。
- 原续期任务同时检测 DNS 直连/历史变化；变化会记录日志并触发原告警机制，但继续尝试证书续期，不封禁正常访问。没有另起独立监控服务。
- LE/Certbot 配置、账户、凭据副本和日志隔离在本项目目录。首次安装必须通过 renew dry-run 和独立真实 deploy hook；每次续期后只 reload Nginx，不重启 Xray。
- 注册商 MFA/Lock/域名续费、DNSSEC、修改提醒和 Token 最小权限由账户管理员在提供商面板配置，脚本明确标为未验证。不能把证书续期与域名续费混为一谈。

### 真实安全检查与监控边界

- `security-check` 先做合法节点真实代理请求，再测试错误 UUID、Short ID 和公钥。合法基线失败则不执行负向检查；准备失败标为未验证，不把所有网络失败都当作安全通过。
- 测试中的正确/错误客户端均使用真实 Xray。负向请求还核对独立测试源访问日志计数没有增长，防止只是“客户端报错”却已经访问目标。
- 连接数/1 秒全机非回环接口采样只提示较高使用量，可能包含其他进程与虚拟接口重复计数，不能据此认定攻击或自动封禁。
- 公开 SNI 任何人都可以填写，服务器无法识别对方的域名使用意图。上述措施保护本机 VLESS 认证和有限的 HTTPS 回落，不宣称能禁止第三方使用公开域名。

## 卸载验收与边界

卸载清理本项目 Xray、service、专用账号/组、配置/备份、链接、快捷命令、管理脚本、TFO 归属设置、旧 RealityChecker、检测客户端及临时认证文件；自有模式还清理站点、网站、证书/ACME 账户、Token 副本、deploy hook、专用 timer/service、私有日志及 DNS/安全记录。清除本项目 unit 的 systemd 失败状态，避免删除 unit 文件后仍显示失败条目；系统 journal 历史不删除。

删除前验证目录标记、文件 SHA-256、符号链接、未知网站数据及常见其他 Web 配置的共享引用。归属/共享检查不通过时停止并明确报告，避免清理一半后丢失管理记录。失败的配置恢复不会静默删除唯一备份。

不删除共享 Nginx/Certbot 系统包、其他站点/证书、系统 journal、共享 timer、用户自备 Token 源文件/外部告警扩展、DNS 或防火墙规则。保留未知/被手工修改的数据，因此不能承诺通过删除所有同名文件来“还原整台系统”。已无项目资源时重复卸载沿用原语义，明确报告未发现，不误删其他资源。

## 测试结果

| 测试 | 结果与实际范围 |
| --- | --- |
| Bash 语法与 ShellCheck | 通过，`install.sh` 静态检查零诊断 |
| 现有与新增测试 | 通过 `tests/*.bash`（原握手单独在容器运行）；覆盖普通模式、旧记录、TFO、Encryption、菜单、更新、卸载和失败回滚 |
| systemd unit | 通过 `systemd-analyze verify`；未运行真实日历调度器 |
| 官方 Xray | 26.11.9，官方 Release 资产 SHA-256 校验后的 amd64 二进制 |
| Nginx/OpenSSL | Nginx 1.22.1 / OpenSSL 3.0.22 和 Nginx 1.26.3 / OpenSSL 3.5.7，均通过实际 nginx -t |
| TLS/网站 | 两环境均通过 TLS 1.3、强制 X25519、h2、测试 CA 链/域名/指纹、443 回落 HTTP/2 200、无跳转、8443 非回环拒绝 |
| SNI/Host | 两环境通过未知/无 SNI 拒绝、HTTP/1.1 与 H2 Host 不匹配 421、大小写/正确端口正常、空 Host 和绝对 URI 域名不匹配拒绝 |
| 合法与错误认证 | Encryption 关闭/native/xorpub/random 均通过真实合法代理及错误 UUID/SID/公钥拒绝，负向目的站请求数不变 |
| 限速与旧模板更新 | 两环境均通过真实开启/关闭、限速后 HTTPS 和合法节点、旧模板更新不改变认证资料；测试使用较低阈值实际测量回落变慢 |
| 权限与安全命令 | 真实 UID、套接字归属、密钥配对、目录/文件权限、完整 security-check；协议测试中的 DNS/调度为明确替身，未伪装为外部验证 |
| ACME | 真实 Certbot 2.1.0 与隔离 Pebble：HTTP-01 签发、renew --dry-run、实际 Nginx reload hook 通过 |
| 故障与保护 | 443/8443/80 占用、错误 DNS/AAAA/CNAME、错误提供商/凭据、签发/续期/状态写入/timer/Nginx/Xray 失败、错误 target、域名切换/安全模板失败及回滚失败备份保留均通过 |
| 实际卸载 | 两环境均实际停止 Nginx，删除节点程序/配置/账号、证书、Token 副本、私有日志、网站和管理入口；确认 443/8443 已无监听，重复卸载安全报告未发现 |

测试 CA 只在一次性容器信任。HTTP-01 未绕过挑战或关闭 TLS 校验。测试目的站是私网独立 HTTP 源，只有测试配置精确放行该 IP/端口，生产配置无此放行。Docker 的 SYS_PTRACE 只为观察非 root 测试服务 fd，不修改生产服务的 capability。

## 未实测项目

- 真实公网域名的生产 Let’s Encrypt 签发/长期续期：未提供域名；隔离 ACME 测试不等于生产签发。部署时必须通过实际申请与 dry-run。
- Cloudflare 真实 Zone/Token 的 DNS-01：未提供生产凭据。仅验证插件参数、凭据权限、提供商判断和失败回滚，未向生产 API 发起修改。
- 实际注册商账户设置、DNSSEC 状态、真实 DNS 历史与告警送达：未提供账户/外部告警渠道。脚本不自动配置注册商或 DNS。
- 真正外部网络访问生产 VPS 443/8443、真实公网节点性能和链路攻击：没有部署生产 VPS；容器非回环拒绝及本机客户端不冒充外部测试。
- systemd PID 1 的长期调度、真实 VPS 重启及长期计时器行为：容器未运行系统调度器，unit 语法与故障路径已测。
- arm64 实机、各 Ubuntu 组合和用户自定义/非标准 Nginx 配置：实际协议环境为 Debian 12/13 amd64，其他组合需部署前在隔离 VPS 验证。

以上未验证项不能算作通过，也不宣称能完全阻止域名被盗或彻底防止带宽滥用。

## 复现

基础步骤见原报告。运行强化协议测试需允许测试容器查看非 root 进程 fd：

```bash
bash -n install.sh tests/*.bash tests/integration/*.bash
docker build -t vless-self-test -f tests/integration/Dockerfile .
docker run --rm -v "$PWD:/src:ro" vless-self-test shellcheck install.sh
docker run --rm -v "$PWD:/src:ro" vless-self-test bash tests/systemd_units.bash
for file in tests/*.bash; do
    [[ "$file" == tests/reality_handshake.bash ]] && continue
    bash "$file"
done
# XRAY_TEST_BIN：已按官方 Release SHA-256 校验的可执行二进制
docker run --rm --cap-add SYS_PTRACE -e LC_ALL=C.UTF-8 -v "$PWD:/src:ro" -v "$XRAY_TEST_BIN:/xray:ro" vless-self-test bash tests/integration/self_tls.bash /xray
bash tests/integration/acme.bash
```

现代语法环境用 `--build-arg DEBIAN_IMAGE=debian:trixie-slim` 重建镜像后复测。GitHub Actions 双矩阵执行同样范围。

## 官方依据

- [Xray REALITY 配置与回落限速说明](https://xtls.github.io/en/config/transports/reality.html)
- [Xray v25.6.8 官方配置解析结构](https://github.com/XTLS/Xray-core/blob/v25.6.8/infra/conf/transport_internet.go)；实现以实际安装二进制能力检查为准。
- [Nginx ssl_reject_handshake](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_reject_handshake)
- [Nginx 请求 server 选择](https://nginx.org/en/docs/http/request_processing.html)
- [Nginx HTTP/2 新旧语法](https://nginx.org/en/docs/http/ngx_http_v2_module.html#http2)
- [Certbot 续期与 hook](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)
- [Cloudflare 插件权限与凭据](https://certbot-dns-cloudflare.readthedocs.io/en/stable/)
- [CAA RFC 8659](https://www.rfc-editor.org/rfc/rfc8659)
