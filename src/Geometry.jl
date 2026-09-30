function edges_from_centers(c::AbstractVector)
    n = length(c)
    n < 2 && return [c[1] - 0.5; c[1] + 0.5]
    mids = (c[1:end-1] .+ c[2:end]) ./ 2
    first_edge = c[1] - (c[2] - c[1]) / 2
    last_edge = c[end] + (c[end] - c[end-1]) / 2
    return vcat(first_edge, mids, last_edge)
end

function core_indices(c::AbstractVector; tol::Real = 0.2)
    widths = abs.(diff(edges_from_centers(c)))
    n = length(widths)
    n <= 4 && return 1:n
    start_idx = max(1, round(Int, 0.2n))
    end_idx = min(n, round(Int, 0.8n))
    ref_width = median(@view widths[(start_idx + 1):end_idx])
    is_core = abs.(widths .- ref_width) .<= tol * ref_width
    best_i, best_len = 1, 0
    i = 1
    while i <= n
        if is_core[i]
            j = i
            while j <= n && is_core[j]
                j += 1
            end
            if (j - i) > best_len
                best_i, best_len = i, j - i
            end
            i = j
        else
            i += 1
        end
    end
    return best_len > 0 ? (best_i:(best_i + best_len - 1)) : (1:n)
end

function core_xy_indices(model::MTModel; pad_tol::Real = 0.2)
    if length(model.npad) == 2
        xpad, ypad = model.npad
        ix = (xpad + 1):(length(model.cx) - xpad)
        iy = (ypad + 1):(length(model.cy) - ypad)
        if !isempty(ix) && !isempty(iy)
            return ix, iy
        end
    end
    return core_indices(model.cx; tol = pad_tol), core_indices(model.cy; tol = pad_tol)
end

function z_indices_for_max_depth(zc::AbstractVector, max_depth::Real)
    cum_depth = cumsum(abs.(diff(edges_from_centers(zc))))
    if max_depth <= cum_depth[1]
        return 1:1
    elseif max_depth >= cum_depth[end]
        return 1:length(zc)
    end
    idx = findfirst(>=(max_depth), cum_depth)
    if idx > 1 && (max_depth - cum_depth[idx - 1]) < (cum_depth[idx] - max_depth)
        return 1:(idx - 1)
    end
    return 1:idx
end

function compute_colorrange(values::AbstractArray)
    finite_values = values[isfinite.(values)]
    isempty(finite_values) && return (0.0, 1.0)
    qlo, qhi = quantile(vec(finite_values), (0.02, 0.98))
    lo = min(qlo, qhi)
    hi = max(qlo, qhi)
    if lo == hi
        delta = max(1e-12, 1e-6 * abs(lo))
        lo -= delta
        hi += delta
    end
    return lo, hi
end

function prepare_model_arrays(model::MTModel; log10scale::Bool = true, with_padding::Bool = true, max_depth::Union{Nothing, Real} = nothing, pad_tol::Real = 0.2)
    ix_core, iy_core = core_xy_indices(model; pad_tol = pad_tol)
    ix = with_padding ? (1:length(model.cx)) : ix_core
    iy = with_padding ? (1:length(model.cy)) : iy_core
    kz = isnothing(max_depth) ? (1:length(model.cz)) : z_indices_for_max_depth(model.cz, float(max_depth))
    values = log10scale ? log10.(model.A) : copy(model.A)
    return model.cx[ix], model.cy[iy], model.cz[kz], values[ix, iy, kz], ix, iy, kz
end

function bracket_index_and_weight(vals::AbstractVector{<:Real}, query::Real)
    n = length(vals)
    n <= 1 && return 1, 1, 0.0
    if query <= vals[1]
        return 1, 2, 0.0
    elseif query >= vals[end]
        return n - 1, n, 1.0
    end
    i1 = searchsortedfirst(vals, query)
    i0 = i1 - 1
    v0 = Float64(vals[i0])
    v1 = Float64(vals[i1])
    if v0 == v1
        return i0, i1, 0.0
    end
    w = (Float64(query) - v0) / (v1 - v0)
    return i0, i1, clamp(w, 0.0, 1.0)
end

function sample_polyline(points::Vector{Tuple{Float64, Float64}}, nsamp::Int)
    length(points) < 2 && return Float64[], Float64[], Float64[]
    seglen = Float64[0.0]
    for i in 2:length(points)
        push!(seglen, seglen[end] + hypot(points[i][1] - points[i - 1][1], points[i][2] - points[i - 1][2]))
    end
    total = seglen[end]
    if total <= 0
        return fill(points[1][1], nsamp), fill(points[1][2], nsamp), zeros(nsamp)
    end
    s_query = collect(range(0.0, total; length = max(8, nsamp)))
    xs = Vector{Float64}(undef, length(s_query))
    ys = similar(xs)
    j = 2
    for (k, s) in enumerate(s_query)
        while j < length(points) && seglen[j] < s
            j += 1
        end
        j0 = max(1, j - 1)
        j1 = min(length(points), j)
        s0 = seglen[j0]
        s1 = seglen[j1]
        t = s1 > s0 ? (s - s0) / (s1 - s0) : 0.0
        x0, y0 = points[j0]
        x1, y1 = points[j1]
        xs[k] = (1.0 - t) * x0 + t * x1
        ys[k] = (1.0 - t) * y0 + t * y1
    end
    return xs, ys, s_query
end

function build_section_surface_polyline(xv, yv, zv, values, path::Vector{Tuple{Float64, Float64}}; nsamp::Int = 360)
    xs, ys, sdist = sample_polyline(path, nsamp)
    ns = length(xs)
    nz = length(zv)
    X = Matrix{Float64}(undef, ns, nz)
    Y = Matrix{Float64}(undef, ns, nz)
    Z = Matrix{Float64}(undef, ns, nz)
    C = Matrix{Float64}(undef, ns, nz)
    for i in 1:ns
        ix0, ix1, wx = bracket_index_and_weight(xv, xs[i])
        iy0, iy1, wy = bracket_index_and_weight(yv, ys[i])
        for k in 1:nz
            X[i, k] = xs[i]
            Y[i, k] = ys[i]
            Z[i, k] = zv[k]
            v00 = values[ix0, iy0, k]
            v10 = values[ix1, iy0, k]
            v01 = values[ix0, iy1, k]
            v11 = values[ix1, iy1, k]
            v0 = (1.0 - wx) * v00 + wx * v10
            v1 = (1.0 - wx) * v01 + wx * v11
            C[i, k] = (1.0 - wy) * v0 + wy * v1
        end
    end
    return X, Y, Z, C, sdist
end
