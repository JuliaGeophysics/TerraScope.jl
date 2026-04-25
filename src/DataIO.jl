function make_nan_data()
    return MTData(
        Float64[], Float64[], Matrix{Float64}(undef, 0, 0), Matrix{Float64}(undef, 0, 0),
        String[], Matrix{Float64}(undef, 0, 0), 0, 0, 0, String[],
        Array{ComplexF64}(undef, 0, 0, 0), Array{ComplexF64}(undef, 0, 0, 0),
        Array{Float64}(undef, 0, 0, 0), Array{Float64}(undef, 0, 0, 0),
        Array{Float64}(undef, 0, 0, 0), Array{Float64}(undef, 0, 0, 0),
        Array{ComplexF64}(undef, 0, 0, 0), Array{ComplexF64}(undef, 0, 0, 0),
        Float64[], Float64[], Float64[], Float64[], "", "",
    )
end

strip_gt(s::AbstractString) = startswith(strip(s), ">") ? strip(strip(s)[2:end]) : strip(s)
safeparsefloat(s) = something(tryparse(Float64, s), 0.0)

function is_dataline(line::AbstractString)
    t = strip(line)
    return !isempty(t) && !startswith(t, "#") && !startswith(t, ">") && occursin(r"^[\s\+\-\.0-9]", t)
end

function calc_rho_pha(Z::Array{ComplexF64, 3}, Zerr::Array{ComplexF64, 3}, T::Vector{Float64})
    nf, ncomp, ns = size(Z)
    mu0 = 4pi * 1e-7
    rho = fill(NaN, nf, ncomp, ns)
    phi = fill(NaN, nf, ncomp, ns)
    rhoerr = fill(NaN, nf, ncomp, ns)
    phierr = fill(NaN, nf, ncomp, ns)
    for i in 1:nf
        omega = 2pi / T[i]
        for j in 1:ncomp, k in 1:ns
            zval = Z[i, j, k]
            if isfinite(real(zval)) && isfinite(imag(zval))
                rho_a = abs(zval)^2 / (omega * mu0)
                phi_a = rad2deg(angle(zval))
                rho[i, j, k] = rho_a
                phi[i, j, k] = phi_a
                zerr = Zerr[i, j, k]
                if isfinite(real(zerr)) && isfinite(imag(zerr))
                    abs_z = abs(zval)
                    delta_z = abs(zerr)
                    if abs_z > 0
                        rhoerr[i, j, k] = 2 * rho_a * (delta_z / abs_z)
                        phierr[i, j, k] = rad2deg(delta_z / abs_z)
                    end
                end
            end
        end
    end
    return rho, phi, rhoerr, phierr
end

function load_data_modem(path::AbstractString)
    mu0 = 4pi * 1e-7
    data = make_nan_data()
    data.name = path

    T = Float64[]
    site = String[]
    loc_lat = Float64[]
    loc_lon = Float64[]
    loc_elev = Float64[]
    xvals = Float64[]
    yvals = Float64[]
    zvals = Float64[]
    responses = String[]
    values = ComplexF64[]
    errors = ComplexF64[]
    header_units = String[]
    signs = Int[]
    rotations = Float64[]
    origins = Vector{NTuple{2, Float64}}()

    open(path, "r") do io
        while !eof(io)
            raw = readline(io)
            stripped = strip(raw)
            isempty(stripped) && continue
            if startswith(stripped, "#")
                continue
            elseif startswith(stripped, ">")
                headers = String[stripped]
                for _ in 1:5
                    eof(io) && break
                    push!(headers, readline(io))
                end
                push!(signs, occursin("-", lowercase(strip_gt(headers[2]))) ? -1 : 1)
                push!(header_units, strip_gt(headers[3]))
                rotation_tokens = split(strip_gt(headers[4]))
                push!(rotations, isempty(rotation_tokens) ? 0.0 : safeparsefloat(rotation_tokens[1]))
                origin_tokens = split(strip_gt(headers[5]))
                push!(origins, (
                    length(origin_tokens) >= 1 ? safeparsefloat(origin_tokens[1]) : 0.0,
                    length(origin_tokens) >= 2 ? safeparsefloat(origin_tokens[2]) : 0.0,
                ))
            elseif is_dataline(stripped)
                parts = split(stripped)
                length(parts) < 11 && continue
                push!(T, parse(Float64, parts[1]))
                push!(site, parts[2])
                push!(loc_lat, parse(Float64, parts[3]))
                push!(loc_lon, parse(Float64, parts[4]))
                push!(loc_elev, parse(Float64, parts[7]))
                push!(xvals, parse(Float64, parts[5]))
                push!(yvals, parse(Float64, parts[6]))
                push!(zvals, parse(Float64, parts[7]))
                push!(responses, parts[8])
                re = parse(Float64, parts[9])
                im = parse(Float64, parts[10])
                sigma = parse(Float64, parts[11])
                push!(values, ComplexF64(re, im))
                push!(errors, ComplexF64(sigma, sigma))
            end
        end
    end

    unique_sites = unique(site)
    site_indices = [findfirst(==(s), site) for s in unique_sites]
    data.site = unique_sites
    data.ns = length(unique_sites)
    data.loc = hcat(loc_lat, loc_lon, loc_elev)[site_indices, :]
    data.x = xvals[site_indices]
    data.y = yvals[site_indices]
    data.z = zvals[site_indices]
    data.T = sort(unique(T))
    data.f = 1.0 ./ data.T
    data.nf = length(data.f)
    data.responses = unique(responses)
    data.nr = length(data.responses)

    data.Z = fill(ComplexF64(NaN, NaN), data.nf, 4, data.ns)
    data.Zerr = fill(ComplexF64(NaN, NaN), data.nf, 4, data.ns)
    data.rho = fill(NaN, data.nf, 4, data.ns)
    data.rhoerr = fill(NaN, data.nf, 4, data.ns)
    data.phi = fill(NaN, data.nf, 4, data.ns)
    data.phierr = fill(NaN, data.nf, 4, data.ns)
    data.tip = fill(ComplexF64(NaN, NaN), data.nf, 2, data.ns)
    data.tiperr = fill(ComplexF64(NaN, NaN), data.nf, 2, data.ns)

    compidx = Dict("ZXX" => 1, "ZXY" => 2, "ZYX" => 3, "ZYY" => 4, "TX" => 5, "TY" => 6)
    for i in eachindex(T)
        ifreq = findfirst(==(T[i]), data.T)
        isite = findfirst(==(site[i]), data.site)
        icomp = get(compidx, responses[i], 0)
        if !(isnothing(ifreq) || isnothing(isite) || icomp == 0)
            if icomp >= 5
                data.tip[ifreq, icomp - 4, isite] = values[i]
                data.tiperr[ifreq, icomp - 4, isite] = errors[i]
            else
                data.Z[ifreq, icomp, isite] = values[i]
                data.Zerr[ifreq, icomp, isite] = errors[i]
            end
        end
    end

    for units in header_units
        compact = lowercase(replace(strip(units), " " => ""))
        if compact == "[mv/km]/[nt]"
            data.Z .*= (mu0 * 1000)
            data.Zerr .*= (mu0 * 1000)
            break
        elseif compact == "[v/m]/[t]" || compact == "[]"
            break
        end
    end

    if !isempty(origins)
        data.origin = [origins[1][1], origins[1][2], 0.0]
    else
        data.origin = [0.0, 0.0, 0.0]
    end
    if !isempty(rotations)
        data.zrot = fill(rotations[1], data.nf, data.ns)
        data.trot = data.zrot
    else
        data.zrot = zeros(data.nf, data.ns)
        data.trot = data.zrot
    end
    if !isempty(signs) && signs[1] == -1
        data.Z .= conj.(data.Z)
        data.tip .= conj.(data.tip)
    end

    data.rho, data.phi, data.rhoerr, data.phierr = calc_rho_pha(data.Z, data.Zerr, data.T)
    return data
end

function _write_data_block_header!(io;
    datatype::AbstractString,
    sign::Int,
    units::AbstractString,
    rotation::Real,
    origin_lat::Real,
    origin_lon::Real,
    nf::Int,
    ns::Int)

    signline = sign == -1 ? "exp(-iwt)" : "exp(+iwt)"
    println(io, "> $datatype")
    println(io, "> $signline")
    println(io, "> $units")
    println(io, "> $(rotation)")
    println(io, "> $(origin_lat) $(origin_lon)")
    println(io, "> $(nf) $(ns)")
end

function write_data_modem(outputfile::AbstractString, data::MTData;
    sign::Int = 1,
    units::AbstractString = "[V/m]/[T]",
    rotation::Union{Nothing, Real} = nothing,
    include_impedance::Bool = true,
    include_tipper::Bool = true)

    ns = data.ns
    nf = data.nf
    ns == 0 && error("Data has zero stations.")
    nf == 0 && error("Data has zero periods.")
    size(data.loc, 1) == ns || error("Data loc array does not match station count.")

    rotation_value = if isnothing(rotation)
        if !isempty(data.zrot)
            value = data.zrot[1]
            isfinite(value) ? value : 0.0
        else
            0.0
        end
    else
        Float64(rotation)
    end

    origin_lat = length(data.origin) >= 1 ? data.origin[1] : 0.0
    origin_lon = length(data.origin) >= 2 ? data.origin[2] : 0.0

    open(outputfile, "w") do io
        println(io, "# Written by TerraScope.write_data_modem")

        if include_impedance
            _write_data_block_header!(io;
                datatype = "Full_Impedance",
                sign = sign,
                units = units,
                rotation = rotation_value,
                origin_lat = origin_lat,
                origin_lon = origin_lon,
                nf = nf,
                ns = ns)

            comp_labels = ("ZXX", "ZXY", "ZYX", "ZYY")
            for isite in 1:ns
                site = data.site[isite]
                lat = data.loc[isite, 1]
                lon = data.loc[isite, 2]
                elev = data.loc[isite, 3]
                x = data.x[isite]
                y = data.y[isite]
                for ip in 1:nf
                    period = data.T[ip]
                    for icomp in 1:4
                        zval = data.Z[ip, icomp, isite]
                        if isfinite(real(zval)) && isfinite(imag(zval))
                            err = abs(data.Zerr[ip, icomp, isite])
                            err_out = (isfinite(err) && err > 0) ? err : 1e12
                            println(io, "$(period) $(site) $(lat) $(lon) $(x) $(y) $(elev) $(comp_labels[icomp]) $(real(zval)) $(imag(zval)) $(err_out)")
                        end
                    end
                end
            end
        end

        if include_tipper
            _write_data_block_header!(io;
                datatype = "Full_Vertical_Components",
                sign = sign,
                units = units,
                rotation = rotation_value,
                origin_lat = origin_lat,
                origin_lon = origin_lon,
                nf = nf,
                ns = ns)

            tip_labels = ("TX", "TY")
            for isite in 1:ns
                site = data.site[isite]
                lat = data.loc[isite, 1]
                lon = data.loc[isite, 2]
                elev = data.loc[isite, 3]
                x = data.x[isite]
                y = data.y[isite]
                for ip in 1:nf
                    period = data.T[ip]
                    for icomp in 1:2
                        tipval = data.tip[ip, icomp, isite]
                        if isfinite(real(tipval)) && isfinite(imag(tipval))
                            err = abs(data.tiperr[ip, icomp, isite])
                            err_out = (isfinite(err) && err > 0) ? err : 1e12
                            println(io, "$(period) $(site) $(lat) $(lon) $(x) $(y) $(elev) $(tip_labels[icomp]) $(real(tipval)) $(imag(tipval)) $(err_out)")
                        end
                    end
                end
            end
        end
    end

    return outputfile
end

default_data_dir() = joinpath(dirname(@__DIR__), "Data")

function discover_dataset_paths(root::AbstractString = default_data_dir())
    rho_files = String[]
    dat_files = String[]
    vox_files = String[]
    shp_files = String[]
    segy_files = String[]

    if !isdir(root)
        return (rho = nothing, dat = nothing, density = nothing, shapefiles = String[], segy_files = String[])
    end

    for (dir, _, files) in walkdir(root)
        for file in files
            path = joinpath(dir, file)
            lower = lowercase(file)
            if endswith(lower, ".rho")
                push!(rho_files, path)
            elseif endswith(lower, ".dat")
                push!(dat_files, path)
            elseif endswith(lower, ".vox")
                push!(vox_files, path)
            elseif endswith(lower, ".shp")
                push!(shp_files, path)
            elseif endswith(lower, ".sgy") || endswith(lower, ".segy")
                push!(segy_files, path)
            end
        end
    end

    sort!(rho_files)
    sort!(dat_files)
    sort!(vox_files)
    sort!(shp_files)
    sort!(segy_files)
    return (
        rho = isempty(rho_files) ? nothing : first(rho_files),
        dat = isempty(dat_files) ? nothing : first(dat_files),
        density = isempty(vox_files) ? nothing : first(vox_files),
        shapefiles = shp_files,
        segy_files = segy_files,
    )
end

function volume_from_model(model::MTModel; with_padding::Bool = false, max_depth::Union{Nothing, Real} = nothing, pad_tol::Real = 0.2)
    x, y, zpos, values, _, _, _ = prepare_model_arrays(model; log10scale = true, with_padding = with_padding, max_depth = max_depth, pad_tol = pad_tol)
    metadata = Dict{Symbol, Any}(
        :value_scale => :log10,
        :physical_units => "ohm_m",
        :display_units => "log10(ohm_m)",
        :source_model => model.name,
    )
    return ScalarVolume("Resistivity", :resistivity, values, x, y, -zpos, "log10(ohm_m)", metadata)
end

function load_dataset_bundle(root::AbstractString = default_data_dir(); with_padding::Bool = false, max_depth::Union{Nothing, Real} = nothing, pad_tol::Real = 0.2)
    paths = discover_dataset_paths(root)
    paths.rho === nothing && error("No ModEM .rho model found in $root")

    model = load_model_modem(paths.rho)
    mt_data = paths.dat === nothing ? nothing : load_data_modem(paths.dat)
    resistivity = volume_from_model(model; with_padding = with_padding, max_depth = max_depth, pad_tol = pad_tol)

    density = if paths.density !== nothing && isfile(paths.density)
        load_density_volume(paths.density)
    else
        nothing
    end

    return DatasetBundle(root, model, mt_data, resistivity, density, paths.shapefiles, paths.segy_files)
end