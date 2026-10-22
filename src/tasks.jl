# 任务层：问题类的最小映射（第 10 章）
#
# 参考实现只执行 simulate 与 sensitivity；其余五类在书中讲映射，
# 代码留作扩展，不假装已经支持。

struct TaskSpec
    name::String
    kind::Symbol
end

function sensitivity(doc::Document; param::AbstractString, relstep=1e-3)
    idx = findfirst(p -> p.name == param, doc.params)
    idx === nothing && error("unknown parameter $param")
    base = doc.params[idx].default
    delta = abs(base) * relstep
    delta == 0 && (delta = relstep)
    y0 = final_state(simulate(doc; saveat=doc.tspan[2]), "N")
    y1 = final_state(simulate(doc; saveat=doc.tspan[2],
                              param_overrides=Dict(param => base + delta)), "N")
    (value=(y1 - y0) / delta, base=y0, perturbed=y1, delta=delta)
end

function run_task(doc::Document, kind::Symbol; param="lambda")
    if kind == :simulate
        return simulate(doc; saveat=doc.tspan[2])
    elseif kind == :sensitivity
        return sensitivity(doc; param=param)
    end
    error("task '$kind' is not implemented in the reference; the book explains its mapping")
end
