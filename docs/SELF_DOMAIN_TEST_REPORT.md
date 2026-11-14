# 自有域名 REALITY 开发与测试报告

日期：2026-11-14。基础版本：`main@2d706c2`（v1.6.2），开发分支：`feat/self-domain-reality`。本报告记录开发阶段验证，未在生产 VPS 部署；交付与合并状态见 [PR #2](https://github.com/Soulleslie/vless-reality-vision/pull/2)。

后续 v2.1.0 已把部署与安全任务合并至 `feat/self-domain-security`；新增功能和当前完整验收见 [安全审查与测试报告](SELF_DOMAIN_SECURITY_REPORT.md)。

本报告中的 20–24 是开发阶段旧菜单编号。v2.1.1 的交互菜单已改为连续 1–26，当前编号以 README 和实际菜单为准；命名命令保持兼容。

## 修改文件

- `install.sh`：单文件内嵌自有域名模式、DNS 与端口预检、Nginx 静态站、Certbot 申请/续期、检测、同步域名变更、操作锁、归属校验和卸载回滚。保留原命令与菜单编号；新增菜单 20–24。
- `README.md`：双模式、DNS/Cloudflare/HTTP-01、端口分工、证书、管理、安全与卸载边界。
- `tests/marker.bash`：兼容六行/七行旧安装记录以及八行模式记录。
- `tests/uninstall.bash`：补充中断客户端检测的可识别暂存文件清理。
- `tests/self_domain.bash`：DNS、端口冲突、元数据、链接、自有域名管理限制与普通模式配置。
- `tests/self_lifecycle.bash`：安装/失败回滚、证书/服务故障、域名切换回滚、重复安装、修改文件及用户数据保护、卸载清理。
- `tests/self_update.bash`：升级 Xray 保留自有域名 target 和旧安装记录。
- `tests/systemd_units.bash`：生成真实 timer/service/告警 unit 并执行 systemd-analyze verify。
- `tests/integration/Dockerfile`：Debian Bookworm/Trixie 的隔离 Nginx/Certbot/ShellCheck 测试环境。
- `tests/integration/self_tls.bash`：真实 Nginx、OpenSSL、非 root Xray 服务端与实际客户端的 HTTPS/协议测试。
- `tests/integration/{acme.bash,acme_client.bash,pebble.json}`：真实 Certbot 与隔离 Pebble ACME 的 HTTP-01 签发、dry-run、reload hook 验证。
- `.github/workflows/tests.yml`：PR/主分支 CI，在两代 Debian 环境验证。

## 技术选择与审查结果

- `install-self` 复用既有官方 Release 下载和 SHA-256 校验、UUID/密钥/Short ID、Vision、TFO、VLESS Encryption 和非 root Xray 服务流程。普通模式不新增 Nginx/证书依赖。
- 安装记录第八行为 `external` 或 `self`，缺失按普通模式处理。自有域名链接使用域名 Address，target 永远是 `127.0.0.1:8443`；禁止 `sni auto` 和变更 443 端口。域名更换同步网站、证书、Xray、链接并支持恢复。
- Nginx 1.22 使用 `listen ... ssl http2`；1.26 使用 `http2 on`。未知/无 SNI 使用 `ssl_reject_handshake` 拒绝；本项目站点仅 IPv4 回环 8443。
- Certbot 使用独立 config/work/logs，显式空 cli.ini 避免继承共享配置。项目 timer 只处理独立 lineage，共享 Certbot timer/证书不动。dry-run 后单独执行实际 deploy hook，避免错误地把 dry-run 当成已执行 hook。
- 续期结果、证书有效期和 Nginx 实际加载的证书指纹都检查；失败/不足 14 天记录日志，提供用户管理的外部告警入口。Token 隐藏输入、root:600 保存、日志脱敏。
- 安装临时抑制新 Nginx 包的默认站点启动。抑制文件、网站、站点配置、凭据和 unit 有明确归属记录；原子发布站点/unit。卸载前检查文件变更、未知数据、目录符号链接和常见 Web 服务共享引用。
- 自有域名变更、续期、常用节点修改及卸载通过操作锁协调。REALITY 检测客户端有私有暂存目录和 PID/启动时间记录，中断后可识别清理，避免误杀复用 PID。
- 参考官方 REALITY 文档，回落限速会引入特征，不默认统一开启 `limitFallbackUpload/Download`；不使用未经确认的字段。回落仅为静态站，不是开放反向代理。
- 测试发现并修正了布尔 `false` 状态读取、HTTP-01 探测文件权限、reload 后新证书加载等待、旧安装记录行数、安装失败时管理脚本保留与临时资源清理等问题。

## 已通过的本地验证

| 项目 | 环境与范围 |
| --- | --- |
| Bash 语法 | `bash -n install.sh tests/*.bash tests/integration/*.bash` |
| ShellCheck | ShellCheck 0.9.0 对 `install.sh` 检查，零诊断；子 shell 状态隔离使用有说明的定向注释 |
| 原有测试与新增故障测试 | `tests/*.bash`，实际握手单独执行；systemd 验证在容器内 root 执行 |
| 官方 Xray | 26.11.9，重新查询官方 latest 并按官方资产 SHA-256 校验 |
| 普通模式实际握手 | 原有 `tests/reality_handshake.bash`；与其原测试定义一致，内网目标仍被 Xray 默认安全规则拒绝 |
| 自有域名 TLS/网站/协议 | Nginx 1.22.1 + OpenSSL 3.0.22；Nginx 1.26.3 + OpenSSL 3.5.7 |
| 自有域名 HTTPS 回落 | 真实 Xray 443 → Nginx 127.0.0.1:8443，HTTP/2 200，无跳转 |
| TLS/SNI | TLS 1.3、强制 X25519、ALPN h2、测试 CA 证书链/域名/已加载指纹、未知与无 SNI 拒绝 |
| 实际节点请求 | 非 root Xray 服务端 + 实际客户端，Encryption 关闭/native/xorpub/random；通过 SOCKS 传输实际 HTTP 内容 |
| Certbot 实际申请/续期 | Certbot 2.1.0 对隔离 Pebble 测试 CA 做真实 HTTP-01、renew --dry-run，并实际 reload Nginx |
| systemd unit 语法 | `systemd-analyze verify`，专用 service/timer/OnFailure 告警 unit |
| 故障注入 | DNS、提供商不匹配、凭据权限、签发失败、续期失败、timer 失败、Nginx/Xray 启动失败、target 错误、域名切换部分失败 |
| 保护与兼容 | 443/8443/80 占用、无/错误/AAAA/CNAME 记录、重复安装、旧记录、Xray 更新、修改的配置、额外网站数据、共享证书引用和卸载清理 |

协议测试的证书为仅容器信任的测试 CA。测试出站源在隔离容器私网，Xray 仅在测试配置中为该地址/端口添加精确的 allow finalRule，生产配置不添加该放行。ACME 测试仅由测试 wrapper 将生产 CA URL 替换为 Pebble，不跳过 HTTP-01 挑战，不关闭 TLS 验证，没有使用 `PEBBLE_VA_ALWAYS_VALID`。

## 未实测及交付限制

| 未验证项目 | 原因与部署时验证方式 |
| --- | --- |
| 生产 Let’s Encrypt 签发/续期 | 没有提供可控制的公网域名；安装时必须实际签发并通过 dry-run，否则回滚 |
| 真实 Cloudflare API Token 与 DNS-01 | 未提供真实 Zone/Token；测试验证参数、权限、提供商拒绝和失败清理，未调用生产 Cloudflare API |
| 真实公网 DNS 直连 VPS | DNS 逻辑用记录替身验证，部署时向两个公共解析器做真实查询 |
| 真正外部网络的 HTTPS/VLESS | 测试源在隔离网络；脚本明确标为未验证，支持用户的外部验证程序，不能把本机回访算作外部验证 |
| systemd 实际日历调度与长期续期 | 容器不是 systemd PID 1；unit 已验证，启动/失败以替身测试，需在用户测试 VPS 查看 timer 与实际运行记录 |
| arm64 实机 | 当前隔离协议环境为 amd64；保留原有 arm64 官方资产映射，但未做 arm64 实机验证 |
| Ubuntu 发行版组合 | 保持 Debian/Ubuntu 支持，协议集成实际测试在 Debian 12/13；其他组合需有满足要求的 Nginx/OpenSSL/curl/Certbot |

CI 首次运行发现 GitHub runner 缺少旧握手测试使用的 rg；已将该测试移入包含依赖的隔离容器。当前没有未解决的本地已运行测试失败。上述未验证项不算通过；本交付不宣称生产方案已经完全验证。网站文件被用户修改或资源被共享时，卸载会明确保留并报错，不能承诺抹除用户数据来追求“零残留”。系统包、journal、其他站点/证书和用户自己提供的源凭据也不属于项目卸载范围。

## 复现

```bash
bash -n install.sh tests/*.bash tests/integration/*.bash
docker build -t vless-self-test -f tests/integration/Dockerfile .
docker run --rm -e LC_ALL=C.UTF-8 -v "$PWD:/src:ro" vless-self-test shellcheck install.sh
docker run --rm -e LC_ALL=C.UTF-8 -v "$PWD:/src:ro" vless-self-test bash tests/systemd_units.bash
for file in tests/*.bash; do
    [[ "$file" == tests/reality_handshake.bash ]] && continue
    bash "$file"
done
# XRAY_TEST_BIN 应指向已按官方 Release SHA-256 验证的可执行二进制。
bash tests/reality_handshake.bash "$XRAY_TEST_BIN"
docker run --rm -e LC_ALL=C.UTF-8 -v "$PWD:/src:ro" -v "$XRAY_TEST_BIN:/xray:ro" vless-self-test bash tests/integration/self_tls.bash /xray
bash tests/integration/acme.bash
# 新 Nginx 语法可用 --build-arg DEBIAN_IMAGE=debian:trixie-slim 重建同名镜像复测。
```
