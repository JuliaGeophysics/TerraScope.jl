meshgrid(ax::AbstractVector, ay::AbstractVector) = (
    repeat(reshape(ax, 1, :), length(ay), 1),
    repeat(reshape(ay, :, 1), 1, length(ax)),
)

function read_mackie3d_model(fname::AbstractString, block::Bool = true)
    lines = readlines(fname)
    i = 1
    while i <= length(lines) && (isempty(lines[i]) || startswith(strip(lines[i]), "#"))
        i += 1
    end

    i <= length(lines) || error("Empty ModEM model: $fname")
    header = strip(lines[i])
    i += 1
    tokens = split(header)
    ints = Int[]
    for token in tokens
        parsed = tryparse(Int, token)
        if parsed !== nothing
            push!(ints, parsed)
        end
    end
    length(ints) >= 4 || error("Invalid ModEM dimensions: $header")
    nx, ny, nz, nz_air = ints[1], ints[2], ints[3], ints[4]
    all(>(0), (nx,ny,nz)) || error("ModEM dimensions must be positive")
    scale_type = occursin("LOGE", header) ? "LOGE" : occursin("LOG10", header) ? "LOG10" : "LINEAR"

    function take_floats!(n::Int)
        collected = Float64[]
        while length(collected) < n && i <= length(lines)
            for token in split(strip(lines[i]))
                parsed = tryparse(Float64, token)
                if parsed !== nothing
                    push!(collected, parsed)
                    length(collected) == n && break
                end
            end
            i += 1
        end
        length(collected) == n || error("Truncated ModEM model: expected $n numbers, got $(length(collected))")
        return collected
    end

    dx = take_floats!(nx)
    dy = take_floats!(ny)
    dz = take_floats!(nz)
    values = zeros(nx, ny, nz)

    if block
        for k in 1:nz
            block_values = take_floats!(nx * ny)
            values[:, :, k] = reverse(reshape(block_values, nx, ny), dims = 1)
        end
    else
        kmax = 0
        while kmax < nz && i <= length(lines)
            raw = strip(lines[i])
            i += 1
            isempty(raw) && continue
            layers = Int[]
            for token in split(raw)
                parsed = tryparse(Int, token)
                parsed === nothing || push!(layers, parsed)
            end
            isempty(layers) && continue
            length(layers) == 1 && push!(layers, layers[1])
            block_values = reshape(take_floats!(nx * ny), nx, ny)
            for k in layers[1]:layers[2]
                values[:, :, k] = block_values
            end
            kmax = max(kmax, layers[2])
        end
    end

    origin = [0.0, 0.0, 0.0]
    rotation = 0.0
    while i <= length(lines)
        raw = strip(lines[i])
        i += 1
        isempty(raw) && continue
        parsed = Float64[]
        for token in split(raw)
            number = tryparse(Float64, token)
            number === nothing || push!(parsed, number)
        end
        if length(parsed) == 3
            origin = parsed
        elseif length(parsed) == 1
            rotation = parsed[1]
        end
    end

    return dx, dy, dz, values, nz_air, scale_type, origin, rotation
end

function load_model_modem(path::AbstractString)
    dx, dy, dz, values, _, scale_type, origin, _ = read_mackie3d_model(path, true)
    model = MTModel(
        values,
        dx,
        dy,
        dz,
        size(values, 1),
        size(values, 2),
        size(values, 3),
        Float64[],
        Float64[],
        Float64[],
        collect(origin),
        Float64[],
        Float64[],
        Float64[],
        zeros(0, 0),
        zeros(0, 0),
        zeros(0, 0),
        zeros(0, 0),
        zeros(0, 0),
        (0, 0),
        String(path),
        "",
    )

    if scale_type == "LOGE"
        model.A = exp.(model.A)
    elseif scale_type == "LOG10"
        model.A = 10.0 .^ model.A
    end

    model.y = vcat(0.0, cumsum(model.dy)) .+ model.origin[2]
    model.x = vcat(0.0, cumsum(model.dx)) .+ model.origin[1]
    model.z = vcat(0.0, cumsum(model.dz)) .+ model.origin[3]
    model.A[model.A .> 1e15] .= NaN

    model.cx = (model.x[1:end-1] .+ model.x[2:end]) ./ 2
    model.cy = (model.y[1:end-1] .+ model.y[2:end]) ./ 2
    model.cz = (model.z[1:end-1] .+ model.z[2:end]) ./ 2
    model.X, model.Y = meshgrid(model.y, model.x)
    model.Xc, model.Yc = meshgrid(model.cy, model.cx)
    model.nx = length(model.cx)
    model.ny = length(model.cy)
    model.nz = length(model.cz)

    top_surface = zeros(model.nx, model.ny)
    @inbounds for i in 1:model.nx, j in 1:model.ny
        column = view(model.A, i, j, :)
        air_index = findlast(isnan, column)
        sea_index = findlast(value -> abs(value - 0.3) < 1e-5, column)
        cut_index = max(air_index === nothing ? 0 : air_index, sea_index === nothing ? 0 : sea_index)
        cut_index = cut_index == model.nz ? model.nz - 1 : cut_index
        top_surface[i, j] = model.z[cut_index + 1]
    end
    model.Z = top_surface

    dx_mid = model.dx[clamp(round(Int, model.nx / 2), 1, length(model.dx))]
    dy_mid = model.dy[clamp(round(Int, model.ny / 2), 1, length(model.dy))]
    nx_core = count(==(dx_mid), model.dx)
    ny_core = count(==(dy_mid), model.dy)
    model.npad = (Int((model.nx - nx_core) ÷ 2), Int((model.ny - ny_core) ÷ 2))

    return model
end

function write_model_modem(outputfile::AbstractString, model::MTModel; rotation::Real = 0.0)
    return write_model_modem(outputfile, model.dx, model.dy, model.dz, model.A, model.origin; rotation = rotation)
end

function write_model_modem(outputfile::AbstractString,
    dx::AbstractVector, dy::AbstractVector, dz::AbstractVector,
    values::Array{<:Real, 3}, origin::AbstractVector;
    rotation::Real = 0.0)

    nx, ny, nz = size(values)
    written_values = copy(Float64.(values))
    written_values[isnan.(written_values)] .= 1e17
    written_values .= log.(written_values)

    open(outputfile, "w") do io
        println(io, "# Written by TerraScope.write_model_modem")
        println(io, "$nx $ny $nz 0 LOGE")

        for value in dx
            print(io, "$value ")
        end
        println(io)
        for value in dy
            print(io, "$value ")
        end
        println(io)
        for value in dz
            print(io, "$value ")
        end
        println(io)

        for k in 1:nz
            println(io)
            for j in 1:ny
                for i in nx:-1:1
                    @printf(io, "%15.5E", written_values[i, j, k])
                end
                println(io)
            end
        end

        ox = length(origin) >= 1 ? origin[1] : 0.0
        oy = length(origin) >= 2 ? origin[2] : 0.0
        oz = length(origin) >= 3 ? origin[3] : 0.0
        println(io, "$ox $oy $oz")
        println(io, "$rotation")
    end

    return outputfile
end

# ══════════════════════════════════════════════════════════════════════════════
#  jif3D  (https://git.tu-berlin.de/applied-geophysics/jif3d)
#  Readers for other inversion codes (VTK, ...) go in their own section below.
# ══════════════════════════════════════════════════════════════════════════════

# jif3d NetCDF models and data (https://git.tu-berlin.de/applied-geophysics/jif3d).
#
# jif3d works in absolute projected metres: X is northing, Y is easting and Z is depth,
# positive down. A model stores the end coordinate of every cell along each axis plus a
# separate `<axis>_Origin` for the first boundary. Arrays are written in C order as
# (Depth, Easting, Northing), so they read here as (Northing, Easting, Depth).

const JIF3D_MODEL_VARIABLES = (
    (name = "Conductivity", kind = :resistivity, units = "ohm m"),
    (name = "Density", kind = :density, units = "kg/m^3"),
    (name = "Susceptibility", kind = :susceptibility, units = "SI"),
)

is_jif3d_file(path::AbstractString) = lowercase(splitext(path)[2]) == ".nc"

function _jif3d_edges(ds, axis::AbstractString)
    ends = Float64.(collect(ds[axis][:]))
    origin_name = axis * "_Origin"
    origin = haskey(ds, origin_name) ? Float64(ds[origin_name][]) : 0.0
    edges = vcat(origin, ends)
    all(>(0), diff(edges)) || error("jif3d $axis boundaries are not strictly increasing.")
    return edges
end

_centers(edges) = (edges[1:end-1] .+ edges[2:end]) ./ 2

"""
    load_model_jif3D(path)

Read a jif3d `.nc` model. Conductivity is returned as resistivity in ohm m; density
(kg/m^3) and susceptibility (SI) are returned unchanged. `values` is indexed
(north, east, depth), with cell centres in `north`, `east` and `depth` (positive down).
"""
function load_model_jif3D(path::AbstractString)
    NCDataset(path) do ds
        entry = findfirst(v -> haskey(ds, v.name), JIF3D_MODEL_VARIABLES)
        entry === nothing && error("$(basename(path)) is not a jif3d model: none of " *
            join((v.name for v in JIF3D_MODEL_VARIABLES), ", ", " or ") * " is present.")
        spec = JIF3D_MODEL_VARIABLES[entry]
        var = ds[spec.name]
        dimnames(var) == ("Northing", "Easting", "Depth") ||
            error("Unexpected jif3d $(spec.name) dimensions $(dimnames(var)).")
        values = Float64.(coalesce.(var[:, :, :], NaN))
        if spec.kind === :resistivity
            values = map(s -> s > 0 ? 1.0 / s : NaN, values)
        end
        north_edges = _jif3d_edges(ds, "Northing")
        east_edges = _jif3d_edges(ds, "Easting")
        depth_edges = _jif3d_edges(ds, "Depth")
        size(values) == (length(north_edges) - 1, length(east_edges) - 1, length(depth_edges) - 1) ||
            error("jif3d $(spec.name) size $(size(values)) does not match its mesh.")
        return (kind = spec.kind, units = spec.units, name = splitext(basename(path))[1],
            values = values,
            north = _centers(north_edges), east = _centers(east_edges), depth = _centers(depth_edges),
            north_edges = north_edges, east_edges = east_edges, depth_edges = depth_edges)
    end
end

"""
    jif3d_axes_to_crs(east, north, source_crs, target_crs)

Map jif3d axis coordinates into `target_crs` as scene axes `(x = easting, y = northing)`.
Identical CRSs pass through unchanged. Otherwise each axis is transformed along the
centre line of the other, which keeps the grid rectilinear; that is exact for a pure
datum shift and a close approximation between neighbouring projected CRSs.
"""
function jif3d_axes_to_crs(east::AbstractVector, north::AbstractVector,
        source_crs::AbstractString, target_crs::AbstractString)
    src, dst = String(strip(source_crs)), String(strip(target_crs))
    uppercase(src) == uppercase(dst) && return collect(Float64, east), collect(Float64, north)
    transform = _xy_transform(src, dst)
    e_mid, n_mid = (first(east) + last(east)) / 2, (first(north) + last(north)) / 2
    x = [transform(e, n_mid)[1] for e in east]
    y = [transform(e_mid, n)[2] for n in north]
    return x, y
end
