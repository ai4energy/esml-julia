# 量纲检查：声明单位 → Unitful 量纲 → 方程两侧比较

struct DimensionIssue
    equation::String
    message::String
end

struct DimensionReport
    checked::Int
    issues::Vector{DimensionIssue}
end

const _TIME_DIM = Unitful.dimension(Unitful.u"s")

function _dimension_of(ast, units::Dict{String, Any})
    if ast[1] == :num
        return Unitful.NoDims
    elseif ast[1] == :var
        name = ast[2]
        haskey(units, name) || error("unit check: unknown variable '$name'")
        return Unitful.dimension(units[name])
    elseif ast[1] == :neg
        return _dimension_of(ast[2], units)
    elseif ast[1] == :bin
        op, l, r = ast[2], ast[3], ast[4]
        a = _dimension_of(l, units)
        b = _dimension_of(r, units)
        if op in ("+", "-")
            a == b || error("dimension mismatch: $a vs $b")
            return a
        elseif op == "*"
            return a * b
        elseif op == "/"
            return a / b
        elseif op == "^"
            (r[1] == :num) || error("unit check: exponent must be numeric")
            return a^r[2]
        end
    elseif ast[1] == :call && ast[2] == "D"
        arg = ast[3][1]
        arg[1] == :var || error("D(...) argument must be a variable")
        return _dimension_of(arg, units) / _TIME_DIM
    end
    error("unit check: unsupported expression")
end

function check_dimensions(doc::Document)
    units = Dict{String, Any}()
    for p in doc.params
        u = parse_unit(p.unit)
        u === nothing && continue
        units[p.name] = u
    end
    for s in doc.states
        u = parse_unit(s.unit)
        u === nothing && continue
        units[s.name] = u
    end
    checked = 0
    issues = DimensionIssue[]
    for eq in doc.equations
        parts = split(eq, "="; limit=2)
        length(parts) == 2 || continue
        checked += 1
        try
            dl = _dimension_of(parse_expr(strip(parts[1])), units)
            dr = _dimension_of(parse_expr(strip(parts[2])), units)
            dl == dr || push!(issues, DimensionIssue(eq, "lhs $dl vs rhs $dr"))
        catch e
            push!(issues, DimensionIssue(eq, sprint(showerror, e)))
        end
    end
    DimensionReport(checked, issues)
end
