# 符号层：方程文本 → Symbolics 表达式 → 导数
#
# 第 7 章只做一条方程：把右侧表达式交给 Symbolics，并对状态求导。
# 多条方程与雅可比矩阵留到第 8 章。

function symbolic_rhs(doc::Document)
    t = _T
    states = Dict{String, Any}()
    for s in doc.states
        states[s.name] = _state_variable(s.name)
    end
    params = Dict{String, Any}()
    for p in doc.params
        params[p.name] = _param_variable(p.name)
    end
    parts = split(doc.equations[1], "="; limit=2)
    length(parts) == 2 || error("equation must contain '='")
    rhs = to_symbolic(parse_expr(strip(parts[2])), states, params, t)
    (states=states, params=params, rhs=rhs)
end

function symbolic_derivative(doc::Document, state_name::AbstractString)
    s = symbolic_rhs(doc)
    haskey(s.states, state_name) || error("unknown state $state_name")
    Symbolics.derivative(s.rhs, s.states[state_name])
end
