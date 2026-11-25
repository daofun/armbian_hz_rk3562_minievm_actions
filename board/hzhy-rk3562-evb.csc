# =============================================================================
# HZHY-RK3562_EVB 板级配置（社区支持 .csc —— 无官方维护者，自行验证）
#
# 硬件事实（来自原厂固件分析）：
#   - SoC      : Rockchip RK3562（四核 Cortex-A53 + Mali-G52）
#   - 原厂板型 : evb_rk3562 / "HZHY-RK3562_EVB Board"
#   - 调试串口 : UART2 (0xff680000)，Rockchip 惯例 1500000 8n1
#   - 存储     : SD (mmc0/ff870000) + eMMC (mmc1/ff880000)
#
# 软件选型：
#   - 内核     : edge 分支 = 最新主线（rk35xx 家族 edge 无私有补丁，
#                纯 mainline，含 rk3562-evb2-v10.dtb）
#   - U-Boot   : 主线 v2026.07 + binman 打包（沿用 KICKPI K3B 方案，
#                K3B 是 Armbian 官方支持的首款 RK3562 板，同 SoC）
#
# 注意：内核 DTB 使用主线官方 Rockchip EVB2（调试口为 UART0/ttyS0）。
# 若你的板子只引出了 UART2，首次启动时串口可能无输出 —— 系统大概率
# 仍在正常运行，可通过网线 SSH 登录验证，或按 README「进阶定制」
# 换成自己移植的 DTS。
# =============================================================================

BOARD_NAME="HZHY RK3562 EVB"
BOARD_VENDOR="hzhy"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2026"

# 只启用 edge（最新主线内核）；vendor 分支为 Rockchip BSP 6.1/6.12，备选
KERNEL_TARGET="edge,vendor"
KERNEL_TEST_TARGET="edge"

# 主线内核自带的 Rockchip 官方 EVB2 设备树（同为 RK3562 EVB 类硬件）
BOOT_FDT_FILE="rockchip/rk3562-evb2-v10.dtb"

# 主线 U-Boot + binman 打包方式（GPT 分区表，SD/eMMC 通用镜像）
BOOT_SCENARIO="binman"
BOOT_SOC="rk3562"
IMAGE_PARTITION_TABLE="gpt"
SERIALCON="ttyS0"

function post_family_config__hzhy-rk3562-evb() {
	# 启动脚本与串口控制台：ttyS0（对应主线 EVB2 DTS 的 stdout-path）
	declare -g BOOTSCRIPT='boot-rockchip64-ttyS0.cmd:boot.cmd'
	declare -g DEFAULT_OVERLAYS=""

	display_alert "${BOARD}" "mainline u-boot overrides (via kickpi-k3b defconfig)" "info"

	# U-Boot：主线 v2026.07，复用 KICKPI K3B 的 RK3562 defconfig
	# （同 SoC，binman + rkbin DDR blob，与具体板子的外设无关）
	declare -g BOOTCONFIG="kickpi-k3b-rk3562_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
}
