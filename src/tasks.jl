# 任务层：十种任务（七类问题类 + 三个辅助任务）的参考执行器。
#
# 这一层只做「把问题算出来」：模型仍由 compile_model 建一次，
# 执行器复用同一个系统；求解器内部不做扩展。

_leaf(p::AbstractString) = String(last(split(p, r"\.|__")))

function _default_param(doc::Document, name::AbstractString)
    for p in doc.params
        p.name == name && return p.default
    end
    error("unknown parameter $name")
end

# --- expression evaluation (for the independent optimize objective) ---

function eval_ast(ast, env::Dict{String, Float64})
    tag = ast[1]
    if tag == :num
        return Float64(ast[2])
    elseif tag == :var
        name = ast[2]
        haskey(env, name) || error("unknown symbol $name in objective")
        return env[name]
    elseif tag == :neg
        return -eval_ast(ast[2], env)
    elseif tag == :bin
        op, a, b = ast[2], eval_ast(ast[3], env), eval_ast(ast[4], env)
        op == "+" && return a + b
        op == "-" && return a - b
        op == "*" && return a * b
        op == "/" && return a / b
        op == "^" && return a^b
        error("unsupported operator $op in objective")
    end
    error("unsupported expression node in objective")
end

# --- 1. simulate ---

function task_simulate(doc::Document, t::TaskSpec)
    tspan = t.tspan === nothing ? doc.tspan : t.tspan
    r = simulate(doc; tspan=tspan, saveat=(tspan[2] - tspan[1]) / 200)
    (kind=:simulate, result=r)
end

# --- 2. sensitivity ---

function task_sensitivity(doc::Document, t::TaskSpec)
    t.perturb === nothing && error("sensitivity requires <perturb>")
    path, frac = t.perturb
    name = _leaf(path)
    base = _default_param(doc, name)
    delta = base == 0 ? frac : abs(base) * frac
    tspan = t.tspan === nothing ? doc.tspan : t.tspan
    saveat = (tspan[2] - tspan[1]) / 200
    plus = simulate(doc; tspan=tspan, saveat=saveat,
                    param_overrides=Dict(name => base + delta))
    minus = simulate(doc; tspan=tspan, saveat=saveat,
                     param_overrides=Dict(name => base - delta))
    (kind=:sensitivity, var=path, plus=plus, minus=minus, delta=delta)
end

# --- 3. parameter estimation ---

function _sse_at(c, doc::Document, name::AbstractString, theta::Float64,
                 samples::Vector{Tuple{Float64, Float64}})
    tmax = maximum(first.(samples))
    u0 = Dict(c.states[s.name] => s.initial for s in doc.states)
    p = Dict(c.params[pp.name] => (pp.name == name ? theta : pp.default)
             for pp in doc.params)
    prob = ODEProblem(c.sys, merge(u0, p), (0.0, tmax))
    sol = solve(prob, Tsit5(); saveat=[first(s) for s in samples])
    sum((y - sol(x)[1])^2 for (x, y) in samples)
end

function _golden(f, a, b; tol=1e-10)
    gr = (sqrt(5) - 1) / 2
    c = b - gr * (b - a)
    d = a + gr * (b - a)
    fc, fd = f(c), f(d)
    while abs(b - a) > tol
        if fc < fd
            b, d, fd = d, c, fc
            c = b - gr * (b - a)
            fc = f(c)
        else
            a, c, fc = c, d, fd
            d = a + gr * (b - a)
            fd = f(d)
        end
    end
    (a + b) / 2
end

function task_estimation(doc::Document, t::TaskSpec)
    isempty(t.estimates) && error("estimation requires <estimate>")
    isempty(t.samples) && error("estimation requires <samples>")
    path, init = t.estimates[1]
    name = _leaf(path)
    c = compile_model(doc)
    f = theta -> _sse_at(c, doc, name, theta, t.samples)
    xs = 10 .^ range(log10(1e-4), log10(10.0), length=120)
    vals = [f(x) for x in xs]
    i = argmin(vals)
    a = xs[max(1, i - 1)]
    b = xs[min(length(xs), i + 1)]
    theta = _golden(f, a, b)
    (kind=:estimation, theta=[theta], sse=f(theta), initial=init)
end

# --- 4. optimization ---

function _objective_at(t::TaskSpec, xname::String, xval::Float64,
                       direction::String)
    t.objective === nothing && error("optimize requires <objective>")
    ast = parse_expr(t.objective[2])
    v = eval_ast(ast, Dict(xname => xval))
    direction == "max" ? -v : v
end

function _constraint_bounds(t::TaskSpec, xname::String, lo::Float64, hi::Float64)
    for text in t.constraints
        m = match(r"^\s*([A-Za-z_]\w*)\s*(>=|>|<=|<)\s*([-+0-9.eE]+)\s*$", text)
        m === nothing && error("unsupported constraint: $text")
        m.captures[1] == xname ||
            error("constraint variable $(m.captures[1]) != decision $xname")
        c = parse(Float64, m.captures[3])
        if m.captures[2] in (">=", ">")
            lo = max(lo, c)
        else
            hi = min(hi, c)
        end
    end
    (lo, hi)
end

function task_optimize(doc::Document, t::TaskSpec)
    length(t.decisions) == 1 ||
        error("reference optimize supports one decision variable")
    xname, lower, upper = t.decisions[1]
    lo, hi = _constraint_bounds(t, xname, lower, upper)
    lo <= hi || return (kind=:optimize, x=Float64[], objective=NaN, feasible=false)
    direction = t.objective === nothing ? "min" : t.objective[1]
    f = x -> _objective_at(t, xname, x, direction)
    xs = range(lo, hi, length=1001)
    vals = [f(x) for x in xs]
    i = argmin(vals)
    a = xs[max(1, i - 1)]
    b = xs[min(length(xs), i + 1)]
    xbest = _golden(f, a, b)
    fbest = f(xbest)
    obj = direction == "max" ? -fbest : fbest
    (kind=:optimize, x=[xbest], objective=obj, feasible=true)
end

# --- 5. control (single-input MPC, reference implementation) ---

function _step_state(c, doc::Document, x0::Float64, u::Float64,
                     dt::Float64, pname::String, sname::String)
    u0 = Dict(c.states[s.name] => (s.name == sname ? x0 : s.initial)
              for s in doc.states)
    p = Dict(c.params[pp.name] => (pp.name == pname ? u : pp.default)
             for pp in doc.params)
    prob = ODEProblem(c.sys, merge(u0, p), (0.0, dt))
    sol = solve(prob, Tsit5(); saveat=dt)
    sol.u[end][1]
end

function task_control(doc::Document, t::TaskSpec)
    t.mpc === nothing && error("control requires <mpc>")
    isempty(t.estimates) &&
        error("control requires <estimate name=input initial=setpoint>")
    isempty(doc.states) && error("control requires a state")
    N, dt = t.mpc
    path, setpoint = t.estimates[1]
    pname = _leaf(path)
    sname = doc.states[1].name
    c = compile_model(doc)
    xcur = doc.states[1].initial
    us = Float64[]
    xs = Float64[xcur]
    for _ in 1:(2N)
        cost = u -> abs(_step_state(c, doc, xcur, u, dt, pname, sname) - setpoint)
        grid = range(0.0, 10.0, length=11)
        gv = [cost(u) for u in grid]
        gi = argmin(gv)
        a = grid[max(1, gi - 1)]
        b = grid[min(length(grid), gi + 1)]
        best_u = _golden(cost, a, b; tol=1e-4)
        push!(us, best_u)
        xcur = _step_state(c, doc, xcur, best_u, dt, pname, sname)
        push!(xs, xcur)
    end
    (kind=:control, u=us, x=xs)
end

# --- 6. surrogate ---

function task_surrogate(doc::Document, t::TaskSpec)
    t.surrogate === nothing && error("surrogate requires <surrogate>")
    isempty(t.samples) && error("surrogate requires <samples>")
    method, degree = t.surrogate
    degree > 0 || error("surrogate degree must be > 0")
    xs = [s[1] for s in t.samples]
    ys = [s[2] for s in t.samples]
    A = hcat([xs .^ k for k in 0:degree]...)
    coef = A \ ys
    pred = A * coef
    sst = sum((ys .- mean(ys)) .^ 2)
    r2 = sst == 0 ? 1.0 : 1 - sum((ys .- pred) .^ 2) / sst
    (kind=:surrogate, coeffs=coef, degree=degree, r2=r2, method=method)
end

# --- 7. validation ---

function task_validation(doc::Document, t::TaskSpec)
    isempty(t.samples) && error("validation requires <samples>")
    tspan = t.tspan === nothing ? doc.tspan : t.tspan
    r = simulate(doc; tspan=tspan, saveat=(tspan[2] - tspan[1]) / 200)
    pred = [r.sol(x)[1] for (x, y) in t.samples]
    ys = [y for (x, y) in t.samples]
    res = ys .- pred
    r2 = 1 - sum(res .^ 2) / sum((ys .- mean(ys)) .^ 2)
    (kind=:validation, r2=r2, rmse=sqrt(mean(res .^ 2)), mae=mean(abs.(res)),
     bias=mean(res), max_abs=maximum(abs.(res)), residuals=res, metrics=t.metrics)
end

# --- 8. forecast (polynomial extrapolation over time) ---

function task_forecast(doc::Document, t::TaskSpec)
    tspan = t.tspan === nothing ? doc.tspan : t.tspan
    N = t.mpc === nothing ? 3 : t.mpc[1]
    dt = t.mpc === nothing ? 0.5 : t.mpc[2]
    r = simulate(doc; tspan=tspan, saveat=(tspan[2] - tspan[1]) / 50)
    ts = collect(r.sol.t)
    ys = [u[1] for u in r.sol.u]
    degree = 3
    A = hcat([ts .^ k for k in 0:degree]...)
    coef = A \ ys
    fitted = [(ts[i], (A * coef)[i]) for i in eachindex(ts)]
    extrapolated = [(tspan[2] + k * dt,
                     sum(coef[j] * (tspan[2] + k * dt)^(j - 1)
                         for j in 1:length(coef))) for k in 1:N]
    last_residual = abs(ys[end] - (A * coef)[end])
    (kind=:forecast, fitted=fitted, extrapolated=extrapolated,
     degree=degree, last_residual=last_residual)
end

# --- 9. data summary ---

function task_data(doc::Document, t::TaskSpec)
    isempty(t.samples) && error("data requires <samples>")
    ys = [s[2] for s in t.samples]
    # Population standard deviation (n), matching the engine's DataOutcome.
    (kind=:data, count=length(ys), min=minimum(ys), max=maximum(ys),
     mean=mean(ys), std=std(ys; corrected=false), median=median(ys),
     sources=String[])
end

# --- 10. decision ---

function task_decision(doc::Document, t::TaskSpec)
    isempty(t.decisions) && error("decision requires candidates")
    names = [d[1] for d in t.decisions]
    vals = [d[3] for d in t.decisions]
    direction = t.objective === nothing ? "min" : t.objective[1]
    idx = direction == "max" ? argmax(vals) : argmin(vals)
    (kind=:decision, chosen=names[idx], value=vals[idx],
     direction=direction,
     candidates=[(name=names[i], value=vals[i]) for i in eachindex(vals)],
     pareto_front=[])
end

# --- dispatch ---

function _run_task(doc::Document, t::TaskSpec)
    k = t.kind
    k == "simulate" && return task_simulate(doc, t)
    k == "sensitivity" && return task_sensitivity(doc, t)
    k == "estimation" && return task_estimation(doc, t)
    k == "optimize" && return task_optimize(doc, t)
    k == "control" && return task_control(doc, t)
    k == "surrogate" && return task_surrogate(doc, t)
    k == "validation" && return task_validation(doc, t)
    k == "forecast" && return task_forecast(doc, t)
    k == "data" && return task_data(doc, t)
    k == "decision" && return task_decision(doc, t)
    error("task kind '$k' is not implemented in the reference")
end

"""Run the first task of `kind` (optionally by `name`).

`simulate` keeps the historical return type (`SimulationResult`); the other
kinds return a named tuple with the task's output fields.
"""
function run_task(doc::Document, kind::Symbol; name=nothing)
    idx = findfirst(t -> t.kind == String(kind) &&
                         (name === nothing || t.name == name), doc.tasks)
    idx === nothing &&
        error("no task kind=$kind$(name === nothing ? "" : " name=$name")")
    r = _run_task(doc, doc.tasks[idx])
    kind == :simulate ? r.result : r
end

"""Run every declared task, in declaration order."""
run_tasks(doc::Document) = [_run_task(doc, t) for t in doc.tasks]

# --- historical sensitivity API (kept for the chapter-10 tests) ---

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
