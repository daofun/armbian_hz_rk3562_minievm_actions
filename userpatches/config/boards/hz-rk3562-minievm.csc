# HZ-RK3562 MiniEVM — Rockchip RK3562
# Kernel: Armbian rk35xx "vendor" (Rockchip BSP 6.1, armbian/linux-rockchip) / "vendor-next" (6.12, experimental)
# U-Boot: vendor U-Boot from the HZ SDK (built by the workflow, written by the hook below)
BOARD_NAME="HZ-RK3562 MiniEVM"
BOARD_VENDOR="hzhy"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
KERNEL_TARGET="vendor,vendor-next"
KERNEL_TEST_TARGET="vendor"
BOOT_SOC="rk3562"
BOOT_SCENARIO="spl-blobs"
BOOT_FDT_FILE="${HZ_FDT:-rockchip/hzhy_rk3562_mini.dtb}"
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="no"
HAS_VIDEO_OUTPUT="yes"

# 在 family 配置之后执行（999 > rockchip64_common 的 900），覆盖 U-Boot / 串口 / 启动脚本
function post_family_config__999_hz_rk3562_overrides() {
	display_alert "${BOARD}" "use vendor U-Boot blobs, ttyFIQ0 115200 console" "info"
	declare -g BOOTCONFIG="none"
	# 厂家设备树把 fiq-debugger 设为 115200（hzhy_rk3562_mini.dtsi）
	declare -g SERIALCON="ttyFIQ0:115200"
	declare -g BOOTSCRIPT="boot-hz-rk3562.cmd:boot.cmd"

	# 工作流已把内核源码浅克隆到 userpatches/hz-kernel.git，改从本地拉取（避免 GitHub 增量拉取超时）
	local hz_local_kernel="${SRC}/userpatches/hz-kernel.git"
	if [[ -d "${hz_local_kernel}" ]]; then
		# 容器内是 root，仓库属主是 runner，放行 safe.directory
		git config --global --add safe.directory '*' || true
		declare -g KERNELSOURCE="file://${hz_local_kernel}"
		declare -g -i KERNEL_GIT_CACHE_TTL=0
		display_alert "${BOARD}" "kernel source from local mirror ${KERNELSOURCE} (${KERNELBRANCH})" "info"
	fi
}

# Armbian 的 linux-rk35xx-vendor.config 没有打开 CONFIG_CPU_RK3562（已核实），
# 不打开的话 RK3562 的时钟驱动和 VOP2 显示驱动都不会编译。
# CLK_RK3562 / ROCKCHIP_VOP2 依赖 CPU_RK3562 且默认 y，Armbian 随后会执行 olddefconfig。
function custom_kernel_config__hz_rk3562() {
	opts_y+=("CPU_RK3562" "CLK_RK3562" "ROCKCHIP_VOP2" "FIQ_DEBUGGER" "FIQ_DEBUGGER_CONSOLE" "FIQ_DEBUGGER_CONSOLE_DEFAULT_ENABLE")
	kernel_config_modifying_hashes+=("hz-rk3562: CPU_RK3562 CLK_RK3562 ROCKCHIP_VOP2 FIQ_DEBUGGER* =y")
	# RK3562 的 GPU 是 Mali-G52（Bifrost）。开源驱动 panfrost 在厂家 6.1 内核上给 GPU 上电时
	# 触发 "failed to get ack on domain 'gpu'" -> Kernel panic。关掉 panfrost，改用 Rockchip 的 bifrost 驱动。
	opts_n+=("DRM_PANFROST")
	# Rockchip Mali Bifrost 驱动（bifrost_kbase.ko）。
	# 上次编译报 kbase_platform_rk_* 隐式声明：这几个函数只在 platform/rk/mali_kbase_config_platform.h 里声明，
	# 说明编译时没用上 rk 平台目录（MALI_PLATFORM_NAME 不是 rk）。这里直接用 --set-str 写入 rk，
	# 并打印最终值，方便在日志里核对。
	opts_m+=("MALI_BIFROST")
	opts_y+=("MALI_BIFROST_DEVFREQ")
	kernel_config_modifying_hashes+=("hz-rk3562: DRM_PANFROST=n MALI_BIFROST=m MALI_PLATFORM_NAME=rk")
	if [[ -f .config ]]; then
		# 先把 MALI_BIFROST 设为 m，MALI_PLATFORM_NAME 才在可配置范围内，再写字符串
		./scripts/config --module MALI_BIFROST --enable MALI_BIFROST_DEVFREQ
		./scripts/config --set-str MALI_PLATFORM_NAME rk
		display_alert "${BOARD}" "GPU: $(grep -E '^CONFIG_MALI_PLATFORM_NAME=' .config || echo 'MALI_PLATFORM_NAME 未设置')" "info"
	fi
}

# 镜像卸载前：写入厂家 idblock/uboot，安装 boot.scr，检查 dtb 与内核配置，兜底 armbianEnv/uInitrd
function pre_umount_final_image__hz_rk3562_vendor_boot() {
	local blobs="${SRC}/userpatches/hz-blobs"
	local bootdir="${MOUNT}/boot"

	[[ -f "${blobs}/idblock.bin" && -f "${blobs}/uboot.img" ]] ||
		exit_with_error "HZ-RK3562: ${blobs} 中缺少 idblock.bin / uboot.img"

	# uboot.img 写在 sector 16384 (8 MiB)，Armbian 根分区从 16 MiB 开始，最多 8 MiB
	local ub_size
	ub_size=$(stat -c %s "${blobs}/uboot.img")
	((ub_size <= 8 * 1024 * 1024)) || exit_with_error "HZ-RK3562: uboot.img (${ub_size} B) 超过 8 MiB，会覆盖根分区"

	display_alert "HZ-RK3562" "写入 idblock.bin@64 / uboot.img@16384 -> ${LOOP}" "info"
	dd if="${blobs}/idblock.bin" of="${LOOP}" seek=64 conv=notrunc,fsync status=none
	dd if="${blobs}/uboot.img" of="${LOOP}" seek=16384 conv=notrunc,fsync status=none

	# 启动脚本
	install -m 0644 "${SRC}/userpatches/bootscripts/boot-hz-rk3562.cmd" "${bootdir}/boot.cmd"
	sed -i "s#^setenv fdtfile .*#setenv fdtfile \"${BOOT_FDT_FILE}\"#" "${bootdir}/boot.cmd"
	mkimage -C none -A arm -T script -d "${bootdir}/boot.cmd" "${bootdir}/boot.scr" > /dev/null

	# 设备树必须存在
	[[ -f "${bootdir}/dtb/${BOOT_FDT_FILE}" ]] ||
		exit_with_error "HZ-RK3562: 镜像中没有 /boot/dtb/${BOOT_FDT_FILE}（检查 dts 补丁是否被应用）"

	# 内核配置检查
	local kcfg
	kcfg=$(ls -1 "${bootdir}"/config-* 2> /dev/null | tail -n1 || true)
	if [[ -n "${kcfg}" ]]; then
		grep -q '^CONFIG_CPU_RK3562=y' "${kcfg}" || exit_with_error "HZ-RK3562: 内核未启用 CONFIG_CPU_RK3562"
		grep -qE '^CONFIG_CLK_RK3562=[ym]' "${kcfg}" || exit_with_error "HZ-RK3562: 内核未启用 CONFIG_CLK_RK3562"
	fi

	# armbianEnv.txt 兜底
	local env="${bootdir}/armbianEnv.txt"
	touch "${env}"
	if grep -q '^fdtfile=' "${env}"; then
		sed -i "s#^fdtfile=.*#fdtfile=${BOOT_FDT_FILE}#" "${env}"
	else
		echo "fdtfile=${BOOT_FDT_FILE}" >> "${env}"
	fi
	grep -q '^verbosity=' "${env}" || echo "verbosity=1" >> "${env}"
	grep -q '^console=' "${env}" || echo "console=serial" >> "${env}"
	if ! grep -q '^rootdev=' "${env}"; then
		local rootsrc rootuuid
		rootsrc=$(findmnt -n -o SOURCE --target "${MOUNT}")
		rootuuid=$(blkid -s UUID -o value "${rootsrc}")
		echo "rootdev=UUID=${rootuuid}" >> "${env}"
	fi

	# uInitrd 兜底
	if [[ ! -e "${bootdir}/uInitrd" ]]; then
		local initrd
		initrd=$(ls -1 "${bootdir}"/initrd.img-* 2> /dev/null | tail -n1 || true)
		[[ -n "${initrd}" ]] && mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd -d "${initrd}" "${bootdir}/uInitrd" > /dev/null
	fi

	display_alert "HZ-RK3562" "armbianEnv.txt:" "info"
	cat "${env}"

	# 双保险：即使内核里还有 panfrost 模块，也不让它加载
	mkdir -p "${MOUNT}/etc/modprobe.d"
	cat > "${MOUNT}/etc/modprobe.d/hz-rk3562-gpu.conf" <<- 'EOF'
		# panfrost 给 GPU 上电会触发 Kernel panic，禁用
		blacklist panfrost
		# Rockchip Mali 驱动尚未在本板验证（可能和 panfrost 一样卡在 GPU 上电），先不自动加载。
		# 手动测试: sudo modprobe bifrost_kbase ；正常的话删掉下面这一行即可开机自动加载
		blacklist bifrost_kbase
	EOF


	# 厂家 U-Boot 2017.09 执行 boot.scr 失败（内容变乱码）。distro boot 会先找 extlinux.conf，
	# 找到就不再执行 boot.scr。这里生成 extlinux.conf，全部用实际文件路径（不走符号链接）。
	local kver rootuuid2
	kver=$(ls -1 "${bootdir}"/vmlinuz-* | sed 's#.*/vmlinuz-##' | sort -V | tail -n1)
	rootuuid2=$(grep '^rootdev=' "${env}" | head -n1 | cut -d= -f2-)
	[[ -n "${kver}" ]] || exit_with_error "HZ-RK3562: 找不到 /boot/vmlinuz-*"
	[[ -f "${bootdir}/dtb-${kver}/${BOOT_FDT_FILE}" ]] || exit_with_error "HZ-RK3562: 缺少 /boot/dtb-${kver}/${BOOT_FDT_FILE}"
	local initrd_line=""
	# extlinux 按原始数据加载 initrd，必须用不带 U-Boot 头的 initrd.img（uInitrd 只给 boot.scr/bootm 用）
	[[ -f "${bootdir}/initrd.img-${kver}" ]] && initrd_line="    initrd /boot/initrd.img-${kver}"
	mkdir -p "${bootdir}/extlinux"
	cat > "${bootdir}/extlinux/extlinux.conf" <<- EOF
		default armbian
		timeout 10
		menu title HZ-RK3562 MiniEVM

		label armbian
		    kernel /boot/vmlinuz-${kver}
		    fdt /boot/dtb-${kver}/${BOOT_FDT_FILE}
		${initrd_line}
		    append root=${rootuuid2} rootwait rootfstype=ext4 console=ttyFIQ0,115200 earlycon consoleblank=0 loglevel=7 cgroup_enable=memory swapaccount=1 modprobe.blacklist=panfrost
	EOF
	display_alert "HZ-RK3562" "extlinux.conf:" "info"
	cat "${bootdir}/extlinux/extlinux.conf"
}
