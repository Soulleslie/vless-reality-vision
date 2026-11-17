# Cloudflare Token 更换：审查与测试

版本 v2.4.0，分支 `feat/rotate-cloudflare-token`，基础 `main@a22a584`。实现仍在现有 `install.sh` 内，没有在生产 VPS 部署，没有使用用户 Cloudflare Token。

## 使用与续期行为

新增交互菜单 **28** 与命名命令 `vless-reality cert token`。原 1–27、`cert status` / `cert renew-test` 和历史数字 CLI 语义保留。仅 Cloudflare DNS-01 的自有域名节点可用，HTTP-01 / 普通模式拒绝。

新 Token 从终端隐藏输入或 `VLESS_CF_CREDENTIALS` 指定的 root:600 普通文件读取，不接受秘密命令参数或秘密环境变量。显式去掉同名局部变量继承的 export 属性；来源文件不改写、不删除。相同 Token 拒绝更换，避免将未换新的结果误当作撤销旧令牌的依据。

续期配置继续引用原 `/etc/vless-reality-self/cloudflare.ini`，内容安全更新后，自动任务自然使用新值。现有证书、节点、UUID/密钥/Short ID、Address/SNI、TFO/Encryption、网页、链接、Nginx 配置和 timer 不变。更换时不重签生产证书、不重启 Xray；原续期测试 hook 仍会 nginx -t 并平滑 reload Nginx。

## 验证与事务

1. 只读预检后在不持锁的状态下收集输入，避免提示符长时间停留阻塞自动续期；提交后共用节点目录和自有域名 operation.lock，与自动续期/证书测试/节点管理串行，并在锁内重读记录。域名或安装目录在输入期间改变则拒绝应用。检查归属、Cloudflare 方法、证书域名、保存的 authenticator/凭据路径、可用网站证书、hook 与启用中的 timer。
2. 私有 `work/token-backup.*` 以 700 保存旧/新 600 凭据、原归属清单、续期配置与原测试记录/日志。新凭据先不替换正式文件。
3. 全新临时配置、账户和工作目录执行 `certbot certonly --dry-run`，显式使用 Let’s Encrypt staging、DNS-01、候选文件和 60 秒传播等待，禁用目录 hook，不读取全局 CLI 配置。新账户避免复用旧账户授权而把无效新 Token 误判成功。
4. 通过后原子替换原凭据及 SHA-256，运行原 `renew --dry-run`、既有 Nginx deploy hook 与实际本地 TLS。验证续期配置字节未变化、依然绑定原路径，timer 仍就绪。
5. 正常失败或 HUP/INT/TERM 恢复原凭据、清单、续期配置、原测试 JSON/日志。恢复不成功不删除唯一备份。先同时脱敏旧/新 Token 再清理；按长度排序处理前缀关系。原自动续期历史记录保持，不把历史失败写成新成功。
6. 成功清理临时账户、备份、探测日志和诊断文件，只保留标准续期测试记录/已脱敏日志；正常失败保留 root:600 的脱敏诊断路径。I/O、脱敏或回滚本身异常会返回失败并保留 root 专用资料，不能虚假显示全流程成功。

若验证已经提交但最终清理失败，会明确报告「新 Token 已验证并应用，但临时文件清理失败」，返回失败并保留可恢复资料，不假装已经回滚或已清理完成。

所有新增文件位于原 work/logs/acme 清理范围，不新增白名单例外、软件依赖、端口、系统服务或定时任务。卸载前仍校验归属与共享引用，保留手改/未知/共享资源。修复原续期测试记录写入失败时 `.renew.*` 未立即删除的问题。

DNS TXT 添加/清理由官方插件负责，仅验证 `_acme-challenge`，不改 A/AAAA/CDN。外部 DNS/API 故障或硬中断不能保证远端 TXT 即时清理；不通过删除未知 DNS 记录来“清残留”。本机备份回滚也不能恢复 Cloudflare 已撤销的令牌。应先创建不同的新 Token，成功后再撤销旧 Token。

## 速度与前置条件

原 apt 成功短期复用、双 DNS 并发、SNI 最多 16 个持续任务、网页静态生成均保留。HTTP-01 没有 CF 凭据时仍走日志处理快路径。只有明确调用 Token 更换才执行两阶段 ACME/DNS 验证，传播等待保留 60 秒，可能需要一分钟以上；没有按速度目标跳过验证。

此功能用于配置完整、归属正常、证书/网站与 timer 正常的部署；不是证书已过期、凭据被手改或站点损坏的强制修复入口。旧 Token 可以已经失效，但如果候选也无效，恢复本机旧文件不代表云端旧权限会恢复。SSL 证书自动续期与域名注册续费无关，注册商配置不会修改。

## 修改文件

| 文件 | 内容 |
| --- | --- |
| `install.sh` | v2.4.0；安全输入、独立 DNS-01 探测、凭据/记录事务、双令牌脱敏、菜单/命令及暂存清理 |
| `README.md`、本报告、`SELF_DOMAIN_SECURITY_REPORT.md` | 操作、续期影响、安全边界、卸载与验证 |
| `tests/cf_token.bash` | 权限/来源/绑定、发布/续期/记录/信号/回滚故障、环境/参数保护、双令牌脱敏与锁 |
| `tests/cf_token_input.bash` | 真实 PTY 隐藏输入、格式失败、EOF 取消、终端属性恢复 |
| `tests/cf_token_lock.bash` | 输入等待不占自动续期锁，提交后串行，域名/安装目录变化时拒绝应用 |
| `tests/menu.bash` | 连续 1–28、旧操作/数字语义、菜单 28 与 cert token 分派 |
| `tests/integration/cf_*` | 实际 Cloudflare 插件、Certbot、DNS-01、受限测试 API、Pebble、Nginx/Xray 与撤销旧 Token 后续期 |
| `tests/integration/self_tls.bash` | 原协议/节点实际卸载补充 Token 半成品与私有日志清理 |
| `.github/workflows/tests.yml` | Debian 12/13 矩阵加入真实 DNS-01 与令牌轮换/后续续期联合测试 |

## 验证结果

| 检查 | 结果与范围 |
| --- | --- |
| Bash / ShellCheck / systemd unit | 通过语法、install.sh 零诊断及容器 unit 语法；未运行真实 PID 1 长期调度 |
| 原单元/故障套件与性能 | 通过普通/自有模式、菜单、TFO/Encryption、地址/网页、SNI 并发、apt 复用、回滚与卸载 |
| Token 故障套件 | 通过无效格式、来源模式/归属/链接、相同值、禁用 xtrace、缺失/修改旧凭据、方法/绑定错误、备份/receipt/发布/续期/记录/hook/TLS/timer/信号及回滚失败保护 |
| 秘密保护 | 真实 PTY 无回显/恢复；命令参数和子进程环境没有旧/新 Token，即使调用者导出同名变量；正常输出/日志无 Token，前缀令牌同时脱敏，来源文件不变 |
| 操作互斥 | 真实 PTY 等待输入时自动续期文件锁仍可获取；提交后持锁串行，不提前更换 Token 或发起挑战；输入期间更换域名/安装目录会拒绝应用 |
| Debian 12/13 DNS-01 联合测试 | 两环境通过真实 CF 插件与 DNS 协议、Certbot 和 Pebble；只读 Token 拒绝且原凭据/清单/测试记录不变；有效候选成功后证书/节点/配置/链接哈希不变 |
| 撤销旧 Token 后的续期 | 模拟提供商撤销旧值，原 `self_cert_renew` 用新值完成实际测试 CA 续期、更新证书并让 Nginx 加载；新令牌至少用于独立探测、原 dry-run 和后续续期三次 TXT 创建，均清理 |
| 节点连接 | 实际非 root Xray/VLESS/REALITY/Vision 在更换后和后续证书更新后均正常，服务 PID/节点资料保持；原四种 Encryption 强化协议回归通过 |
| 清理 | 双环境实际清理 CF 账户/备份/诊断/凭据/网站；原节点实际卸载验证 Token orphan 目录也清除，来源文件和共享资源保护保持 |

DNS-01 联合测试只重定向 Cloudflare API 传输到本地受限测试服务、CA 到隔离 Pebble。认证插件/凭据读取/TXT 增删/DNS 查询/ACME/证书/HTTPS/Xray 均实际执行；不启用绕过验证的开关。测试只将等待改为 0，并在测试 CA 强制进入到期续期路径，生产传播等待与到期策略没有改动。测试 CA 只在一次性容器信任；全部端口只在独立测试网络，未对宿主机或 VPS 发布。

## 尚未实测

- 真实 Cloudflare Zone/API、生产 Let’s Encrypt：未使用用户域名或秘密，模拟提供商不等于生产验证。
- systemd PID 1 长期调度、真实 VPS 重启、外部网络及各 Ubuntu/arm64 组合：未部署生产 VPS。实际定时函数、unit 语法和故障路径已测。
- SIGKILL/掉电及外部 API/DNS 故障不能保证执行 shell 回滚或远端清理；严重失败保留私有备份，归属校验仍会保护异常资源。

## 复现与依据

基础步骤见安全报告。新测试：

```bash
bash tests/cf_token.bash
bash tests/cf_token_input.bash
# XRAY_TEST_BIN 为按官方 Release SHA-256 校验的二进制
bash tests/integration/cf_acme.bash vless-self-test "$XRAY_TEST_BIN"
```

- [Cloudflare 插件：权限、凭据文件及保存路径用于后续续期](https://certbot-dns-cloudflare.readthedocs.io/en/stable/)
- [Certbot：dry-run/staging、独立目录和自动续期/hook](https://eff-certbot.readthedocs.io/en/stable/using.html)
