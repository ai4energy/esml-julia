# esml-julia

《ESML 编译器》第二卷的公开参考实现。

**定位**：教学用最小实现，不是生产引擎。书里讲的每条主线都对应本仓的一段可运行代码；生产引擎的工程化部分不在本仓。

## 第 1 章最小链

```text
examples/decay.esml
  → parse_document (EzXML)
  → check_units (Unitful)
  → compile_model (Symbolics + ModelingToolkit)
  → simulate (OrdinaryDiffEq)
  → N(60) = 4.978...
```

## 运行

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. test/runtests.jl
```

或直接看结果：

```sh
julia --project=. -e '
using ESML
doc = parse_document("examples/decay.esml")
r = simulate(doc; saveat=60.0)
println("N(60) = ", final_state(r, "N"))
'
```

## 依赖

Unitful.jl（单位）· Symbolics.jl（符号表达式）· ModelingToolkit.jl（方程系统）· OrdinaryDiffEq.jl / DifferentialEquations.jl（数值求解）· EzXML.jl（文档解析）。

## 许可

MIT License（见 `LICENSE`）。

## 边界

本仓只实现书里需要的 subset，作为教学参考实现；不描述生产实现的内部细节。
