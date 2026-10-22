# 单位层：声明 → Unitful。数值层仍用裸数；Unitful 只做边界检查。

struct UnitIssue
    where::String
    message::String
end

struct UnitReport
    checked::Int
    issues::Vector{UnitIssue}
end

function parse_unit(s::AbstractString)
    t = strip(s)
    (isempty(t) || t == "1") && return Unitful.NoUnits
    try
        return Unitful.uparse(t)
    catch
        return nothing
    end
end

function check_units(doc::Document)
    issues = UnitIssue[]
    checked = 0
    for p in doc.params
        checked += 1
        parse_unit(p.unit) === nothing &&
            push!(issues, UnitIssue("parameter $(p.name)", "unknown unit '$(p.unit)'"))
    end
    for s in doc.states
        checked += 1
        parse_unit(s.unit) === nothing &&
            push!(issues, UnitIssue("state $(s.name)", "unknown unit '$(s.unit)'"))
    end
    UnitReport(checked, issues)
end
