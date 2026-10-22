# HIR：名字解析后的中间表示
#
# 第 3 章只做一层的名字解析：实例 → 路径；模型类型 → 变量/参数/方程。
# 连接、数组、分区留给后面的章节。

struct HirVar
    path::String
    initial::Float64
    unit::String
end

struct HirParam
    path::String
    value::Float64
    unit::String
end

struct HIR
    model::String
    vars::Vector{HirVar}
    params::Vector{HirParam}
    equations::Vector{String}
end

function _rewrite_equation(eq::AbstractString, names)
    out = eq
    for (local_name, path) in names
        out = replace(out, Regex("\\b" * local_name * "\\b") => path)
    end
    out
end

function build_hir(doc::Document)
    isempty(doc.instances) && error("HIR: system has no instances")
    vars = HirVar[]
    params = HirParam[]
    equations = String[]
    for inst in doc.instances
        inst.type == doc.model ||
            error("HIR: instance $(inst.name) has type $(inst.type), expected $(doc.model)")
        prefix = inst.name * "__"
        names = Pair{String,String}[]
        for s in doc.states
            path = prefix * s.name
            push!(vars, HirVar(path, s.initial, s.unit))
            push!(names, s.name => path)
        end
        for p in doc.params
            path = prefix * p.name
            push!(params, HirParam(path, p.default, p.unit))
            push!(names, p.name => path)
        end
        append!(equations, [_rewrite_equation(eq, names) for eq in doc.equations])
    end
    HIR(doc.model, vars, params, equations)
end
