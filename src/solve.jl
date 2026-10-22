# 求解层：MTK 系统 → ODEProblem → SciML 解

struct SimulationResult
    sol::Any
    sys::Any
    states::Dict{String, Any}
    params::Dict{String, Any}
end

function simulate(doc::Document; tspan=doc.tspan, saveat=1.0)
    c = compile_model(doc)
    u0 = Dict(c.states[s.name] => s.initial for s in doc.states)
    p = Dict(c.params[p.name] => p.default for p in doc.params)
    prob = ODEProblem(c.sys, merge(u0, p), tspan)
    sol = solve(prob, Tsit5(); saveat=saveat)
    SimulationResult(sol, c.sys, c.states, c.params)
end

function final_state(result::SimulationResult, name::AbstractString)
    result.sol[result.states[name]][end]
end
