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
    nx, ny, nz, nz_air = ints[1], ints[2], ints[3], ints[4]
    scale_type = occursin("LOGE", header) ? "LOGE" : "LINEAR"

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