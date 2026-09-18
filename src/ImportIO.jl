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
    transform = opts.format in (:xyz,:ubc,:voxel,:seismic) ? _xy_transform(source,target) : nothing
    data = if opts.format == :modem
        grid, source = _load_modem_import(path,opts,target)
        grid
    elseif opts.format == :xyz
        points = read_xyz_points(path; columns=opts.columns, skip_rows=opts.skip_rows, positive_down=opts.positive_down)
        for i in eachindex(points.x)
            points.x[i], points.y[i] = transform(points.x[i],points.y[i])
        end
        points
    elseif opts.format == :ubc
        mesh = isempty(opts.mesh_path) ? companion_mesh(path) : opts.mesh_path
        x,y,z,values = read_ubc_model(path; mesh_path=mesh)
        X,Y = _project_grid(x,y,transform)
        ImportedGrid(X,Y,z,values)
    elseif opts.format == :voxel
        volume = load_density_volume(path)
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
