# VLESS + REALITY + Vision 节点管理脚本

这是参照 [Soulleslie/anytls-](https://github.com/Soulleslie/anytls-) 的交互和运维思路编写的 Xray-core 管理脚本，用于在 Debian/Ubuntu VPS 上安装 **VLESS + REALITY + XTLS Vision**。

与原 AnyTLS 脚本的主要区别：REALITY 不申请 TLS 证书，因此不要求自有域名，也不需要开放 TCP 80。安装时需要选择一个支持 TLS 1.3、可从 VPS 正常访问的伪装站点域名（SNI）。

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
- 可选安装并运行 [RealityChecker](https://github.com/V2RaySSR/RealityChecker) 检测伪装域名，卸载节点时清理本脚本安装的程序
- 升级失败、配置修改失败和首次安装失败时回滚
- 卸载时只清理本脚本拥有的文件

## 安装前准备

1. 使用带公网 IPv4 的 Debian 或 Ubuntu VPS，以 root 身份执行。
2. 在云服务商安全组中放行准备使用的 TCP 端口。若使用系统防火墙，也需放行该端口。
3. 选择端口时直接回车使用 TCP 443；若已占用，脚本会提示重新输入其他端口（例如 8443）。
4. 安装时伪装域名直接回车，会立即测速并显示实测延迟最低的域名，然后再提示输入节点名称；也可以手动输入一个支持 TLS 1.3 的域名。自动优选从脚本内的 68 个候选域名并发初筛，跳过证书或 TLS 1.3 验证失败的站点，再复测全部通过初筛的域名，选两次握手平均耗时最低的站点。这个耗时是 **VPS 到伪装站点** 的耗时，不是客户端到 VPS 的延迟。若候选全部不可用，请手动指定域名。
5. 选择是否开启 TCP Fast Open 和 VLESS Encryption；两者直接回车都默认关闭。开启 VLESS Encryption 后可选择 `native`、`xorpub`、`random`，直接回车默认 `native`。安装后可分别通过菜单第 17、19 项切换。交互安装还会询问是否安装 RealityChecker，直接回车默认不安装。

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

v1.4.3 增加可选 RealityChecker 管理入口；按架构下载官方发布包、校验 SHA-256、安装程序并记录归属，卸载节点时一并清理。

v1.4.4 补齐 RealityChecker 的单域名、空格分隔批量域名和 CSV 文件检测，并在菜单第 18 项提供三个入口。

v1.4.5 修正 RealityChecker v2.2.3 将 RealiTLScanner CSV 的 `TLS` 列误当域名的问题：按 `CERT_DOMAIN` 列名提取域名，生成临时兼容文件后再检测。

v1.5.0 增加 VLESS Encryption 开关：通过 `xray vlessenc` 生成配对参数，写入服务端配置和客户端链接；切换由 systemd 后台任务完成，失败时恢复原配置。

v1.6.0 增加 VLESS Encryption 的 `native`、`xorpub`、`random` 三种模式；安装时选择，安装后可从菜单或命令行修改。默认 `native`。

v1.6.1 开启服务端 TFO 时，在新生成的导入链接中附带客户端可选参数 `tfo=1`；切换 TFO 后刷新链接。

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

## 常用命令

```text
vless-reality show                 显示 vless:// 导入链接
vless-reality status               检查服务、配置、端口和伪装站点
vless-reality port 8443            修改监听端口
vless-reality sni www.apple.com    修改 REALITY 伪装域名
vless-reality sni auto             重新测量并优选伪装域名
vless-reality sni-best             显示当前测速延迟最低的域名，不修改节点
vless-reality checker install      安装 RealityChecker
vless-reality checker check 域名   用 RealityChecker 检测域名
vless-reality checker batch apple.com tesla.com microsoft.com  批量检测域名
vless-reality checker csv file.csv 从 CSV 文件检测域名
vless-reality checker status       查看 RealityChecker 状态
vless-reality checker uninstall    单独卸载 RealityChecker
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

## RealityChecker（可选）

交互安装节点时可以选择一并安装 RealityChecker，默认不安装；非交互安装节点后可单独运行 `checker install`。菜单第 18 项可安装、检测或单独卸载；命令行也可运行 `vless-reality checker install`，安装节点前可使用 `/root/vless-reality-setup.sh checker install`。安装时，脚本根据 VPS 的 amd64 或 arm64 架构读取官方最新稳定版的 GitHub Release，校验发布信息给出的 SHA-256 后解压并设置执行权限。程序安装在 `/usr/local/bin/reality-checker`，归属记录写入 `/usr/local/bin/.vless-reality-checker-owned`；不会把压缩包留在当前目录。若工具下载失败，已成功安装的节点仍会保留，可稍后重试。

工具的三种检测方式均可从菜单第 18 项进入，也可使用 `vless-reality checker check example.com`、`vless-reality checker batch apple.com tesla.com microsoft.com` 和 `vless-reality checker csv file.csv`。批量域名以空格分隔；CSV 路径可以是当前目录下的文件名或绝对路径。CSV 必须有 `CERT_DOMAIN` 列（也支持单列 `DOMAIN`）；脚本会跳过无效或重复域名，生成三列的临时文件供 RealityChecker 读取，检测结束即删除临时文件。上游 RealityChecker v2.2.3 直接读取 CSV 时固定使用第 3 列；对包含 `IP,ORIGIN,TLS,...,CERT_DOMAIN` 的 RealiTLScanner 文件，直接执行 `reality-checker csv file.csv` 会把 `TLS 1.3` 错当域名。请使用本脚本的 `checker csv` 入口。CSV 转换使用 Python 3，若 VPS 缺少它，首次使用时会安装。用户提供的原 CSV 不会被修改，卸载时也不会删除。

卸载节点时会连同本脚本管理的 RealityChecker 和可识别的暂存目录一起清理；单独运行 `vless-reality checker uninstall` 也可以清理。脚本不会覆盖或删除未带本脚本归属记录的同名程序。如果程序内容在安装后被改动，卸载会停止并提示检查，以免误删其他程序。以前手动执行 `wget`、`unzip` 留在当前目录中的文件不属于脚本管理范围。

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
