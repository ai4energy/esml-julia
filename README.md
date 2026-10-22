# esml-julia

《ESML 编译器》与《七类计算》的公开参考实现（MIT）。

**定位**：教学用最小实现，不是生产引擎。书里讲的每条主线都对应本仓的一段可运行代码；生产引擎的工程化部分不在本仓。

## 能力

- **编译链**：`parse_document`（EzXML）→ HIR → 单位/量纲检查 → 结构分析 → Symbolics → ModelingToolkit `ODESystem` → `ODEProblem` → SciML。
- **离散事件**：`simulate_with_reset` 用 `ContinuousCallback` 演示事件与复位。
- **代码生成**：`compile_rhs` 生成普通 Julia 函数，`sci_rhs` 提供 SciML 四参数接口。
- **任务层**：十种任务——七类问题类（simulate / sensitivity / estimation / optimize / control / surrogate / validation）+ 三个辅助任务（forecast / data / decision）。

## 运行

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
```

本版测试：**73 passed / 0 failed**。

单份算例：

```sh
julia --project=. -e '
using ESML
d = parse_document("examples/tasks/tasks-all.esml")
for r in run_tasks(d)
    println(r.kind)
end'
```

## 任务层

| kind | 输出 |
|---|---|
| simulate | 轨迹 |
| sensitivity | 加/减摄动两条轨迹 |
| estimation | 参数、SSE |
| optimize | 最优点、目标值、可行性 |
| control | 输入序列、状态轨迹 |
| surrogate | 多项式系数、R² |
| validation | R²、RMSE、MAE、bias、maxAbs、残差 |
| forecast | 拟合值、外推值 |
| data | 计数、极值、均值、标准差、中位数 |
| decision | 选中项、候选表 |

`examples/tasks/` 是《七类计算》（105 卷）算例的同源副本；书里的引擎后端结果与这里的参考实现结果在容差内一致。

## 依赖

EzXML.jl · Unitful.jl · Symbolics.jl · ModelingToolkit.jl · OrdinaryDiffEq.jl / DifferentialEquations.jl · Statistics / LinearAlgebra（标准库）。

## 许可

MIT License（版权 Ai4Energy，见 `LICENSE`）。

## 边界

本仓只实现书里需要的 subset，作为教学参考实现；不描述生产实现的内部细节。求解器内部（时间积分、线性代数、稀疏结构、并行调度）不在本仓范围。
