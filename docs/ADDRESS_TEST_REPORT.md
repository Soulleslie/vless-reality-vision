# IP / 域名连接地址切换审查与测试

日期：2026-11-14。版本 v2.2.0，开发分支 `feat/client-address-switch`，基于 `main@105e9d2`（v2.1.2）。本次不在生产 VPS 安装、卸载或重启服务。

## 行为与边界

- 菜单 12 为服务器地址管理，新增 `addr [ip|domain [连接域名]]`；原 `refresh-ip` 和历史数字命令行参数语义保留。
- 普通模式默认 IP，可选择自己 A 直连 VPS 的连接域名；REALITY 的第三方 SNI 和 target 不变，不安装 Nginx/Certbot。自有域名模式默认域名，可切当前公网 IP；SNI、网站、证书和 loopback target 不变。
- 域名切换要求两个解析器一致、唯一 A 指向本机公网 IPv4、无 CNAME/AAAA。缺少 `dig` 时只补 `dnsutils`，安装失败不提交地址。自有模式 IP 兜底允许 DNS 尚未修好，但明确警告仍需维护网站与证书解析。
- 自有模式更换网站域名继续使用 `sni`，同步证书/Nginx/Xray；Address 为 IP 时保留 IP 选择，为域名时跟随新 SNI。域名变更失败恢复原地址记录和链接。
- 安装记录新增第 9/10 行：地址模式 `auto|ip|domain` 与普通模式连接域名；旧六/七/八行自动兼容。普通默认 IP、自有默认域名不变。
- 仅地址操作提交安装记录和 root:600 链接，不写 Xray 配置、不重启服务。配置 root:xray 640、目录 750 的权限不变。更换 UUID、密钥或 Encryption 后继续使用已选地址。
- 更新地址前备份元数据和链接，任一保存失败恢复旧版本；回滚失败保留唯一备份并报错。成功清理备份，中断残留纳入原有归属卸载清理，不新增锁文件、常驻服务或端口。
- 普通与自有模式的节点修改、链接重生成使用同一目录上的 `flock`；自有域名更换也使用相同顺序，继续协调证书/域名锁。等待后重读元数据，并确认目录 inode 未替换，避免覆盖并发生成的认证或地址记录。临时 Xray 检测客户端不继承管理锁。
- `refresh-ip` 更新缓存/链接并保留当前 IP/域名选择，不向服务商申请新 IP，不修改 DNS。地址切换不能消除 NAT 回访待验证状态或证明真正的外部连接成功。

## 验证范围

| 检查 | 结果与范围 |
| --- | --- |
| Bash 语法、ShellCheck | 通过；`install.sh` 零诊断 |
| 地址功能与故障注入 | 通过；双模式 IP/域名往返、错误 DNS/IPv4/域名拒绝、IP 兜底、地址模式保持、元数据/链接写入失败恢复、恢复失败保留备份、并发查看/修改重读、等待时节点被替换则拒绝 |
| 旧记录及菜单 | 通过；六/七/八行兼容、十行记录校验、连续 1–26、菜单 12 分派、旧数字 12 仍刷新 IP |
| 身份与更新兼容 | 通过；UUID/密钥/Encryption 修改后保留选择、Xray 更新保留 IP 选择、域名变更成功/失败均保留地址模式 |
| 卸载 | 通过单元故障测试和两套真实容器卸载；地址备份/私有链接输出、网站、证书、Token 副本、节点/账号/管理入口清理，443/8443 无监听；重复卸载安全报告未发现 |
| 原有回归 | 通过全部 `tests/*.bash`；原握手另在真实 Xray 容器执行；systemd unit 由容器 root 执行 `systemd-analyze verify`，不将本地非 root 跳过记作通过 |
| 真实协议 | Debian 12/13 双环境通过；官方 SHA-256 校验的 Xray 26.11.9，Nginx 1.22.1/1.26.3，TLS 1.3/X25519/h2、四种加密设置下的 IP/域名实际连接、配置/证书/原进程保持、错误认证拒绝 |
| 真实 Certbot HTTP-01/renew | 证书逻辑未修改；本地真实 Certbot 2.1 与隔离 Pebble 签发、`renew --dry-run`、独立 deploy hook 通过；PR CI 在两个 Debian 环境重跑，结果见 PR 检查 |

真实协议测试分别以 IP 和 `/etc/hosts` 中的测试域名作为客户端 Address，用真实 Xray 客户端执行 REALITY/Vision 请求，覆盖 Encryption 关闭/native/xorpub/random。普通模式的第三方目标用同一隔离 TLS 网站替身，DNS 由独立故障测试覆盖；不将容器测试域名冒充公网 DNS 验证。比较配置、Nginx 站点、状态和证书文件摘要，核对原服务进程仍存活，检查 Address 改变而 SNI 不变。既有 TLS 1.3、X25519、h2、HTTP/2 200、错误认证拒绝、8443 回环限制、限速和实际卸载均回归通过。

## 未实测项目

- 未修改用户正在使用的生产节点；生产客户端导入新链接的各应用兼容性、真实 DNS 传播、IP 变化后的服务商映射需部署者验证。
- 未调用生产 Cloudflare API、未申请生产 Let’s Encrypt 证书；本次未改签发/续期逻辑，隔离 ACME 不代表生产续期已验证。
- 不以本机探测替代真正外部网络测试。用户报告其现有节点可访问外部网站；该人工结果不自动写成脚本已完成外部程序验证。
- arm64 实机、Ubuntu 全版本、长期 systemd 调度未新增实测。

## 复现

```bash
bash -n install.sh tests/*.bash tests/integration/*.bash
docker run --rm -v "$PWD:/src:ro" vless-self-test shellcheck install.sh
docker run --rm -v "$PWD:/src:ro" vless-self-test bash tests/systemd_units.bash
for file in tests/*.bash; do
    [[ "$file" == tests/reality_handshake.bash ]] && continue
    bash "$file"
done
# XRAY_TEST_BIN 必须为已经验证官方 Release SHA-256 的可执行二进制。
docker run --rm --cap-add SYS_PTRACE -e LC_ALL=C.UTF-8 -v "$PWD:/src:ro" -v "$XRAY_TEST_BIN:/xray:ro" vless-self-test bash tests/integration/self_tls.bash /xray
```

完整复现及隔离 ACME 环境见 [安全报告](SELF_DOMAIN_SECURITY_REPORT.md) 和 GitHub Actions 双矩阵。测试容器增加 SYS_PTRACE 仅用于检查非 root Xray 的套接字归属，不修改生产服务权限。
