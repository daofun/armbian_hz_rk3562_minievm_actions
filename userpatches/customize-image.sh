#!/bin/bash
# Armbian 在 chroot 中调用: customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP $ARCH
RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

set -e
echo ">>> HZ-RK3562 customize-image: RELEASE=${RELEASE} FAMILY=${LINUXFAMILY} BOARD=${BOARD}"

# fiq-debugger 串口登录
systemctl enable serial-getty@ttyFIQ0.service || true

# LT8912B MIPI->HDMI：开机用 I2C 写厂家 U-Boot 的 1080p 初始化序列
# Armbian 把 userpatches/overlay 挂载到 chroot 的 /tmp/overlay
if [ -f /tmp/overlay/hz-lt8912b/hz-lt8912b.sh ]; then
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends i2c-tools gpiod
	install -m 0755 /tmp/overlay/hz-lt8912b/hz-lt8912b.sh /usr/local/sbin/hz-lt8912b.sh
	install -m 0644 /tmp/overlay/hz-lt8912b/hz-lt8912b.service /etc/systemd/system/hz-lt8912b.service
	echo i2c-dev > /etc/modules-load.d/i2c-dev.conf
	systemctl enable hz-lt8912b.service
	echo ">>> hz-lt8912b.service installed"
else
	echo ">>> WARNING: /tmp/overlay/hz-lt8912b 不存在，跳过 HDMI 初始化服务"
fi

# 可选：国内镜像 / 时区 / 额外软件包
# sed -i 's#http://deb.debian.org#https://mirrors.tuna.tsinghua.edu.cn#g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true
# ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone
# apt-get update && apt-get install -y --no-install-recommends i2c-tools can-utils
