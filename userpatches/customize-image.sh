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

# 可选：国内镜像 / 时区 / 额外软件包
# sed -i 's#http://deb.debian.org#https://mirrors.tuna.tsinghua.edu.cn#g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true
# ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo "Asia/Shanghai" > /etc/timezone
# apt-get update && apt-get install -y --no-install-recommends i2c-tools can-utils
