# Armbian RK3562 云端编译工作流

在 **GitHub Actions** 上为 **Rockchip RK3562** 开发板（HZHY-RK3562_EVB）编译
**Armbian Debian 13 (Trixie) Minimal** 固件，内核使用**最新主线**（edge 分支，Linux 7.2）。

无需本地编译环境，Fork 本仓库后点几下鼠标即可出固件。

---

## 1. 原厂固件分析结论

对本板原厂文件（`MiniLoaderAll.bin` / `uboot.img` / `boot.img`）的分析结果：

| 项目 | 结论 |
| --- | --- |
| SoC | Rockchip **RK3562**（4×Cortex-A53 + Mali-G52） |
| 原厂板型标识 | `evb_rk3562` / 内核串 `HZHY-RK3562_EVB Board` |
| 原厂内核 | Rockchip BSP **5.10.226**（Android bootimg 打包） |
| 原厂 U-Boot | Rockchip fork **2017.09**（FIT：ATF + OP-TEE + U-Boot） |
| DDR 固件 | Rockchip blob `ddr-v1.07`（支持 LP4/4x） |
| 调试串口 | **UART2**（`0xff680000`），惯例波特率 **1500000** 8n1 |
| 存储节点 | SD = `mmc0@ff870000`，eMMC = `mmc1@ff880000` |

> 原厂 U-Boot 阶段设备树的反编译结果见
> [`reference/hzhy-rk3562-evb-uboot.dts`](reference/hzhy-rk3562-evb-uboot.dts)，
> 是后续移植/核对外设（GPIO、I2C、SPI、显示等）的重要参考。

### 为什么这套方案可行

- Armbian 官方 `rk35xx` 家族**已支持 RK3562**（首款参考板 KICKPI K3B，
  主线 U-Boot v2026.07 + 纯主线内核）；
- 主线内核自带 Rockchip 官方 **`rk3562-evb2-v10.dtb`**（同为 RK3562 EVB 类硬件）；
- 主线 U-Boot 提供 `kickpi-k3b-rk3562_defconfig`（binman + rkbin DDR blob，
  与具体板子外设无关，同 SoC 可复用）。

## 2. 仓库结构

```
├── .github/workflows/build-armbian.yml   # GitHub Actions 编译工作流（核心）
├── board/hzhy-rk3562-evb.csc             # 自定义板级配置（构建时注入 armbian/build）
└── reference/hzhy-rk3562-evb-uboot.dts   # 原厂 U-Boot 设备树反编译参考
```

## 3. 快速上手（约 5 分钟配置 + 1~2 小时云端编译）

1. **上传仓库**：把本目录推送到你自己的 GitHub 账号
   （`git init && git add -A && git commit -m init`，再 `git remote add origin ... && git push`）；
2. **开权限**：仓库 `Settings → Actions → General → Workflow permissions`
   选择 **Read and write permissions**（发 Release 需要）；
3. **触发构建**：`Actions → Build Armbian (RK3562 · Debian 13 Trixie · Minimal)
   → Run workflow`，参数保持默认即可；
4. **下载固件**：构建完成后在运行记录底部的 **Artifacts** 下载
   `*.img.xz`（附 `*.sha` 校验）；勾选 `create_release` 时会同步发到 Releases；
5. **烧录**：用 Balena Etcher / Rufus / `xzcat *.img.xz | sudo dd of=/dev/sdX bs=1M status=progress`
   写入 TF 卡（或 USB 烧录到 eMMC），插卡上电。

### 构建参数说明

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `board` | `hzhy-rk3562-evb` | 目标板。`kickpi-k3b` 为官方同 SoC 参考板，可作对照 |
| `branch` | `edge` | **内核分支**：`edge` = 最新主线（7.2）；`vendor` = Rockchip BSP 6.1/6.12 |
| `release` | `trixie` | 发行版，**trixie = Debian 13** |
| `build_minimal` | `true` | Minimal 精简镜像（纯命令行、最小软件包集） |
| `armbian_repo` / `armbian_branch` | `armbian/build` / `main` | 深度定制时指向自己的 fork |
| `create_release` | `false` | 是否发布到仓库 Releases |

首次登录：用户名 `root`，密码 `1234`，系统会强制改密并引导创建普通用户。

## 4. 串口与首次启动注意

- **波特率 1500000**（8n1），不是常见的 115200；USB 转串口建议 CH343/CP2102/FT232
  （廉价 CH340 在 1.5Mbps 下可能乱码）；
- 当前内核设备树用的是主线官方 EVB2，调试口为 **UART0（ttyS0）**；
  而原厂固件走 **UART2**。因此：
  - 若板子引出了 UART0 → 直接看 UART0；
  - 若只有 UART2 → 串口可能无输出，但系统多半已正常启动，
    插网线后在路由器里找 `armbian` 主机名 SSH 登录即可；
  - 想完全匹配原板引脚，请按下节移植自己的 DTS。

## 5. 进阶定制（可选）

需要精确匹配板子外设（WiFi/BT 芯片、网口 PHY、摄像头、屏幕等）时：

1. **Fork [armbian/build](https://github.com/armbian/build)**，在
   `config/boards/` 下把本仓库的 `hzhy-rk3562-evb.csc` 提交进去；
2. 参照 `reference/hzhy-rk3562-evb-uboot.dts` 和主线
   `arch/arm64/boot/dts/rockchip/rk3562-evb2-v10.dts`，编写你自己的
   `rk3562-hzhy-evb.dts`（重点：`chosen/stdout-path` 改 `serial2:1500000n8`），
   以内核补丁形式提交到家族补丁目录；
3. 本仓库 `Run workflow` 时把 `armbian_repo` 改成 `你的用户名/build` 即可。

> 提示：原厂 Android boot.img 中的内核 DTB 存放在未提供的 `resource.img` 里。
> 如能拿到 `resource.img`（或整盘 `update.img`），可反编译出**完整**的原厂
> 内核设备树，移植外设会更省事。

## 6. 风险与说明

- 本项目交付的是**构建工作流与板级配置**，固件在 GitHub 云端编译，
  未经实板验证；RK3562 主线支持仍在快速演进，个别外设（GPU 加速、VPU、
  NPU、MIPI 摄像头/屏）在主线内核上可能尚不可用；
- `vendor` 分支（Rockchip BSP 6.1/6.12）外设支持通常更全，可作备选；
- 构建耗时约 1~2 小时（GitHub 免费 runner 4 vCPU/16GB），
  磁盘清理 + `/mnt` 数据盘 + ccache 缓存已配置好，失败重跑会明显提速；
- 工作流中留有每周一定时构建的注释（`schedule`），取消注释即可自动跟进最新内核。
