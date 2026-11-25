#!/usr/bin/env bash
# 在 Linux 或 WSL2 中运行（SDK 建议放在 ext4 内，如 ~/sdk，不要放 /mnt/d）
#   1) 生成 rk3562-uboot 仓库（u-boot/ + rkbin/）
#   2) 把厂家板级设备树复制到本工作流仓库的 dts/ 目录
# 用法: ./scripts/prepare-bsp-repos.sh <SDK目录> <GitHub用户名> [输出目录]
set -euo pipefail

SDK=$(realpath "$1")
OWNER=$2
OUT=$(realpath -m "${3:-$HOME/hz-bsp-repos}")
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"

case "$SDK" in /mnt/*) echo "警告: SDK 位于 Windows 盘（$SDK），可执行位/符号链接可能已损坏，建议在 ~/ 下重新解压" ;; esac

command -v git > /dev/null || { echo "错误: 没有 git，请先运行: sudo apt update && sudo apt install -y git"; exit 1; }
[ -d "${SDK}/u-boot" ] || { echo "错误: ${SDK}/u-boot 不存在"; exit 1; }
[ -d "${SDK}/rkbin" ] || { echo "错误: ${SDK}/rkbin 不存在"; exit 1; }

# 复制目录（排除 .git）。优先 rsync，没有就用 tar
copy_tree() {
	local src=$1 dst=$2
	rm -rf "$dst"
	mkdir -p "$dst"
	if command -v rsync > /dev/null; then
		rsync -a --exclude='.git' "${src}/" "${dst}/"
	else
		(cd "$src" && tar --exclude='./.git' -cf - .) | (cd "$dst" && tar -xf -)
	fi
}

echo "== U-Boot + rkbin =="
mkdir -p "${OUT}/rk3562-uboot"
echo "  复制 u-boot ..."
copy_tree "${SDK}/u-boot" "${OUT}/rk3562-uboot/u-boot"
echo "  复制 rkbin ..."
copy_tree "${SDK}/rkbin" "${OUT}/rk3562-uboot/rkbin"
cd "${OUT}/rk3562-uboot"
(cd u-boot && make distclean > /dev/null 2>&1 || true)
rm -f u-boot/*.img u-boot/*.bin u-boot/*.elf 2> /dev/null || true
big=$(find . -type f -size +95M)
[ -z "$big" ] || { echo "以下文件超过 GitHub 100MB 限制，请删除:"; echo "$big"; exit 1; }
rm -rf .git
git init -q -b main
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-$OWNER}" -c user.email="${GIT_AUTHOR_EMAIL:-${OWNER}@users.noreply.github.com}" \
	commit -q -m "HZ-RK3562 SDK u-boot + rkbin"
git remote add origin "https://github.com/${OWNER}/rk3562-uboot.git"

echo "== 板级设备树 -> ${REPO_ROOT}/dts =="
KDTS="${SDK}/kernel-5.10/arch/arm64/boot/dts/rockchip"
[ -d "$KDTS" ] || KDTS="${SDK}/kernel/arch/arm64/boot/dts/rockchip"
mkdir -p "${REPO_ROOT}/dts"
for f in hzhy_rk3562_mini.dts hzhy_rk3562_mini.dtsi HZ-MiniEVM_EXP.dtsi; do
	if [ -f "${REPO_ROOT}/dts/$f" ]; then
		echo "  保留已移植到 6.1 的 dts/$f（不用 SDK 5.10 原版覆盖）"
	elif [ -f "${KDTS}/$f" ]; then
		sed 's/\r$//' "${KDTS}/$f" > "${REPO_ROOT}/dts/$f"
		echo "  已复制 $f"
	else
		echo "  未找到 $f（跳过）"
	fi
done
echo "  这些文件 #include 的其它非 rk3562*.dtsi 板级文件也要一并放进 dts/："
grep -hoE '#include "[^"]+"' "${REPO_ROOT}"/dts/* 2> /dev/null | sort -u | sed 's/^/    /' || true

cat << EOF

完成。
1) 在 GitHub 新建空仓库 ${OWNER}/rk3562-uboot，然后:
     cd ${OUT}/rk3562-uboot && git push -u origin main
2) 把 ${REPO_ROOT}/dts/ 提交到工作流仓库，在 Actions 中运行工作流。
   dts-patch 任务会在 Rockchip 6.1 内核上编译检查设备树，报错按提示修改即可。
EOF
