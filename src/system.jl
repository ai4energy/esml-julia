# 系统层：Document → 符号方程 → ModelingToolkit 系统
#
# 这里只做第 1 章需要的 subset：状态、参数、D(x)、四则运算。
# 第 2 章以后在同一层上加 HIR、连接与结构分析。

function _state_variable(name::AbstractString)
    s = Symbol(name)
    Core.eval(@__MODULE__, :(only(ModelingToolkit.@variables $(s)(_T))))
end

function _param_variable(name::AbstractString)
    s = Symbol(name)
    Core.eval(@__MODULE__, :(only(ModelingToolkit.@parameters $(s))))
end

function compile_model(doc::Document)
    t = _T
    states = Dict{String, Any}()
    for s in doc.states
        states[s.name] = _state_variable(s.name)
    end
    algebraics = Dict{String, Any}()
    for a in doc.algebraics
        algebraics[a.name] = _state_variable(a.name)
    end
    allvars = merge(states, algebraics)
    params = Dict{String, Any}()
    for p in doc.params
        params[p.name] = _param_variable(p.name)
    end

    equations = Equation[]
    for text in doc.equations
        parts = split(text, "="; limit=2)
        length(parts) == 2 || error("equation must contain '=': $text")
        lhs = to_symbolic(parse_expr(strip(parts[1])), allvars, params, t)
        rhs = to_symbolic(parse_expr(strip(parts[2])), allvars, params, t)
        push!(equations, lhs ~ rhs)
    end

    sys = ODESystem(equations, t; name=:S)
    sys = structural_simplify(sys)
    (sys=sys, states=allvars, params=params, t=t)
end

# =============================================================================
# 纯代数稳态：无状态模型 → Newton
# =============================================================================
"""
    solve_steady(doc; tol=1e-10, maxiter=50) -> NamedTuple

纯代数模型（`doc.states` 为空、`doc.algebraics` 非空）的稳态解：
把每条方程写成残差 `lhs-rhs`，用 Symbolics 生成残差/Jacobian，
再做阻尼 Newton。教学用最小实现，不处理欠定/超定。
"""
function solve_steady(doc::Document; tol::Float64=1e-10, maxiter::Int=50)
    isempty(doc.algebraics) && error("solve_steady: 模型没有代数变量")
    isempty(doc.states) || error("solve_steady: 模型含状态变量，请用 simulate")
    vars = Dict{String, Any}(a.name => Symbolics.variable(Symbol(a.name)) for a in doc.algebraics)
    params = Dict{String, Any}(p.name => _param_variable(p.name) for p in doc.params)
    vlist = [vars[a.name] for a in doc.algebraics]
    plist = [params[p.name] for p in doc.params]
    eqs = Symbolics.Equation[]
    for text in doc.equations
        parts = split(text, "="; limit=2)
        length(parts) == 2 || error("equation must contain '=': $text")
        lhs = to_symbolic(parse_expr(strip(parts[1])), vars, params, _T)
        rhs = to_symbolic(parse_expr(strip(parts[2])), vars, params, _T)
        push!(eqs, lhs ~ rhs)
    end
    res = [e.lhs - e.rhs for e in eqs]
    jac = Symbolics.jacobian(res, vlist)
    f = Symbolics.build_function(res, vlist, plist; expression=Val(false))[1]
    jf = Symbolics.build_function(jac, vlist, plist; expression=Val(false))[1]
    x = Float64[a.initial for a in doc.algebraics]
    p = Float64[pp.default for pp in doc.params]
    iters = 0; rn = Inf
    for k in 1:maxiter
        iters = k
        r = Float64.(f(x, p)); J = Float64.(jf(x, p))
        rn = maximum(abs, r)
        rn < tol && break
        dx = -(J \ r)
        α = 1.0
        while α > 1e-4 && maximum(abs, Float64.(f(x .+ α .* dx, p))) >= rn
            α /= 2
        end
        x .+= α .* dx
    end
    return (values = Dict(a.name => x[i] for (i, a) in enumerate(doc.algebraics)),
            residual = rn, iterations = iters, converged = rn < tol)
end

"""
    build_residual(doc) -> NamedTuple

公开残差/Jacobian 契约（纯代数模型）：
`(names, pnames, u0, p0, residual, jacobian)`。
`residual(x,p)` 返回 `Vector{Float64}`，`jacobian(x,p)` 返回矩阵。
"""
function build_residual(doc::Document)
    isempty(doc.algebraics) && error("build_residual: 模型没有代数变量")
    isempty(doc.states) || error("build_residual: 纯代数接口不接收状态变量")
    vars = Dict{String, Any}(a.name => Symbolics.variable(Symbol(a.name)) for a in doc.algebraics)
    params = Dict{String, Any}(p.name => _param_variable(p.name) for p in doc.params)
    vlist = [vars[a.name] for a in doc.algebraics]
    plist = [params[p.name] for p in doc.params]
    res = Any[]
    for text in doc.equations
        parts = split(text, "="; limit=2)
        length(parts) == 2 || error("equation must contain '=': $text")
        lhs = to_symbolic(parse_expr(strip(parts[1])), vars, params, _T)
        rhs = to_symbolic(parse_expr(strip(parts[2])), vars, params, _T)
        push!(res, lhs - rhs)
    end
    jac = Symbolics.jacobian(res, vlist)
    f = Symbolics.build_function(res, vlist, plist; expression=Val(false))[1]
    jf = Symbolics.build_function(jac, vlist, plist; expression=Val(false))[1]
    return (names = [a.name for a in doc.algebraics],
            pnames = [p.name for p in doc.params],
            u0 = Float64[a.initial for a in doc.algebraics],
            p0 = Float64[p.default for p in doc.params],
            residual = (x, p = Float64[p.default for p in doc.params]) -> Float64.(f(x, p)),
            jacobian = (x, p = Float64[p.default for p in doc.params]) -> Float64.(jf(x, p)))
end
