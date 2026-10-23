# 多实例无连接装配：104 物性系统的参考实现
# 读取所有 <modelType> 与 <system><instance>，把变量/参数按实例前缀展开，
# 装配成纯代数残差并用 Newton 求解。只覆盖无 <connections> 的系统。

function _num_default(s)
    try
        return parse(Float64, strip(String(s)))
    catch
        return 0.0
    end
end

function assemble_components(path::AbstractString; tol::Float64=1e-10, maxiter::Int=60)
    xdoc = readxml(path); root = xdoc.root
    mts = Dict{String, Any}()
    for mt in descendants(root, "modelType")
        name = attr(mt, "name", "")
        isempty(name) && continue
        params = Dict{String, Float64}()
        pnode = first_child(mt, "parameters")
        if pnode !== nothing
            for p in children(pnode, "parameter")
                params[attr(p, "name", "")] = _num_default(attr(p, "default", "0"))
            end
        end
        vars = Tuple{String, Float64}[]
        vnode = first_child(mt, "variables")
        if vnode !== nothing
            for v in children(vnode, "variable")
                role = attr(v, "role", "algebraic")
                role == "algebraic" || error("assemble_components: 只支持代数变量（$(name).$(attr(v,"name","")) 是 $role）")
                push!(vars, (attr(v, "name", ""), _num_default(attr(v, "initial", "0"))))
            end
        end
        eqs = String[]
        enode = first_child(mt, "equations")
        if enode !== nothing
            for e in children(enode, "equation")
                push!(eqs, replace(strip(nodecontent(e)), "&lt;"=>"<", "&gt;"=>">", "&amp;"=>"&"))
            end
        end
        mts[name] = (params=params, vars=vars, eqs=eqs)
    end

    sys = first(descendants(root, "system"))
    insts = Tuple{String, String}[]
    inode = first_child(sys, "instances")
    if inode !== nothing
        for i in children(inode, "instance")
            push!(insts, (attr(i, "name", ""), attr(i, "type", "")))
        end
    end
    haskey(mts, insts[1][2]) || error("assemble_components: unknown instance type $(insts[1][2])")

    vnames = String[]; initials = Float64[]; pnames = String[]; pvals = Float64[]
    for (iname, itype) in insts
        mt = mts[itype]
        for (v, init) in mt.vars
            push!(vnames, iname * "__" * v); push!(initials, init)
        end
        for (p, val) in mt.params
            push!(pnames, iname * "__" * p); push!(pvals, val)
        end
    end
    known = Set(vcat(vnames, pnames))
    function prefix_eq(text, iname, mt)
        replace(text, r"[A-Za-z_]\w*" => m -> begin
            s = String(m)
            if haskey(mt.params, s) || any(v -> v[1] == s, mt.vars)
                iname * "__" * s
            else
                s
            end
        end)
    end
    eqtexts = String[]
    for (iname, itype) in insts
        mt = mts[itype]
        for e in mt.eqs
            push!(eqtexts, prefix_eq(e, iname, mt))
        end
    end
    vars = Dict{String, Any}(n => Symbolics.variable(Symbol(n)) for n in vnames)
    pars = Dict{String, Any}(n => pvals[i] for (i, n) in enumerate(pnames))
    vlist = [vars[n] for n in vnames]
    res = Any[]
    for text in eqtexts
        parts = split(text, "="; limit=2)
        length(parts) == 2 || error("equation must contain '=': $text")
        lhs = to_symbolic(parse_expr(strip(parts[1])), vars, pars, _T)
        rhs = to_symbolic(parse_expr(strip(parts[2])), vars, pars, _T)
        push!(res, lhs - rhs)
    end
    length(res) == length(vlist) || error("assemble_components: $(length(res)) 方程 vs $(length(vlist)) 未知数")
    jac = Symbolics.jacobian(res, vlist)
    f = Symbolics.build_function(res, vlist; expression=Val(false))[1]
    jf = Symbolics.build_function(jac, vlist; expression=Val(false))[1]
    x = copy(initials)
    for k in 1:maxiter
        r = Float64.(f(x)); rn = maximum(abs, r)
        rn < tol && return (values=Dict(vnames[i] => x[i] for i in eachindex(x)),
                            residual=rn, iterations=k, converged=true, nvars=length(x))
        J = Float64.(jf(x)); dx = -(J \ r)
        α = 1.0
        while α > 1e-4 && maximum(abs, Float64.(f(x .+ α .* dx, pvals))) >= rn
            α /= 2
        end
        x .+= α .* dx
    end
    return (values=Dict(vnames[i] => x[i] for i in eachindex(x)),
            residual=maximum(abs, Float64.(f(x))), iterations=maxiter, converged=false, nvars=length(x))
end
