# 结构分析：未知量、方程与匹配（第 5 章的最小版本）

struct StructureReport
    dof::Int
    unmatched_vars::Vector{String}
    unmatched_eqs::Vector{Int}
end

function _incidence(hir::HIR)
    vars = [v.path for v in hir.vars]
    [ [i for (i, v) in enumerate(vars) if occursin(Regex("\\b" * v * "\\b"), eq)]
      for eq in hir.equations ]
end

function analyze_structure(hir::HIR)
    vars = [v.path for v in hir.vars]
    n, m = length(vars), length(hir.equations)
    inc = _incidence(hir)
    match_var = zeros(Int, n)
    match_eq = zeros(Int, m)

    function augment(e, seen)
        for v in inc[e]
            seen[v] && continue
            seen[v] = true
            if match_var[v] == 0 || augment(match_var[v], seen)
                match_var[v] = e
                match_eq[e] = v
                return true
            end
        end
        false
    end

    for e in 1:m
        augment(e, falses(n))
    end

    unmatched_vars = [vars[i] for i in 1:n if match_var[i] == 0]
    unmatched_eqs = [e for e in 1:m if match_eq[e] == 0]
    StructureReport(n - m, unmatched_vars, unmatched_eqs)
end
