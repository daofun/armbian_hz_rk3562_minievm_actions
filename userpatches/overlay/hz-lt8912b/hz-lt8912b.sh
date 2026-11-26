#!/bin/bash
# HZ-RK3562 MiniEVM: LT8912B MIPI-DSI -> HDMI 初始化（1080p60）
# 寄存器序列逐条移植自厂家 U-Boot: u-boot/drivers/video/drm/lt8912b.c 的 lt8912b_setup()
# 前提：内核已把 DSI 以 1920x1080@60 输出（设备树里的 simple-panel-dsi），本脚本只配置 LT8912B。
#
# 用法: hz-lt8912b.sh [init|status]
set -u

BUS=${LT_BUS:-2}            # i2c2
A1=0x48; A2=0x49; A3=0x4a   # LT8912B 三个 I2C 地址
RST_CHIP=${LT_RST_CHIP:-gpiochip3}
RST_LINE=${LT_RST_LINE:-24} # GPIO3_D0 = 3*32 + 3*8 + 0 -> gpiochip3 第 24 脚（低有效）

log() { echo "hz-lt8912b: $*"; command -v logger >/dev/null && logger -t hz-lt8912b "$*"; }
w() { i2cset -y -f "$BUS" "$1" "$2" "$3" 2>/dev/null || log "写失败 $1 reg $2"; }
r() { i2cget -y -f "$BUS" "$1" "$2" 2>/dev/null || echo "ERR"; }
ms() { sleep "$(awk "BEGIN{print $1/1000}")"; }

gpio_out() { # $1 = 0/1；v2 用 -z 常驻保持电平，v1 用 --mode=exit
	# 结束之前占着该引脚的 gpioset，并等它真正退出，否则会 "Device or resource busy"
	pkill -f "gpioset.*${RST_CHIP}.*${RST_LINE}=" 2>/dev/null
	for _ in $(seq 1 20); do
		pgrep -f "gpioset.*${RST_CHIP}.*${RST_LINE}=" >/dev/null || break
		sleep 0.1
	done
	if gpioset --version 2>/dev/null | grep -q 'v2'; then
		gpioset -z -c "$RST_CHIP" "${RST_LINE}=$1"
	else
		gpioset --mode=exit "$RST_CHIP" "${RST_LINE}=$1"
	fi
}

reset_chip() {
	if command -v gpioset >/dev/null; then
		gpio_out 0; ms 100     # 拉低复位
		gpio_out 1; ms 200     # 释放复位
	else
		log "没有 gpioset（apt install gpiod），跳过硬件复位"
	fi
}

wait_dsi() { # 等 DRM 把 DSI 打开，最多 30 秒
	for _ in $(seq 1 30); do
		for f in /sys/class/drm/card*-DSI-*/enabled; do
			[ -f "$f" ] && grep -q enabled "$f" && return 0
		done
		sleep 1
	done
	log "等待 DSI 超时，继续初始化"
}

DigitalClockEn() { w $A1 0x02 0xf7; w $A1 0x08 0xff; w $A1 0x09 0xff; w $A1 0x0a 0xff; w $A1 0x0b 0x7c; w $A1 0x0c 0xff; }
TxAnalog()       { w $A1 0x31 0xe1; w $A1 0x32 0xe1; w $A1 0x33 0x0c; w $A1 0x37 0x00; w $A1 0x38 0x22; w $A1 0x60 0x82; }
CbusAnalog()     { w $A1 0x39 0x45; w $A1 0x3a 0x00; w $A1 0x3b 0x00; }
HDMIPllAnalog()  { w $A1 0x44 0x31; w $A1 0x55 0x44; w $A1 0x57 0x01; w $A1 0x5a 0x02; }
MipiAnalog()     { w $A1 0x3e 0xd6; w $A1 0x3f 0xd4; w $A1 0x41 0x3c; }
MipiBasicSet()   { w $A2 0x10 0x01; w $A2 0x11 0x08; w $A2 0x13 0x00; w $A2 0x14 0x00; w $A2 0x15 0x00; w $A2 0x1a 0x03; w $A2 0x1b 0x03; }
AudioIIsEn()     { w $A1 0xb2 0x01; w $A3 0x06 0x08; w $A3 0x07 0xf0; w $A3 0x34 0xd2; }
AviInfoframe()   { # 1080P60 16:9, VIC 16
	w $A3 0x3c 0x41
	w $A1 0xab 0x03
	w $A3 0x43 0x27; w $A3 0x44 0x10; w $A3 0x45 0x28; w $A3 0x46 0x00; w $A3 0x47 0x10
}
DDSConfig() {
	w $A2 0x4e 0xaa; w $A2 0x4f 0xaa; w $A2 0x50 0x6a; w $A2 0x51 0x80
	w $A2 0x1e 0x4f; w $A2 0x1f 0x5e; w $A2 0x20 0x01; w $A2 0x21 0x2c; w $A2 0x22 0x01
	w $A2 0x23 0xfa; w $A2 0x24 0x00; w $A2 0x25 0xc8; w $A2 0x26 0x00; w $A2 0x27 0x5e
	w $A2 0x28 0x01; w $A2 0x29 0x2c; w $A2 0x2a 0x01; w $A2 0x2b 0xfa; w $A2 0x2c 0x00
	w $A2 0x2d 0xc8; w $A2 0x2e 0x00; w $A2 0x42 0x64; w $A2 0x43 0x00; w $A2 0x44 0x04
	w $A2 0x45 0x00; w $A2 0x46 0x59; w $A2 0x47 0x00; w $A2 0x48 0xf2; w $A2 0x49 0x06
	w $A2 0x4a 0x00; w $A2 0x4b 0x72; w $A2 0x4c 0x45; w $A2 0x4d 0x00; w $A2 0x52 0x08
	w $A2 0x53 0x00; w $A2 0x54 0xb2; w $A2 0x55 0x00; w $A2 0x56 0xe4; w $A2 0x57 0x0d
	w $A2 0x58 0x00; w $A2 0x59 0xe4; w $A2 0x5a 0x8a; w $A2 0x5b 0x00; w $A2 0x5c 0x34
	w $A2 0x51 0x00
}
MIPI_Video_1080p() { # hfp88 hs44 hbp148 hact1920 htotal2200 vfp4 vs5 vbp36 vact1080 vtotal1125
	w $A2 0x18 0x2c; w $A2 0x19 0x05
	w $A2 0x1c 0x80; w $A2 0x1d 0x07
	w $A2 0x2f 0x0c
	w $A2 0x34 0x98; w $A2 0x35 0x08
	w $A2 0x36 0x65; w $A2 0x37 0x04
	w $A2 0x38 0x24; w $A2 0x39 0x00
	w $A2 0x3a 0x04; w $A2 0x3b 0x00
	w $A2 0x3c 0x94; w $A2 0x3d 0x00
	w $A2 0x3e 0x58; w $A2 0x3f 0x00
}
MIPIRxLogicRes() { w $A1 0x03 0x7f; ms 10; w $A1 0x03 0xff; w $A1 0x05 0xfb; ms 10; w $A1 0x05 0xff; }
HdmiOutputOn()   { w $A1 0x33 0x0e; }

status() {
	echo "chip id : $(r $A1 0x00) $(r $A1 0x01)   (应为 0x12 0xb2)"
	local hpd; hpd=$(r $A1 0xc1)
	echo "HPD     : $hpd   (bit7=1 表示插着 HDMI)"
	echo "MIPI in : hsync $(r $A1 0x9d)$(r $A1 0x9c | sed 's/0x//')  vsync $(r $A1 0x9f)$(r $A1 0x9e | sed 's/0x//')   (1080p 时 vsync 约 0x0465)"
	echo "DDS     : $(r $A2 0x0c) $(r $A2 0x0d) $(r $A2 0x0e) $(r $A2 0x0f)   (稳定时第3个约 0xd2)"
}

init() {
	command -v i2cset >/dev/null || { log "缺少 i2c-tools（apt install i2c-tools）"; exit 1; }
	[ -e "/dev/i2c-$BUS" ] || modprobe i2c-dev 2>/dev/null
	[ -e "/dev/i2c-$BUS" ] || { log "/dev/i2c-$BUS 不存在"; exit 1; }
	wait_dsi
	local id0 id1
	id0=$(r $A1 0x00)
	if [ "$id0" = "ERR" ] || [ "${LT_FORCE_RESET:-0}" = 1 ]; then
		# 芯片没应答（或强制）才做硬件复位；正常情况下 U-Boot/上电后芯片已不在复位状态
		log "芯片无应答，执行硬件复位"
		reset_chip
		id0=$(r $A1 0x00)
	else
		log "芯片已应答，跳过硬件复位"
	fi
	id1=$(r $A1 0x01)
	if [ "$id0" = "ERR" ]; then
		log "i2c-$BUS 地址 $A1 无应答：LT8912B 不在这一路 I2C 上、未上电或仍在复位"
		exit 1
	fi
	log "chip id $id0 $id1"

	DigitalClockEn; TxAnalog; CbusAnalog; HDMIPllAnalog; AudioIIsEn; AviInfoframe
	DigitalClockEn; TxAnalog; CbusAnalog; HDMIPllAnalog
	MipiAnalog; MipiBasicSet; DDSConfig; MIPI_Video_1080p
	AudioIIsEn; AviInfoframe
	MIPIRxLogicRes
	HdmiOutputOn
	log "初始化完成（1080p60）"
	status
}

case "${1:-init}" in
	init) init ;;
	status) status ;;
	*) echo "用法: $0 [init|status]"; exit 2 ;;
esac
