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

struct Document
    name::String
    model::String
    params::Vector{Parameter}
    states::Vector{State}
    equations::Vector{String}
    tspan::Tuple{Float64, Float64}
    system::String
    instances::Vector{Instance}
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
    _check_children(system_node, ["instances"], path, "system")
    system = attr(system_node, "name", "S")

    instances = Instance[]
    for i in descendants(system_node, "instance")
        name = _require_attr(i, "name", path, "instance")
        typ = _require_attr(i, "type", path, "instance")
        cnt = parse(Int, attr(i, "count", "1"))
        cnt >= 1 || throw(ParseError(path, "instance", "count must be >= 1"))
        push!(instances, Instance(name, typ, cnt))
    end

    tspan = (0.0, 1.0)
    for task in descendants(docroot, "task")
        _check_children(task, ["tspan"], path, "task")
        kind = attr(task, "kind")
        kind == "simulate" || continue
        ts = first_child(task, "tspan")
        ts === nothing || (tspan = (parse(Float64, attr(ts, "from", "0")),
                                    parse(Float64, attr(ts, "to", "1"))))
        break
    end

    Document(attr(docroot, "name"), model, params, states, equations, tspan, system, instances)
end
