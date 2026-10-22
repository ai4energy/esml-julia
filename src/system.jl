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
    params = Dict{String, Any}()
    for p in doc.params
        params[p.name] = _param_variable(p.name)
    end

    equations = Equation[]
    for text in doc.equations
        parts = split(text, "="; limit=2)
        length(parts) == 2 || error("equation must contain '=': $text")
        lhs = to_symbolic(parse_expr(strip(parts[1])), states, params, t)
        rhs = to_symbolic(parse_expr(strip(parts[2])), states, params, t)
        push!(equations, lhs ~ rhs)
    end

    sys = ODESystem(equations, t; name=:S)
    sys = structural_simplify(sys)
    (sys=sys, states=states, params=params, t=t)
end
