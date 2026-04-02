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

function _sanitize_iso_range(vmin::Real, vmax::Real, cmin::Real, cmax::Real)
    lo = Float64(vmin)
    hi = Float64(vmax)
    if !isfinite(lo) || !isfinite(hi)
        lo, hi = Float64(cmin), Float64(cmax)
    end
    if lo > hi
        lo, hi = hi, lo
    end
    if lo == hi
        delta = max(1e-8, 1e-4 * max(abs(lo), abs(Float64(cmax - cmin)), 1.0))
        lo -= delta
        hi += delta
    end
    return lo, hi
end

function _cube_triangles(x0::Float64, x1::Float64, y0::Float64, y1::Float64, z0::Float64, z1::Float64)
    p000 = (x0, y0, z0)
    p100 = (x1, y0, z0)
    p010 = (x0, y1, z0)
    p110 = (x1, y1, z0)
    p001 = (x0, y0, z1)
    p101 = (x1, y0, z1)
    p011 = (x0, y1, z1)
    p111 = (x1, y1, z1)
    return NTuple{3, NTuple{3, Float64}}[
        (p000, p100, p110), (p000, p110, p010),
        (p001, p111, p101), (p001, p011, p111),
        (p000, p001, p101), (p000, p101, p100),
        (p010, p110, p111), (p010, p111, p011),
        (p000, p010, p011), (p000, p011, p001),
        (p100, p101, p111), (p100, p111, p110),
    ]
end

function build_range_volume_triangles(xv, yv, zv, values, vmin::Real, vmax::Real, dstart_m::Real, dend_m::Real; stride::Int = 1)
    nx, ny, nz = size(values)
    if nx == 0 || ny == 0 || nz == 0
        return NTuple{3, NTuple{3, Float64}}[], 0
    end

    x_edges = edges_from_centers(xv)
    y_edges = edges_from_centers(yv)
    z_edges = edges_from_centers(zv)
    lo, hi = _sanitize_iso_range(vmin, vmax, minimum(values), maximum(values))
    d0 = max(0.0, min(Float64(dstart_m), Float64(dend_m)))
    d1 = max(0.0, max(Float64(dstart_m), Float64(dend_m)))
    step = max(1, stride)
    triangles = NTuple{3, NTuple{3, Float64}}[]
    selected = 0
    for i in 1:step:nx, j in 1:step:ny, k in 1:step:nz
        val = Float64(values[i, j, k])
        depth_m = -Float64(zv[k])
        if !(val >= lo && val <= hi && depth_m >= d0 && depth_m <= d1)
            continue
        end
        append!(triangles, _cube_triangles(Float64(x_edges[i]), Float64(x_edges[i + 1]), Float64(y_edges[j]), Float64(y_edges[j + 1]), Float64(z_edges[k]), Float64(z_edges[k + 1])))
        selected += 1
    end
    return triangles, selected
end

function triangles_to_vertices_faces(triangles::Vector{NTuple{3, NTuple{3, Float64}}})
    vertices = GLMakie.Point3f[]
    faces = GLMakie.TriangleFace{Int32}[]
    for triangle in triangles
        base = length(vertices) + 1
        push!(vertices, GLMakie.Point3f(triangle[1][1], triangle[1][2], triangle[1][3]))
        push!(vertices, GLMakie.Point3f(triangle[2][1], triangle[2][2], triangle[2][3]))
        push!(vertices, GLMakie.Point3f(triangle[3][1], triangle[3][2], triangle[3][3]))
        push!(faces, GLMakie.TriangleFace(Int32(base), Int32(base + 1), Int32(base + 2)))
    end
    return vertices, faces
end

function write_dxf_triangles(path::AbstractString, triangles::Vector{NTuple{3, NTuple{3, Float64}}}; layer::AbstractString = "ISO")
    open(path, "w") do io
        println(io, "0")
        println(io, "SECTION")
        println(io, "2")
        println(io, "ENTITIES")
        for triangle in triangles
            p1, p2, p3 = triangle
            println(io, "0")
            println(io, "3DFACE")
            println(io, "8")
            println(io, layer)
            println(io, "10"); println(io, p1[1])
            println(io, "20"); println(io, p1[2])
            println(io, "30"); println(io, p1[3])
            println(io, "11"); println(io, p2[1])
            println(io, "21"); println(io, p2[2])
            println(io, "31"); println(io, p2[3])
            println(io, "12"); println(io, p3[1])
            println(io, "22"); println(io, p3[2])
            println(io, "32"); println(io, p3[3])
            println(io, "13"); println(io, p3[1])
            println(io, "23"); println(io, p3[2])
            println(io, "33"); println(io, p3[3])
        end
        println(io, "0")
        println(io, "ENDSEC")
        println(io, "0")
        println(io, "EOF")
    end
    return path
end