# U-Boot boot script for HZ-RK3562 MiniEVM (Armbian, vendor U-Boot + vendor kernel 5.10)
# 修改后重新生成:  mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr

setenv load_addr "0x09000000"
setenv overlay_error "false"
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "1"
setenv console "serial"
setenv bootlogo "false"
setenv rootfstype "ext4"
setenv earlycon "on"
setenv docker_optimizations "on"
setenv fdtfile "rockchip/hzhy_rk3562_mini.dtb"
setenv consoleargs "console=ttyFIQ0,115200"

echo "Boot script loaded from ${devtype} ${devnum}:${distro_bootpart}"

if test -e ${devtype} ${devnum}:${distro_bootpart} ${prefix}armbianEnv.txt; then
	load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}armbianEnv.txt
	env import -t ${load_addr} ${filesize}
fi

if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "${consoleargs} console=tty1"; fi
if test "${earlycon}" = "on"; then setenv consoleargs "earlycon ${consoleargs}"; fi
if test "${bootlogo}" = "true"; then
	setenv consoleargs "splash plymouth.ignore-serial-consoles ${consoleargs}"
else
	setenv consoleargs "splash=verbose ${consoleargs}"
fi

setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} consoleblank=0 loglevel=${verbosity} usb-storage.quirks=${usbstoragequirks} ${extraargs} ${extraboardargs}"
if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=memory swapaccount=1"; fi

load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} ${prefix}Image
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fdt addr ${fdt_addr_r}
fdt resize 65536

for overlay_file in ${user_overlays}; do
	if load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} ${prefix}overlay-user/${overlay_file}.dtbo; then
		echo "Applying user provided DT overlay ${overlay_file}.dtbo"
		fdt apply ${load_addr} || setenv overlay_error "true"
	fi
done
if test "${overlay_error}" = "true"; then
	echo "Error applying DT overlays, restoring original DT"
	load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${prefix}dtb/${fdtfile}
fi

booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
