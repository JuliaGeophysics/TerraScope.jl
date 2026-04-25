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