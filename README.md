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
- 输出标准 `vless://` 客户端导入链接
- 中文菜单管理启动、停止、重启、日志和状态
- 修改端口、SNI、UUID、REALITY 密钥和节点名称
- 升级失败、配置修改失败和首次安装失败时回滚
- 卸载时只清理本脚本拥有的文件

## 安装前准备

1. 使用带公网 IPv4 的 Debian 或 Ubuntu VPS，以 root 身份执行。
2. 在云服务商安全组中放行准备使用的 TCP 端口。若使用系统防火墙，也需放行该端口。
3. 选择端口时直接回车使用 TCP 443；若已占用，脚本会提示重新输入其他端口（例如 8443）。
4. 安装时伪装域名直接回车，会默认选实测延迟最低的域名；也可以手动输入一个支持 TLS 1.3 的域名。自动优选从脚本内的 68 个候选域名并发初筛，跳过证书或 TLS 1.3 验证失败的站点，再复测全部通过初筛的域名，选两次握手平均耗时最低的站点。这个耗时是 **VPS 到伪装站点** 的耗时，不是客户端到 VPS 的延迟。若候选全部不可用，请手动指定域名。

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

## 非交互安装

参数顺序为端口、伪装域名、节点名称：

```bash
/root/vless-reality-setup.sh install 443 www.amazon.com Reality-SG
```

需要自动优选 SNI 时，将第二个参数改为 `auto`：

```bash
/root/vless-reality-setup.sh install 443 auto Reality-SG
```

## 常用命令

```text
vless-reality show                 显示 vless:// 导入链接
vless-reality status               检查服务、配置、端口和伪装站点
vless-reality port 8443            修改监听端口
vless-reality sni www.apple.com    修改 REALITY 伪装域名
vless-reality sni auto             重新测量并优选伪装域名
vless-reality uuid                 重新生成 UUID
vless-reality rotate-keys          轮换 REALITY 密钥和 Short ID
vless-reality rename Reality-US    修改节点名称
vless-reality refresh-ip           刷新链接中的公网 IPv4
vless-reality update               升级 Xray-core
vless-reality log -f               实时查看日志
vless-reality uninstall            卸载并清理
```

卸载会先停止并禁用本脚本创建的 Xray 服务，然后删除程序、配置、安装记录、节点链接、管理脚本、快捷命令、配置备份和可识别的中断临时文件，最后核验服务与专用账号是否仍存在。任一步失败会报错，并尽可能保留安装记录，便于修正问题后重试。

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
