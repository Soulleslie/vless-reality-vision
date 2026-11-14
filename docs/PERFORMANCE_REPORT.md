# 执行速度与兼容性报告

日期：2026-11-14。版本 v2.2.2，分支 `perf/preserve-checks-and-reduce-waits`，基于 `main@3760a84`（v2.2.1）。此次仅优化内部执行，不在生产 VPS 部署、重启、卸载或修改防火墙。

## 修改范围

| 项目 | 优化 | 保持的行为 |
| --- | --- | --- |
| 依赖安装 | 当前执行链复用成功刷新的 apt 索引，子 shell 继承结果 | 仍安装所有缺失依赖；失败不标记成功；新执行链需要安装依赖时重新刷新；不增加磁盘缓存 |
| 自有域名及连接域名 DNS | 两个解析器并发，各自按原顺序检查 A、AAAA | 仍要求两解析器均通过、A 唯一指向当前公网 IPv4、无 CNAME/AAAA；不缓存 DNS/IP；错误按原解析器顺序报告 |
| 第三方 SNI 优选 | 最多 16 个任务持续补充，避免整批空等慢任务 | 生产候选仍为 68 个；全部有效候选仍复测；证书/TLS 校验、超时及两次平均值排序不变；旧 Bash 沿用原批次调度 |

菜单编号、命令及数字命令兼容、默认值、节点参数、Nginx/Xray 配置、UUID/密钥、TFO、Encryption、证书续期、日志、回滚与卸载策略不变。没有缩短网络超时，没有跳过官方 SHA-256、TLS/X25519/H2、证书链/域名、实际正负向 VLESS 请求、`renew --dry-run` 或 Cloudflare 的 DNS 传播等待。

并发 DNS 使用进程内管道，没有新增暂存目录。工作者必须完整执行并返回成功标记；异常退出即使退出码为 0 也拒绝通过。结束时关闭管道、等待并回收工作者；工作者不继承管理锁。SNI 仍使用原有归属临时目录和相同结果文件格式，成功后清理，中断残留沿用原卸载清理，不增加服务或端口。

## 可复现的受控测量

`tests/performance.bash` 使用固定延迟替身，不访问公网、不安装软件。旧版为 `3760a84:install.sh`，新版为本分支实现，交替执行各三次：

| 场景 | 旧版三次耗时 | 新版三次耗时 | 中位数变化 |
| --- | --- | --- | --- |
| DNS：每次查询固定等待 150 ms，成功仍须完成四项 | 649 / 645 / 652 ms | 328 / 323 / 329 ms | 649 → 328 ms，约降低 49% |
| SNI：48 个替身，原每批首项 400 ms，其余 10 ms；1 项初筛失败 | 2480 / 2483 / 2495 ms | 935 / 920 / 923 ms | 2483 → 923 ms，约降低 63% |

DNS 两版都完成 `1.1.1.1`/`8.8.8.8` 的 A、AAAA 四项查询，峰值并行从 1 变为 2。SNI 两版都是 48 项初筛 + 47 项复测，共 95 次，峰值并行均不超过 16，选出同一个最快候选。基准中的 48 个替身不是生产候选列表，生产仍为原有 68 个。

另验证旧 Bash 分支未满 16 个时继续补任务、达到上限才按原批次等待；apt 更新只复用本次成功结果，失败可重试，新执行链重新更新；DNS 工作者提前退出不能被标记通过。

上述数字仅反映固定延迟下的局部调度。不能据此承诺整次安装快 49%/63%，也不表示真实站点握手耗时变短。解析器故障时仍受原超时约束，个别失败路径不保证更快。

## 兼容性验证

本地 Bash 语法、ShellCheck、全部单元/故障回归、容器 root 的 systemd unit 验证以及 Debian 12/13 两套真实协议/卸载测试均通过。PR CI 重跑相同范围和隔离 ACME，结果见 PR 检查。验证范围包括：

- Bash 语法、ShellCheck、原有和新增单元/故障测试、真实终端菜单/输入与旧命令兼容。
- 普通及自有模式、DNS 状态/AAAA/第二解析器失败、输入二次确认、NAT 待验证保护、IP/域名切换。
- 两套真实 Nginx/Xray 环境的 TLS 1.3、X25519、h2、正确/错误认证、四种 Encryption 设置、回落与完整卸载。
- 隔离 Pebble 的真实 Certbot HTTP-01、续期 dry-run 和 Nginx deploy hook（PR 双环境 CI）。

未新增生产 Cloudflare API、Let’s Encrypt 生产签发、真实 VPS 软件源/长期运行、arm64 实机、全部 Ubuntu/Bash 版本的实测。旧 Bash 调度分支通过受控兼容用例，不冒充旧版本解释器的实机验证。

## 复现

```bash
git show 3760a84294c8b573e02092eda95fbec3181ff777:install.sh > /tmp/vless-speed-before.sh
bash tests/performance.bash --benchmark /tmp/vless-speed-before.sh
bash tests/performance.bash
bash -n install.sh tests/*.bash tests/integration/*.bash
docker run --rm -v "$PWD:/src:ro" vless-self-test shellcheck install.sh
for file in tests/*.bash; do
    [[ "$file" == tests/reality_handshake.bash ]] && continue
    bash "$file"
done
```

真实协议环境及 ACME 复现见 [安全报告](SELF_DOMAIN_SECURITY_REPORT.md) 和 GitHub Actions。完整比较应交替运行，避免同时执行重负载测试影响计时。
