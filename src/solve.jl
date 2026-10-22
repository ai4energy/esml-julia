# 求解层：MTK 系统 → ODEProblem → SciML 解

struct SimulationResult
    sol::Any
    sys::Any
    states::Dict{String, Any}
    params::Dict{String, Any}
end

"""Simulate one model with optional parameter / state overrides.

`state_overrides` is used by the control and estimation executors, which need
to restart from a measured (not the declared initial) state.
"""
function simulate(doc::Document; tspan=doc.tspan, saveat=1.0,
                  param_overrides=Dict{String,Float64}(),
                  state_overrides=Dict{String,Float64}())
    c = compile_model(doc)
    _simulate_compiled(c, doc; tspan=tspan, saveat=saveat,
                       param_overrides=param_overrides,
                       state_overrides=state_overrides)
end

"""Reuse an already-compiled system (avoids re-running MTK for every trial)."""
function _simulate_compiled(c, doc::Document; tspan, saveat,
                            param_overrides=Dict{String,Float64}(),
                            state_overrides=Dict{String,Float64}())
    u0 = Dict(c.states[s.name] => get(state_overrides, s.name, s.initial)
              for s in doc.states)
    p = Dict(c.params[pp.name] => get(param_overrides, pp.name, pp.default)
             for pp in doc.params)
    prob = ODEProblem(c.sys, merge(u0, p), tspan)
    sol = solve(prob, Tsit5(); saveat=saveat)
    SimulationResult(sol, c.sys, c.states, c.params)
end

function final_state(result::SimulationResult, name::AbstractString)
    result.sol[result.states[name]][end]
end
