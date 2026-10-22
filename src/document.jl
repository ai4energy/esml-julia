# 文档层：ESML XML → Document
#
# 只读取第 1 章需要的 subset：一个 modelType、参数、状态变量、方程、
# 一个 system 与一个 simulate 任务。后面的章节在同一个 Document 上扩展。

tag(n) = split(nodename(n), ":")[end]

function children(n, name)
    [c for c in elements(n) if tag(c) == name]
end

function first_child(n, name)
    cs = children(n, name)
    isempty(cs) ? nothing : cs[1]
end

function descendants(n, name)
    out = Any[]
    for c in elements(n)
        tag(c) == name && push!(out, c)
        append!(out, descendants(c, name))
    end
    out
end

attr(n, key, default="") = haskey(n, key) ? n[key] : default

struct ParseError <: Exception
    path::String
    element::String
    message::String
end

function Base.showerror(io::IO, e::ParseError)
    print(io, "ESML parse error at $(e.path): ", e.message,
          isempty(e.element) ? "" : " (element <$(e.element)>)")
end

function _check_children(node, allowed, path, where)
    for c in elements(node)
        name = tag(c)
        name in allowed && continue
        throw(ParseError(path, name,
            "unknown element <$name> under <$where>; allowed: " * join(allowed, ", ")))
    end
end

function _require_attr(node, key, path, where)
    haskey(node, key) && return node[key]
    throw(ParseError(path, tag(node), "missing required attribute '$key' on <$where>"))
end

struct Parameter
    name::String
    default::Float64
    unit::String
end

struct State
    name::String
    initial::Float64
    unit::String
end

struct Instance
    name::String
    type::String
    count::Int
end

"""One `<task>` declaration. Payload fields are optional; `nothing` = absent."""
struct TaskSpec
    name::String
    kind::String
    tspan::Union{Nothing, Tuple{Float64, Float64}}
    solver::Union{Nothing, String}
    perturb::Union{Nothing, Tuple{String, Float64}}
    estimates::Vector{Tuple{String, Float64}}
    samples::Vector{Tuple{Float64, Float64}}
    decisions::Vector{Tuple{String, Float64, Float64}}
    objective::Union{Nothing, Tuple{String, String}}
    constraints::Vector{String}
    mpc::Union{Nothing, Tuple{Int, Float64}}
    surrogate::Union{Nothing, Tuple{String, Int}}
    metrics::Vector{String}
end

struct Document
    name::String
    model::String
    params::Vector{Parameter}
    states::Vector{State}
    equations::Vector{String}
    tspan::Tuple{Float64, Float64}
    system::String
    instances::Vector{Instance}
    tasks::Vector{TaskSpec}
end

function parse_document(path::AbstractString)
    doc = readxml(path)
    docroot = root(doc)
    tag(docroot) == "esml" ||
        throw(ParseError(path, tag(docroot), "root element must be <esml>"))
    _check_children(docroot, ["variableTypes", "modelTypes", "systems", "computeTasks"],
                    path, "esml")
    types = Dict{String, String}()
    for t in descendants(docroot, "type")
        name = attr(t, "name")
        isempty(name) && continue
        types[name] = attr(t, "unit", "1")
    end

    model_node = first(descendants(docroot, "modelType"))
    _check_children(model_node, ["parameters", "variables", "equations"],
                    path, "modelType")
    model = _require_attr(model_node, "name", path, "modelType")

    params = Parameter[]
    for p in descendants(model_node, "parameter")
        name = _require_attr(p, "name", path, "parameter")
        push!(params, Parameter(name, parse(Float64, attr(p, "default", "0.0")),
                               get(types, attr(p, "type"), "1")))
    end

    states = State[]
    for v in descendants(model_node, "variable")
        name = _require_attr(v, "name", path, "variable")
        role = attr(v, "role", "algebraic")
        role == "state" || continue
        push!(states, State(name, parse(Float64, attr(v, "initial", "0.0")),
                            get(types, attr(v, "type"), "1")))
    end

    equations = [strip(nodecontent(e)) for e in descendants(model_node, "equation")
                 if !isempty(strip(nodecontent(e)))]

    system_node = first(descendants(docroot, "system"))
    _check_children(system_node, ["instances", "schedule"], path, "system")
    system = attr(system_node, "name", "S")

    instances = Instance[]
    for i in descendants(system_node, "instance")
        name = _require_attr(i, "name", path, "instance")
        typ = _require_attr(i, "type", path, "instance")
        cnt = parse(Int, attr(i, "count", "1"))
        cnt >= 1 || throw(ParseError(path, "instance", "count must be >= 1"))
        push!(instances, Instance(name, typ, cnt))
    end

    tasks = TaskSpec[]
    tspan = (0.0, 1.0)
    all_payloads = ["tspan", "solver", "perturb", "estimate", "samples",
                    "decision", "objective", "constraints", "mpc", "surrogate",
                    "metrics", "data"]
    for task in descendants(docroot, "task")
        _check_children(task, all_payloads, path, "task")
        tname = _require_attr(task, "name", path, "task")
        kind = _require_attr(task, "kind", path, "task")
        ts = first_child(task, "tspan")
        tsp = ts === nothing ? nothing :
              (parse(Float64, attr(ts, "from", "0")),
               parse(Float64, attr(ts, "to", "1")))
        sv = first_child(task, "solver")
        solver = sv === nothing ? nothing : attr(sv, "name", "")
        pb = first_child(task, "perturb")
        perturb = pb === nothing ? nothing :
                  (attr(pb, "name", ""), parse(Float64, attr(pb, "fraction", "0.1")))
        estimates = Tuple{String, Float64}[]
        for e in children(task, "estimate")
            push!(estimates, (attr(e, "name", ""),
                              parse(Float64, attr(e, "initial", "0.0"))))
        end
        samples = Tuple{Float64, Float64}[]
        sr = first_child(task, "samples")
        if sr !== nothing
            for sm in children(sr, "sample")
                push!(samples, (parse(Float64, attr(sm, "x", "0")),
                                parse(Float64, attr(sm, "y", "0"))))
            end
        end
        decisions = Tuple{String, Float64, Float64}[]
        for d in children(task, "decision")
            push!(decisions, (attr(d, "name", ""),
                              parse(Float64, attr(d, "lower", "0")),
                              parse(Float64, attr(d, "upper", "0"))))
        end
        ob = first_child(task, "objective")
        objective = ob === nothing ? nothing :
                    (attr(ob, "direction", "min"), strip(nodecontent(ob)))
        constraints = String[]
        cr = first_child(task, "constraints")
        if cr !== nothing
            for c in children(cr, "constraint")
                push!(constraints, strip(nodecontent(c)))
            end
        end
        mp = first_child(task, "mpc")
        mpc = mp === nothing ? nothing :
              (parse(Int, attr(mp, "N", "10")), parse(Float64, attr(mp, "dt", "1")))
        sg = first_child(task, "surrogate")
        surrogate = sg === nothing ? nothing :
                    (attr(sg, "method", "lsq"), parse(Int, attr(sg, "degree", "2")))
        metrics = String[]
        mr = first_child(task, "metrics")
        if mr !== nothing
            for m in children(mr, "metric")
                push!(metrics, attr(m, "name", ""))
            end
        end
        push!(tasks, TaskSpec(tname, kind, tsp, solver, perturb, estimates,
                              samples, decisions, objective, constraints,
                              mpc, surrogate, metrics))
        if kind == "simulate" && tsp !== nothing && tspan == (0.0, 1.0)
            tspan = tsp
        end
    end

    Document(attr(docroot, "name"), model, params, states, equations, tspan,
             system, instances, tasks)
end
