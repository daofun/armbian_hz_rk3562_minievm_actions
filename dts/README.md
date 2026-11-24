# 板级设备树

把 HZ-RK3562 MiniEVM 的**板级**设备树放在这里（Linux 换行 LF）：

- `hzhy_rk3562_mini.dts`
- `hzhy_rk3562_mini.dtsi`
- `HZ-MiniEVM_EXP.dtsi`
- 以及它们 `#include` 的其它板级文件

**不要**放 SoC 级文件（`rk3562.dtsi`、`rk3562-linux.dtsi`、`rk3562-rk809.dtsi`、`rk3562-pinctrl.dtsi` 等），
Rockchip 6.1 内核里已经有了，工作流遇到同名文件会直接报错。

工作流会把这里的文件加进 armbian/linux-rockchip 的 `arch/arm64/boot/dts/rockchip/`，
编译检查后生成内核补丁交给 Armbian。
