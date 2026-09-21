"""Import settings. XY is always easting/northing (or longitude/latitude); Z is metres."""
Base.@kwdef struct ImportOptions
    format::Symbol = :xyz
    source_crs::String = ""
    kind::Symbol = :resistivity
    units::String = "ohm m"
    mesh_path::String = ""
    columns::NTuple{4,Int} = (1, 2, 3, 4)
    skip_rows::Int = 0
    positive_down::Bool = false
    nodata::Union{Nothing,Float64} = nothing
    log10_values::Bool = false
    # ModEM coordinates are north/east/down. Supply either an absolute source CRS,
    # or the geographic origin of a local mesh (optionally from a ModEM data header).
    origin_latlon::Union{Nothing,NTuple{2,Float64}} = nothing
    data_path::String = ""
    trim_padding::Bool = false
    max_depth_m::Union{Nothing,Float64} = nothing
    trace_xy::Symbol = :source
    display_mode::Symbol = :original
    sample_spacing_m::Float64 = 12.5
    top_z_m::Float64 = 0.0
    max_traces::Int = 1400
    max_samples::Int = 1200
end

struct ImportedGrid
    X::Matrix{Float64}
    Y::Matrix{Float64}
    z::Vector{Float64}
    values::Array{Float64,3}
end

struct ImportedPoints
    x::Vector{Float64}
    y::Vector{Float64}
    z::Vector{Float64}
    values::Vector{Float64}
end

struct ImportedLayer
    name::String
    path::String
    format::Symbol
    source_crs::String
    target_crs::String
    kind::Symbol
    units::String
    log10_values::Bool
    data::Any
    colorrange::Tuple{Float64,Float64}
end

mutable struct ImportSession
    target_crs::String
    layers::Vector{ImportedLayer}
    busy::Bool
end
ImportSession() = ImportSession("", ImportedLayer[], false)

function validate_project_crs(text::AbstractString)
    crs_text = strip(text)
    isempty(crs_text) && error("Choose the project coordinate system first.")
    crs = Proj.CRS(crs_text)
    Proj.is_projected(crs) && !Proj.is_compound(crs) ||
        error("Choose a projected CRS in metres, such as EPSG:28354 (GDA94 / MGA zone 54).")
    cs = Proj.proj_crs_get_coordinate_system(crs)
    cs == C_NULL && error("Cannot inspect CRS coordinate units.")
    try
        for axis in 0:1
            factor = Ref{Cdouble}(0)
            ok = Proj.proj_cs_get_axis_info(cs, axis, C_NULL, C_NULL, C_NULL,
                factor, C_NULL, C_NULL, C_NULL)
            ok == 1 && isapprox(factor[], 1.0; atol=1e-12) || error("Project XY units must be metres.")
        end
    finally
        Proj.proj_destroy(cs)
    end
    return String(crs_text)
end

function set_project_crs!(session::ImportSession, crs::AbstractString)
    session.busy && error("An import is in progress.")
    isempty(session.layers) || error("The project CRS is locked after the first import. Start a new session to change it.")
    session.target_crs = validate_project_crs(crs)
    return session
end

function _xy_transform(source::AbstractString, target::AbstractString)
    isempty(strip(source)) && error("Specify the source CRS; coordinates cannot be inferred from a filename.")
    Proj.CRS(source) # Validate even for the identity path.
    trans = source == target ? nothing : Proj.Transformation(source, target; always_xy=true)
    return (x, y) -> begin
        xy = isnothing(trans) ? (Float64(x), Float64(y)) : trans((Float64(x), Float64(y)))
        all(isfinite, xy) || error("Coordinate conversion produced non-finite coordinates; check the source CRS.")
        (Float64(xy[1]), Float64(xy[2]))
    end
end

const GEOGRAPHIC_CRS = "EPSG:4326"

"""Longitude/latitude bounds PROJ declares for a CRS, as (west,south,east,north)."""
function crs_area_of_use(spec::AbstractString)
    crs = Proj.CRS(spec)
    west, south, east, north = Ref{Cdouble}(NaN), Ref{Cdouble}(NaN), Ref{Cdouble}(NaN), Ref{Cdouble}(NaN)
    name = Ref{Cstring}()
    Proj.proj_get_area_of_use(crs.pj, west, south, east, north, name) == 1 || return nothing
    box = (west[], south[], east[], north[])
    return all(isfinite, box) ? box : nothing
end

_inside_area(lon, lat, box) = box[1] <= lon <= box[3] && box[2] <= lat <= box[4]

"""
Resolve the CRS of coordinate columns that carry no georeferencing metadata.

Degrees and projected metres do not overlap in practice: lon/lat is bounded by
±180/±90, while a metric CRS places survey data tens to hundreds of kilometres from
its false origin. When the columns are degrees but their order is ambiguous - both
within ±90, as anywhere outside the high-longitude bands - the target CRS's declared
area of use decides which column is longitude.

Returns `(source_crs, swap_xy)`; `swap_xy` is true for latitude-first files.
"""
function detect_xy_crs(x, y, target::AbstractString; allow_swap::Bool=true)
    (isempty(x) || isempty(y)) && error("No coordinates to inspect.")
    within(values, limit) = all(v -> -limit <= v <= limit, extrema(values))
    as_lonlat = within(x, 180) && within(y, 90)
    as_latlon = allow_swap && within(x, 90) && within(y, 180)
    # Neither reading fits the degree box, so the file is already metric. Any other
    # guess would silently move the data.
    (as_lonlat || as_latlon) || return (target, false)
    if as_lonlat && as_latlon
        box = crs_area_of_use(target)
        if !isnothing(box)
            direct = count(((lon,lat),) -> _inside_area(lon,lat,box), zip(x,y))
            swapped = count(((lat,lon),) -> _inside_area(lon,lat,box), zip(x,y))
            swapped > direct && return (GEOGRAPHIC_CRS, true)
        end
        return (GEOGRAPHIC_CRS, false)   # Fall back to the lon/lat column convention.
    end
    return (GEOGRAPHIC_CRS, as_latlon)
end

function _project_grid(x, y, transform)
    X = Matrix{Float64}(undef, length(x), length(y))
    Y = similar(X)
    for j in eachindex(y), i in eachindex(x)
        X[i,j], Y[i,j] = transform(x[i], y[j])
    end
    return X, Y
end

function _clean_values!(values, opts)
    for i in eachindex(values)
        v = values[i]
        values[i] = !isfinite(v) || (!isnothing(opts.nodata) && v == opts.nodata) ? NaN :
            opts.log10_values ? (v > 0 ? log10(v) : NaN) : v
    end
    any(isfinite, values) || error("No finite values remain after applying NoData/log settings.")
    return values
end

"""Read arbitrary XYZ pointsets without allocating a potentially enormous Cartesian grid."""
function read_xyz_points(path::AbstractString; columns=(1,2,3,4), skip_rows=0, positive_down=false)
    all(>(0), columns) && length(unique(columns)) == 4 || error("Choose four distinct positive column numbers.")
    skip_rows >= 0 || error("Header row count must be nonnegative.")
    arrays = ntuple(_ -> Float64[], 4)
    for (line_number, line) in enumerate(eachline(path))
        line_number <= skip_rows && continue
        raw = strip(first(split(line, '#'; limit=2)))
        (isempty(raw) || startswith(raw, "!")) && continue
        tokens = occursin(r"[,;]",raw) ? strip.(split(raw,r"[,;]";keepempty=true)) : split(raw)
        length(tokens) >= maximum(columns) || error("$path:$line_number: expected at least $(maximum(columns)) columns.")
        for k in 1:4
            value = tryparse(Float64, replace(tokens[columns[k]], 'D'=>'E', 'd'=>'e'))
            isnothing(value) && error("$path:$line_number: nonnumeric column $(columns[k]); set Header rows for text headers.")
            k <= 3 && !isfinite(value) && error("$path:$line_number: coordinate is not finite.")
            push!(arrays[k], value)
        end
    end
    isempty(arrays[1]) && error("No XYZ records found.")
    positive_down && (arrays[3] .*= -1)
    return ImportedPoints(arrays...)
end

function companion_mesh(path::AbstractString)
    stem = lowercase(splitext(basename(path))[1])
    matches = filter(readdir(dirname(abspath(path)); join=true)) do candidate
        root, ext = splitext(basename(candidate))
        lowercase(root) == stem && lowercase(ext) in (".msh", ".mesh") && isfile(candidate)
    end
    length(matches) == 1 || error("Select the UBC mesh file explicitly; expected one same-name .msh or .mesh companion.")
    return only(matches)
end

function _numeric_tokens(path)
    tokens = String[]
    for line in eachline(path)
        raw = strip(first(split(line, r"[!#]"; limit=2)))
        append!(tokens, split(raw))
    end
    return tokens
end

"""UBC tensor mesh: southwest top origin; values ordered Z fastest, then X, then Y."""
function read_ubc_model(path::AbstractString; mesh_path::AbstractString=companion_mesh(path))
    tokens = _numeric_tokens(mesh_path)
    length(tokens) >= 6 || error("Incomplete UBC mesh header.")
    nx, ny, nz = parse.(Int, tokens[1:3])
    all(>(0), (nx,ny,nz)) || error("UBC mesh dimensions must be positive.")
    origin = parse.(Float64, tokens[4:6])
    widths = Float64[]
    total = Base.checked_add(Base.checked_add(nx,ny),nz)
    for token in tokens[7:end]
        parts = split(token, '*')
        length(parts) <= 2 || error("Invalid UBC cell width: $token")
        count = length(parts) == 2 ? parse(Int, parts[1]) : 1
        width = parse(Float64, last(parts))
        count > 0 && isfinite(width) && width > 0 || error("UBC widths and repeat counts must be positive.")
        length(widths) + count <= total || error("Too many UBC cell widths.")
        append!(widths, Iterators.repeated(width, count))
    end
    length(widths) == total || error("UBC mesh cell width count mismatch.")
    dx, dy, dz = widths[1:nx], widths[nx+1:nx+ny], widths[nx+ny+1:end]
    x = origin[1] .+ cumsum(dx) .- dx ./ 2
    y = origin[2] .+ cumsum(dy) .- dy ./ 2
    z = origin[3] .- cumsum(dz) .+ dz ./ 2
    n = Base.checked_mul(Base.checked_mul(nx,ny),nz)
    values = Vector{Float64}(undef,n)
    index = 0
    for line in eachline(path)
        raw = first(split(line, r"[!#]"; limit=2))
        for token in split(raw)
            index += 1
            index <= n || error("UBC model has more values than mesh cells.")
            values[index] = parse(Float64, token)
        end
    end
    index == n || error("UBC model has $index values; mesh requires $n.")
    return x, y, z, permutedims(reshape(values,nz,nx,ny),(2,3,1))
end

# Read only the georeferencing header, not the full impedance response dataset.
function _modem_origin(path)
    headers = String[]
    for line in eachline(path)
        raw = strip(line)
        startswith(raw, ">") || continue
        push!(headers, strip(raw[2:end]))
        if length(headers) == 5
            values = parse.(Float64, split(headers[5]))
            length(values) == 2 || error("Invalid ModEM geographic origin header.")
            return (values[1], values[2])
        end
    end
    error("ModEM data file has no geographic origin header.")
end

function _load_modem_import(path, opts, target)
    dx, dy, dz, values, _, scale, origin, rotation = read_mackie3d_model(path)
    all(w -> isfinite(w) && w > 0, Iterators.flatten((dx,dy,dz))) || error("ModEM cell widths must be positive.")
    scale == "LOGE" && (values .= exp.(values))
    scale == "LOG10" && (values .= 10.0 .^ values)
    values[values .> 1e15] .= NaN
    north = origin[1] .+ cumsum(dx) .- dx ./ 2
    east = origin[2] .+ cumsum(dy) .- dy ./ 2
    z = .-(origin[3] .+ cumsum(dz) .- dz ./ 2)
    latlon = isempty(opts.data_path) ? opts.origin_latlon : _modem_origin(opts.data_path)
    source = opts.source_crs
    if !isnothing(latlon)
        lat, lon = latlon
        -90 < lat < 90 && -180 <= lon <= 180 || error("Invalid ModEM origin latitude/longitude.")
        source = "+proj=tmerc +lat_0=$lat +lon_0=$lon +k=0.9996 +x_0=0 +y_0=0 +datum=WGS84 +units=m +type=crs"
    end
    transform = _xy_transform(source,target)
    # Clockwise rotation of the ModEM north axis toward east.
    s, c = sind(rotation), cosd(rotation)
    ix = opts.trim_padding ? core_indices(north) : eachindex(north)
    iy = opts.trim_padding ? core_indices(east) : eachindex(east)
    if !isnothing(opts.max_depth_m)
        isfinite(opts.max_depth_m) && opts.max_depth_m > 0 || error("Maximum depth must be positive.")
    end
    iz = isnothing(opts.max_depth_m) ? eachindex(z) : findall(>=(-opts.max_depth_m),z)
    isempty(iz) && error("No model cells fall inside the selected depth range.")
    X, Y = _project_grid(east[iy], north[ix], (e,n) -> transform(c*e+s*n, -s*e+c*n))
    return ImportedGrid(X,Y,z[iz],permutedims(view(values,ix,iy,iz),(2,1,3))), source
end

function load_import(path::AbstractString, opts::ImportOptions, target_crs::AbstractString)
    target = validate_project_crs(target_crs)
    isfile(path) || error("File not found: $path")
    source = opts.source_crs
    # Formats that carry no georeferencing of their own resolve a blank source CRS from
    # the coordinates themselves, once those have actually been read.
    autodetect = opts.format in (:xyz,:ubc,:voxel) && isempty(strip(source))
    transform = (!autodetect && opts.format in (:xyz,:ubc,:voxel,:seismic)) ? _xy_transform(source,target) : nothing
    data = if opts.format == :modem
        grid, source = _load_modem_import(path,opts,target)
        grid
    elseif opts.format == :xyz
        points = read_xyz_points(path; columns=opts.columns, skip_rows=opts.skip_rows, positive_down=opts.positive_down)
        if autodetect
            source, swap_xy = detect_xy_crs(points.x,points.y,target)
            if swap_xy
                for i in eachindex(points.x)
                    points.x[i], points.y[i] = points.y[i], points.x[i]
                end
            end
            transform = _xy_transform(source,target)
        end
        for i in eachindex(points.x)
            points.x[i], points.y[i] = transform(points.x[i],points.y[i])
        end
        points
    elseif opts.format == :ubc
        mesh = isempty(opts.mesh_path) ? companion_mesh(path) : opts.mesh_path
        x,y,z,values = read_ubc_model(path; mesh_path=mesh)
        # Grid axes are separate vectors, so a latitude-first file cannot be repaired by
        # swapping columns; only degrees-versus-metres is inferred here.
        autodetect && ((source,_) = detect_xy_crs(x,y,target;allow_swap=false); transform = _xy_transform(source,target))
        X,Y = _project_grid(x,y,transform)
        ImportedGrid(X,Y,z,values)
    elseif opts.format == :voxel
        volume = load_density_volume(path)
        autodetect && ((source,_) = detect_xy_crs(volume.x,volume.y,target;allow_swap=false); transform = _xy_transform(source,target))
        X,Y = _project_grid(volume.x,volume.y,transform)
        ImportedGrid(X,Y,volume.z,volume.values)
    elseif opts.format == :shapefile
        if isempty(strip(source))
            prj = splitext(path)[1] * ".prj"
            isfile(prj) || error("Shapefile has no .prj; supply its source CRS.")
            source = strip(read(prj,String))
        end
        segments = shapefile_segments(path; post_transform=_xy_transform(source,target))
        isempty(segments) && error("Shapefile contains no supported nonempty geometry.")
        segments
    elseif opts.format == :seismic
        curtain = load_seismic_curtain_from_segy(path; trace_xy=opts.trace_xy,
            display_mode=opts.display_mode, sample_spacing_m=opts.sample_spacing_m,
            top_z_m=opts.top_z_m, max_traces=opts.max_traces, max_samples=opts.max_samples)
        for i in eachindex(curtain.line_x)
            x,y = transform(curtain.line_x[i],curtain.line_y[i])
            curtain.line_x[i],curtain.line_y[i] = x,y
            curtain.X[i,:] .= x
            curtain.Y[i,:] .= y
        end
        curtain
    elseif opts.format == :raster
        isdefined(@__MODULE__, :ArchGDAL) || (@eval import ArchGDAL)
        grid, source = Base.invokelatest(_load_raster_import,path,opts,target)
        grid
    else
        error("Unsupported import format: $(opts.format)")
    end
    range = if data isa Union{ImportedGrid,ImportedPoints}
        _clean_values!(data.values,opts)
        compute_colorrange(data.values)
    else
        (0.0,1.0)
    end
    return ImportedLayer(basename(path),abspath(path),opts.format,source,target,
        opts.kind,opts.units,opts.log10_values,data,range)
end

"""Serial, transactional import: a failed load never changes existing layers."""
function import_layer!(session::ImportSession, path::AbstractString, opts::ImportOptions)
    isempty(session.target_crs) && error("Choose the project coordinate system first.")
    session.busy && error("An import is already in progress.")
    session.busy = true
    try
        layer = load_import(path,opts,session.target_crs)
        push!(session.layers,layer)
        return layer
    finally
        session.busy = false
    end
end

"""Nearest grid index for `v` on an ascending axis."""
function _nearest_axis_index(sorted::Vector{Float64}, v::Float64)
    n = length(sorted)
    n == 1 && return 1
    i = searchsortedfirst(sorted, v)
    i <= 1 && return 1
    i > n && return n
    return (v - sorted[i - 1]) <= (sorted[i] - v) ? i - 1 : i
end

"""Grow the filled cells into the empty ones, one shell of six neighbours per pass."""
function _fill_grid_gaps!(values::Array{Float64,3}; max_passes::Int = 64)
    nx, ny, nz = size(values)
    neighbours = ((-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1))
    for _ in 1:max_passes
        any(isnan, values) || return values
        source = copy(values)
        filled = false
        for k in 1:nz, j in 1:ny, i in 1:nx
            isnan(values[i, j, k]) || continue
            total, hits = 0.0, 0
            for (di, dj, dk) in neighbours
                ii, jj, kk = i + di, j + dj, k + dk
                (1 <= ii <= nx && 1 <= jj <= ny && 1 <= kk <= nz) || continue
                v = source[ii, jj, kk]
                isnan(v) && continue
                total += v
                hits += 1
            end
            if hits > 0
                values[i, j, k] = total / hits
                filled = true
            end
        end
        filled || break
    end
    return values
end

"""
    resample_points_to_axes(points, x, y, z) -> Array{Float64,3}

Resample a scattered point cloud onto the rectilinear grid `x × y × z`, which must be
in the same coordinate system as the points. Each point goes to its nearest cell, cells
that collect several points average them, and cells that collect none are grown in from
their filled neighbours. Returns `values[ix, iy, iz]` in the order the axes were given,
plus the fraction of cells that were filled directly from points.
"""
function resample_points_to_axes(points::ImportedPoints, x::AbstractVector{<:Real},
        y::AbstractVector{<:Real}, z::AbstractVector{<:Real})
    axes = map(axis -> (a = Float64.(collect(axis)); p = sortperm(a); (a[p], invperm(p))), (x, y, z))
    (xs, xi), (ys, yi), (zs, zi) = axes
    nx, ny, nz = length(xs), length(ys), length(zs)
    sums = zeros(Float64, nx, ny, nz)
    counts = zeros(Int, nx, ny, nz)
    for n in eachindex(points.values)
        v = points.values[n]
        isfinite(v) || continue
        i = _nearest_axis_index(xs, points.x[n])
        j = _nearest_axis_index(ys, points.y[n])
        k = _nearest_axis_index(zs, points.z[n])
        sums[i, j, k] += v
        counts[i, j, k] += 1
    end
    hits = count(!iszero, counts)
    hits == 0 && error("No finite points to resample onto the grid.")
    values = [counts[i, j, k] == 0 ? NaN : sums[i, j, k] / counts[i, j, k]
              for i in 1:nx, j in 1:ny, k in 1:nz]
    _fill_grid_gaps!(values)
    return values[xi, yi, zi], hits / length(counts)
end

"""
    axes_from_points(points; max_cells = 128) -> (x, y, z)

Rectilinear axes covering a point cloud, for gridding a file that has no mesh of its
own. Gridded survey and model files repeat their coordinates exactly, so an axis with
few distinct values keeps precisely those values — which is how layered depth columns
survive intact; any other axis is divided into uniform cells instead, as many as the
number of points supports.
"""
function axes_from_points(points::ImportedPoints; max_cells::Int = 128)
    n = length(points.values)
    n == 0 && error("The point cloud is empty.")
    exact(v) = (u = sort!(unique(Float64.(v))); length(u) <= max_cells ? u : nothing)
    function uniform(v, count)
        lo, hi = extrema(Float64.(v))
        hi <= lo && return [lo]
        return collect(range(lo, hi; length = max(count, 2)))
    end
    z = exact(points.z)
    nz = z === nothing ? clamp(round(Int, cbrt(n)), 4, max_cells) : length(z)
    nxy = clamp(round(Int, sqrt(n / nz)), 8, max_cells)
    z === nothing && (z = uniform(points.z, nz))
    return something(exact(points.x), uniform(points.x, nxy)),
           something(exact(points.y), uniform(points.y, nxy)),
           z
end
