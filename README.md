# VLESS + REALITY + Vision 节点管理脚本

这是参照 [Soulleslie/anytls-](https://github.com/Soulleslie/anytls-) 的交互和运维思路编写的 Xray-core 管理脚本，用于在 Debian/Ubuntu VPS 上安装 **VLESS + REALITY + XTLS Vision**。

与原 AnyTLS 脚本的主要区别：REALITY 不申请 TLS 证书，因此不要求自有域名，也不需要开放 TCP 80。安装时需要选择一个支持 TLS 1.3、可从 VPS 正常访问的伪装站点域名（SNI）。

## 功能

- 从 `XTLS/Xray-core` 官方 GitHub Release 获取最新稳定版
- 使用 GitHub Release 的 SHA-256 digest 校验安装包
- 支持 `amd64` 和 `arm64` 的 Debian/Ubuntu
- 安装前检测现有 Xray 文件和服务，不覆盖已有配置
- 自动生成 UUID、X25519 密钥和 Short ID
- 从用户提供的同网段候选域名中筛选 REALITY 伪装目标，再按 VPS 实测延迟优选
- 手动输入域名时检查 TLS 1.3、X25519、H2、证书和跳转，并显示握手耗时
- 可单独查看筛选结果，不修改节点
- 输出标准 `vless://` 客户端导入链接
- 中文菜单管理启动、停止、重启、日志和状态
- 修改端口、SNI、UUID、REALITY 密钥和节点名称
- 可选开启 TCP Fast Open，并在菜单或命令行切换
- 升级失败、配置修改失败和首次安装失败时回滚
- 卸载时只清理本脚本拥有的文件

## 安装前准备

1. 使用带公网 IPv4 的 Debian 或 Ubuntu VPS，以 root 身份执行。
2. 在云服务商安全组中放行准备使用的 TCP 端口。若使用系统防火墙，也需放行该端口。
3. 选择端口时直接回车使用 TCP 443；若已占用，脚本会提示重新输入其他端口（例如 8443）。
4. 在伪装域名处直接回车，可逐行粘贴从 bgp.tools Forward DNS 找到的候选域名，以空行结束；也可以直接输入一个自定义域名。脚本不会自行扫描整个网段或抓取 bgp.tools 网页。导入后会从 VPS 核对域名的全部 IPv4 地址是否仍在本机同一个 `/24` 网段，并跳过有 IPv6 地址的域名，避免实际目标落到其他网络；再检查 TLS 1.3、X25519、H2、证书、跳转和明显的 Cloudflare 响应标志。手动输入的域名也会检查这些 TLS 和网站条件，但不要求同网段。通过后会显示 VPS 到目标站点的握手耗时；导入多个候选时按两次握手平均耗时选最低值。这个耗时不是客户端到 VPS 的延迟。
5. 选择是否开启 TCP Fast Open；直接回车默认关闭。安装后可通过菜单第 17 项切换。

## 一键安装

使用下面的方式下载并运行。不要使用 `curl | bash`，因为脚本需要从终端读取安装参数，并会作为管理脚本保留在 VPS 上。

```bash
wget -O /root/vless-reality-setup.sh https://raw.githubusercontent.com/Soulleslie/vless-reality-vision/main/install.sh && chmod +x /root/vless-reality-setup.sh && /root/vless-reality-setup.sh
```

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

v1.5.0 移除内置域名列表和 `auto` 优选；新增导入同网段候选的 `nearby` 流程与 `sni-nearby` 命令。

v1.6.0 手动安装、修改 SNI 时加入完整目标检查；新增只读 `sni-check` 和菜单第 18 项。跨域跳转会提示跳转目标域名，不会自动改用或请求该域名。

## 非交互安装

参数顺序为端口、伪装域名、节点名称：

```bash
/root/vless-reality-setup.sh install 443 www.amazon.com Reality-SG
```

要从同网段候选中优选，先把 bgp.tools Forward DNS 上的候选整理为纯域名列表，每行一个（最多 32 个），再把第二个参数写成 `nearby:文件路径`：

可运行 `cat > /root/reality-neighbors.txt`，逐行粘贴域名，最后按 `Ctrl+D` 保存。域名文件由用户创建，脚本只读取。

```bash
/root/vless-reality-setup.sh install 443 nearby:/root/reality-neighbors.txt Reality-SG
```

末尾可加 `on`，用于在安装时开启 TFO；省略时默认关闭：

```bash
/root/vless-reality-setup.sh install 443 nearby:/root/reality-neighbors.txt Reality-SG on
```

## 常用命令

```text
vless-reality show                 显示 vless:// 导入链接
vless-reality status               检查服务、配置、端口和伪装站点
vless-reality port 8443            修改监听端口
vless-reality sni 目标域名          修改 REALITY 伪装域名
vless-reality sni nearby:/root/reality-neighbors.txt  优选后修改 SNI
vless-reality sni-nearby /root/reality-neighbors.txt  仅查看同网段优选结果
vless-reality sni-check example.com  检查单个伪装域名，不修改节点
vless-reality tfo                  显示状态，交互式切换 TFO
vless-reality tfo on               开启 TFO
vless-reality tfo off              关闭 TFO
vless-reality uuid                 重新生成 UUID
vless-reality rotate-keys          轮换 REALITY 密钥和 Short ID
vless-reality rename Reality-US    修改节点名称
vless-reality refresh-ip           刷新链接中的公网 IPv4
vless-reality update               升级 Xray-core
vless-reality log -f               实时查看日志
vless-reality uninstall            卸载并清理
```

安装前也可以运行 `/root/vless-reality-setup.sh sni-nearby /root/reality-neighbors.txt` 查看筛选结果；该命令不安装或修改节点。菜单第 16 项可直接逐行粘贴候选域名。旧的 `auto` 参数已移除；用户自行创建的候选文件不会在卸载时删除。

单独检查一个域名可运行 `/root/vless-reality-setup.sh sni-check example.com`，或在菜单选第 18 项。脚本从 VPS 验证 TLS 1.3、X25519 密钥交换、H2 协商、证书域名及信任链，并检查最多三次同域 HTTPS 跳转。若跳至其他域名，脚本会提示首个跨域跳转目标；重新输入并检查，直至不再跨域跳转。响应头中的 CDN/缓存线索和少数常见大型站点名称只会触发提示；不能可靠判断所有 CDN 或网站热度。测速结果是当前 VPS 的两次 TLS 握手耗时，DNS 和站点状态以后可能改变。网页内的 JavaScript 跳转无法通过 HTTP 响应头检查发现。

修改已安装节点的 SNI 会重启 Xray；如果当前 SSH 经过这个节点，请先改用 VPS 直连 SSH。修改后运行 `vless-reality show`，更新客户端中的 SNI 和导入链接。

## TCP Fast Open

TFO 默认关闭。开启时，脚本设置 Xray 入站的 `sockopt.tcpFastOpen`，并开启内核参数 `net.ipv4.tcp_fastopen` 的服务端位。内核设置写入 `/etc/sysctl.d/99-vless-reality-tfo.conf`，重启后仍生效。关闭或卸载时，只清理带有本脚本标记的设置文件，并尽可能恢复修改前的内核值；若内核值后来被其他程序改动，脚本会保留当前值并提示。

TFO 只影响新建 TCP 连接。客户端若支持 TFO，也需要在客户端单独开启；`vless://` 导入链接不会替客户端设置 TFO。部分网络对 TFO 的兼容性较差，因此默认关闭。

切换 TFO 会重启 Xray。如果 SSH 连接经过这个 VLESS 节点，重启可能切断当前 SSH 会话；建议通过 VPS 的直连 SSH 操作。切换由 systemd 后台任务完成，断线后任务仍会继续。重连后运行 `vless-reality status` 核对结果；失败详情可用 `journalctl -u vless-reality-tfo -n 30 --no-pager` 查看。

卸载会先停止并禁用本脚本创建的 Xray 服务，然后恢复本脚本设置的 TFO 内核参数，删除程序、配置、安装记录、节点链接、管理脚本、快捷命令、配置备份和可识别的中断临时文件，最后核验服务与专用账号是否仍存在。任一步失败会报错，并尽可能保留安装记录，便于修正问题后重试。

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
