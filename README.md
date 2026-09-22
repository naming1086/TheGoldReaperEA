# The Gold Reaper EA - 反编译重构工程

## 目录结构

- `MQL4/GoldReaper/The Gold Reaper v4.5.mq4` - 原版 MQL4 源码（保留用于对照）。
- `MQL5/Experts/GoldReaper/The Gold Reaper English MT5.mq5` - 基于 V4.6 转储/JIT 重建的单文件 MQL5 版本（内置 MQL4 兼容层）。
- `Presets/` - 预设参数（*.set）与相关链接。

## MQL5 版本重构状态（批次1-21，已完成）

- **编号式反编译名清零**：`local_*` / `temp_n_*` / `arg_0_*` / `global_*` 等反编译器生成名全部语义化重命名（全局 `g_` 前缀 298 个，局部变量按函数语义命名）。
- **结构去重**：9 个仅常量不同的策略调度块去重为 `RunStrategySlot(strategyIndex,newH1Bar)`；OnTick 拆分为语义模块（余额跟踪 / GMT+DST / NFP 缓存 / 频率档位 / 换日闸门等），语句顺序与原版一致。
- **乱码修复**：37 行 GBK 双重编码注释已还原。
- **死代码清理**：死赋值（如 `local_1_double`）、死声明（如 `temp_string_114`）经三重验证后删除。

## 静态验证（每批次执行）

1. token 计数前后核对（目标残留 = 0）；
2. 行数不变（纯重命名）或 diff 仅删除（死代码）；
3. 花括号配平；全文件合法 UTF-8。

当前状态：121 个函数全部有引用、298 个全局变量全部有引用、括号配平（URL 字符串内的 `//` 非注释）。

## 编译验证（已完成）

MetaEditor 5.0.0.6182（build 6182，X64 Regular）实机编译结果：

```
Result: 0 errors, 0 warnings, 4532 ms elapsed, cpu='X64 Regular'
```

- 编译产物 `.ex5` 正常生成，说明重构后的 MQL5 源码在语法、类型、符号引用层面均通过官方编译器校验。
- 非 ASCII 字符仅存在于注释区（187 行），代码区与字符串字面量 0 处，不影响编译与运行时输出。

## 待办（需在 MetaTrader 5 中进行）

- Strategy Tester 与 V4.6 原版差分回测对照。

> 注意：账户需支持 **Hedging**（对冲）模式。
