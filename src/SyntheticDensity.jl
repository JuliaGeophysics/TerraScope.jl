function generate_synthetic_density(model::MTModel; background::Real = 2670.0, max_depth::Union{Nothing, Real} = nothing)
    x, y, zpos, _, _, _, _ = prepare_model_arrays(model; log10scale = false, with_padding = false, max_depth = max_depth)
    z = -zpos
    nx, ny, nz = length(x), length(y), length(z)
    values = fill(Float64(background), nx, ny, nz)

    xmid = 0.5 * (minimum(x) + maximum(x))
    ymid = 0.5 * (minimum(y) + maximum(y))
    xspan = max(maximum(x) - minimum(x), 1.0)
    yspan = max(maximum(y) - minimum(y), 1.0)
    zspan = max(abs(minimum(z)) - abs(maximum(z)), 1.0)

    for i in 1:nx, j in 1:ny, k in 1:nz
        xr = (x[i] - xmid) / (0.22 * xspan)
        yr = (y[j] - ymid) / (0.28 * yspan)
        zr = ((-z[k]) - 0.45 * maximum(-z)) / max(0.18 * maximum(-z), 1.0)
        if xr^2 + yr^2 + zr^2 <= 1.0
            values[i, j, k] += 210.0
        end

        xr2 = (x[i] - (xmid - 0.24 * xspan)) / (0.12 * xspan)
        yr2 = (y[j] - (ymid + 0.15 * yspan)) / (0.18 * yspan)
        zr2 = ((-z[k]) - 0.18 * maximum(-z)) / max(0.12 * maximum(-z), 1.0)
        if xr2^2 + yr2^2 + zr2^2 <= 1.0
            values[i, j, k] -= 160.0
        end

        trend = 35.0 * ((-z[k]) / max(maximum(-z), 1.0))
        ridge = 55.0 * exp(-((x[i] - (xmid + 0.18 * xspan))^2) / (2 * (0.11 * xspan)^2))
        values[i, j, k] += trend + ridge * exp(-((y[j] - ymid)^2) / (2 * (0.08 * yspan)^2))
    end

    metadata = Dict{Symbol, Any}(
        :background => Float64(background),
        :value_scale => :linear,
        :source => :synthetic,
    )
    return ScalarVolume("Synthetic Density", :density, values, x, y, z, "kg/m^3", metadata)
end

function save_density_volume(path::AbstractString, volume::ScalarVolume)
    open(path, "w") do io
        println(io, "# TerraScope voxel volume")
        println(io, "name=" * volume.name)
        println(io, "kind=" * String(volume.kind))
        println(io, "units=" * volume.units)
        println(io, "dims=$(length(volume.x)) $(length(volume.y)) $(length(volume.z))")
        println(io, "x=" * join(volume.x, ' '))
        println(io, "y=" * join(volume.y, ' '))
        println(io, "z=" * join(volume.z, ' '))
        for k in 1:length(volume.z)
            println(io, "slice=$k")
            for j in 1:length(volume.y)
                println(io, join(volume.values[:, j, k], ' '))
            end
        end
    end
    return path
end

function load_density_volume(path::AbstractString)
    lines = readlines(path)
    meta = Dict{String, String}()
    data_start = 1
    for (idx, line) in enumerate(lines)
        stripped = strip(line)
        isempty(stripped) && continue
        if startswith(stripped, "slice=")
            data_start = idx
            break
        elseif startswith(stripped, "#")
            continue
        elseif occursin('=', stripped)
            key, value = split(stripped, '='; limit = 2)
            meta[strip(key)] = strip(value)
        end
    end

    dims = parse.(Int, split(meta["dims"]))
    x = parse.(Float64, split(meta["x"]))
    y = parse.(Float64, split(meta["y"]))
    z = parse.(Float64, split(meta["z"]))
    values = zeros(Float64, dims[1], dims[2], dims[3])

    current_k = 0
    current_j = 0
    for line in lines[data_start:end]
        stripped = strip(line)
        isempty(stripped) && continue
        if startswith(stripped, "slice=")
            current_k = parse(Int, split(stripped, '='; limit = 2)[2])
            current_j = 0
            continue
        end
        current_j += 1
        values[:, current_j, current_k] = parse.(Float64, split(stripped))
    end

    metadata = Dict{Symbol, Any}(:source => :file, :value_scale => :linear)
    return ScalarVolume(get(meta, "name", "Density"), Symbol(get(meta, "kind", "density")), values, x, y, z, get(meta, "units", "kg/m^3"), metadata)
end