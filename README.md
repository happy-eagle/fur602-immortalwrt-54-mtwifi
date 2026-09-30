# HONOR FUR-602 / FUR-603 · ImmortalWrt 5.4 + 闭源 mtwifi 云编译

荣耀 FUR-602 / FUR-603（联通定制 XU50，与 XT50/XC50 同板型，**MT7981B**）的
**纯净版** ImmortalWrt 固件，通过 GitHub Actions 云编译。

| 项目 | 值 |
|---|---|
| 源码 | `hanwckf/immortalwrt-mt798x` @ `openwrt-21.02` |
| 目标 | **`mediatek/mt7981`** |
| 内核 | **5.4**（`KERNEL_PATCHVER:=5.4`） |
| 无线 | MTK 闭源 **`kmod-mt_wifi`**（mtwifi）+ `mtwifi-cfg` + `luci-app-mtwifi-cfg` |
| 主题 | **`luci-theme-design`**（首次启动自动设为默认，脚本 `files/etc/uci-defaults/99-luci-theme-design`） |
| 插件 | 无额外插件，仅 target/router 默认包（含 LuCI） |
| 镜像 | `factory.bin`（首次）/ `sysupgrade.bin`（升级） |

---

## ⚠️ 关于「mediatek-filogic」的说明

`mediatek/filogic` 这个子目标**只存在于 ImmortalWrt 24.10（内核 6.6）**，
它**没有 5.4 内核，也不带闭源 mtwifi**。

要同时满足 **5.4 内核 + mtwifi**，唯一对应的是 `mediatek/mt7981` 子目标
（hanwckf 的 `openwrt-21.02` 分支）。所以产物文件名是：

```
immortalwrt-<版本>-mediatek-mt7981-honor_fur-602-squashfs-factory.bin
immortalwrt-<版本>-mediatek-mt7981-honor_fur-602-squashfs-sysupgrade.bin
```

这与恩山/ixmu 教程里给出的文件名一致。若你其实要的是 6.6 + 开源 mt76，
那就该换 `immortalwrt/immortalwrt@openwrt-24.10`（见 schema12/honor-fur_602），
本仓库不适用。

---

## 一、云编译（GitHub Actions）

### 1. 建仓库并推送

```bash
cd fur602-immortalwrt-54-mtwifi
git init
git add -A
git commit -m "FUR-602: ImmortalWrt 5.4 + mtwifi cloud build"
git remote add origin https://github.com/<你的用户名>/fur602-immortalwrt-54-mtwifi.git
git branch -M main
git push -u origin main
```

> 若用 SSH 地址：`git@github.com:<用户名>/fur602-immortalwrt-54-mtwifi.git`

### 2. 触发编译

GitHub 仓库 → **Actions** → 允许 workflow → 左侧选
**Build ImmortalWrt 5.4 + mtwifi for HONOR FUR-602** → **Run workflow**。

可选填：

| 输入项 | 默认 | 说明 |
|---|---|---|
| `source_branch` | `openwrt-21.02` | 源码分支 |
| `device` | `honor_fur-602` | 设备 profile（`honor_fur-603` 同板型亦可用） |
| `extra_packages` | 空 | 想加包就填包名，如 `kmod-mediatek_hnat kmod-warp tcpdump` |
| `enable_ccache` | true | 二次编译加速 |

耗时通常 **2~4 小时**。完成后在 **Summary → Artifacts** 下载
`fur602-immortalwrt-5.4-mtwifi-<run#>`。

### 3. 编译内置的校验

工作流会在编译**前**断言：内核为 5.4、目标为 `mediatek/mt7981`、设备定义存在、
`kmod-mt_wifi` 已启用、且**未**启用开源 mt76；编译**后**断言
`factory.bin` / `sysupgrade.bin` 均已产出。任一步失败立即终止，不会产出半成品。

---

## 二、刷机硬性前提

### 1. 必须先刷入定制 U-Boot

原厂 U-Boot 校验镜像签名，**无法直接刷**第三方固件。需先刷
[hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) 的
`mt7981_honor_fur-602`（推荐 `fip-fixed-parts-multi-layout` 版）。

开 SSH（原厂固件）：访问
`http://192.168.101.1/cgi-bin/luci/api/system/cus_telnet` 开启 telnet，
在 `http://192.168.101.1/cgi-bin/luci/admin/mtk/console` 执行 `passwd -d root`。

然后上传 U-Boot 到 `/root` 并写入：

```bash
mtd write mt7981_honor_fur-602-fip-fixed-parts-multi-layout.bin FIP
```

> **强烈建议先用 `cat /proc/mtd` + `dd | nc` 备份全部分区**（尤其 Factory，
> WiFi 校准数据在里面，擦了 WiFi 就废了）。

### 2. 必须切换分区布局为 `expand(114m)`

U-Boot 内置两套布局，默认 `default`（ubi 仅 64 MiB）。
本设备 `IMAGE_SIZE = 116736k`（114 MiB），**只适配 `expand(114m)`**。

U-Boot 里执行（或刷 multi-layout 版 U-Boot 后交互选择）：

```
setenv mtd_layout_label "expand(114m)"
saveenv
```

未切换直接刷会导致 UBI 溢出 / 无法启动。

---

## 三、刷机

1. 电脑设 `192.168.10.x`（或 U-Boot 自动 DHCP）。
2. 断电 → 按住 **Reset** → 上电 → 灯变绿松手，进 U-Boot Web 恢复页（`192.168.1.1`）。
3. 上传 `...-honor_fur-602-squashfs-factory.bin` → Update → 等 1~2 分钟重启。
4. 首次登录 `192.168.1.1`，root / 空密码。
5. 后续升级用 `sysupgrade.bin`（LuCI 或 `sysupgrade`，可保留配置）。

**WiFi 配置**：闭源 mtwifi 不走标准无线页，用 LuCI 里的
**网络 → MTK WiFi（luci-app-mtwifi-cfg）** 配置 2.4G / 5G。

---

## 四、关于 luci-theme-design

官方 21.02 的 luci feed 里**没有** Design 主题，所以工作流在 `feeds install` 之后
从 `gngpp/luci-theme-design` 外挂克隆到 `package/luci-theme-design`，再走正常打包。
该主题 `LUCI_DEPENDS` 为空，静态资源路径 `/luci-static/design`。

首启时 `files/etc/uci-defaults/99-luci-theme-design` 会执行：

```sh
uci set luci.main.mediaurlbase=/luci-static/design
uci commit luci
```

所以开机进 LuCI 就是 Design 主题。想换回 bootstrap 的话，在触发 workflow 时把
`theme` 留空即可（`theme_repo` 也随之忽略）。

## 五、想加东西怎么办

编辑 `config/fur602-mt7981-5.4-mtwifi.config`，追加
`CONFIG_PACKAGE_<包名>=y` 即可；或在触发 workflow 时填 `extra_packages`。

常用的几个（默认都没开，保持纯净）：

| 包名 | 作用 |
|---|---|
| `kmod-mediatek_hnat` | MTK 硬件 NAT 加速 |
| `kmod-warp` | MTK WARP/WED 无线硬件加速 |
| `kmod-ipt-offload` `kmod-nf-flow` | 软件 flow offload |
| `kmod-sched-cake` `sqm-scripts` | SQM QoS |
| `luci-app-upnp` `miniupnpd` | UPnP |
| `tcpdump` `htop` `nano` | 调试工具 |

---

## 六、本地 Linux 编译（可选）

```bash
git clone --depth=1 -b openwrt-21.02 https://github.com/hanwckf/immortalwrt-mt798x.git
cd immortalwrt-mt798x
./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/fur602-mt7981-5.4-mtwifi.config .config
make defconfig
make -j$(nproc) download
make -j$(nproc)
# 产物：bin/targets/mediatek/mt7981/
```

需要 Ubuntu 20.04/22.04 + 25GB 磁盘，且**不要用 root**、路径不能有空格。

---

## 参考

- [hanwckf/immortalwrt-mt798x](https://github.com/hanwckf/immortalwrt-mt798x) — 源码（5.4 + mtwifi 参考实现）
- [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x) — FUR-602 定制 U-Boot
- [schema12/honor-fur_602](https://github.com/schema12/honor-fur_602) — 24.10 / 6.6 / 开源 mt76 路线（本仓库的对照方案）
- <https://www.ixmu.net/200.html> — 免拆开 SSH、刷 U-Boot、刷 ImmortalWrt 图文教程
- <https://www.right.com.cn/forum/thread-8490266-1-1.html> — FUR-602 固件合集与 DTS

> 刷机有风险，务必先备份 Factory 分区。
