# 代码生成层：符号方程 → 普通 Julia 函数（第 11 章）
#
# 这一层输出的是「函数 + 顺序 + 契约」，不是二进制，也不是性能优化。
# 参考实现用 Symbolics.build_function 生成就地与非就地两个版本；
# 读者可以把生成的函数直接交给 SciML，而不必经过本模块。

struct CompiledRHS
    f::Any
    f!::Any
    states::Vector{String}
    params::Vector{String}
end

function _symbol_name(x)
    String(ModelingToolkit.getname(x))
end

function compile_rhs(doc::Document)
    c = compile_model(doc)
    eqs = ModelingToolkit.equations(c.sys)
    us = ModelingToolkit.unknowns(c.sys)
    ps = ModelingToolkit.parameters(c.sys)
    rhs = [eq.rhs for eq in eqs]
    f, f! = Symbolics.build_function(rhs, us, ps; expression=Val(false))
    CompiledRHS(f, f!, [_symbol_name(x) for x in us], [_symbol_name(x) for x in ps])
end

"按编译产物声明的顺序，从名字到数值的字典里取向量。"
function rhs_inputs(c::CompiledRHS, values::AbstractDict)
    ([values[n] for n in c.states], [values[n] for n in c.params])
end

"在给定状态与参数下求右端项；返回普通向量。"
function rhs_at(c::CompiledRHS, u::AbstractVector, p::AbstractVector)
    c.f(u, p)
end

"就地求右端项；把结果写进 out。"
function rhs_at!(out::AbstractVector, c::CompiledRHS, u::AbstractVector, p::AbstractVector)
    c.f!(out, u, p)
    out
end

"""
把三参数的就地函数包装成 SciML 的四参数签名。

SciML 按「参数个数」判断就地/非就地：`f(du,u,p)` 会被误判成
非就地函数，从而静默算出错误结果。包装一层四参数函数，
接口契约才明确；接错时必须靠对拍发现，不能靠类型系统。
"""
function sci_rhs(c::CompiledRHS)
    (du, u, p, t) -> (c.f!(du, u, p); nothing)
end
