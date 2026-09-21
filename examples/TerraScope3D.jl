# Example: interactive 3D model viewer with user-defined lat/lon cross-sections.
# Author: @pankajkmishra
# This script displays one horizontal map slice plus only selected cross-sections.
# Cross-sections are defined by endpoint pairs in (lat, lon), and each can be slid
# across the model with its own slider.

using GLMakie
GLMakie.activate!()
using Statistics
using Dates
using SegyIO
using Shapefile
using GeoInterface
using Proj
using FFTW
using TerraScope: core_indices, edges_from_centers, load_data_modem, load_density_volume, load_model_modem, z_indices_for_max_depth
import TerraScope   # File readers shared with the package (ImportOptions, resampling).

# -------------------- Input Files --------------------
# Every input is optional. A method's `_model` is the 3D volume and its `_data` is the
# measured dataset that georeferences it; see `_resolve_frame` further down for how the
# two combine. With nothing configured at all the viewer opens an empty 3D scene.

function _merge_launch_config(base::NamedTuple, override::NamedTuple)
    return (; (name => begin
        base_val = getfield(base, name)
        if haskey(override, name)
            override_val = getfield(override, name)
            if base_val isa NamedTuple && override_val isa NamedTuple
                _merge_launch_config(base_val, override_val)
            else
                override_val
            end
        else
            base_val
        end
    end for name in keys(base))...)
end

DEFAULT_TERRASCOPE_LAUNCH_CONFIG = (
    inputs = (                       # Absolute paths; "" means the input is not used.
        MT_model = "", MT_data = "",
        gravity_model = "", gravity_data = "",
        magnetic_model = "", magnetic_data = "",
        seismic_data = "",
    ),
    shapefiles = NamedTuple[],       # (path =, color =, width =, alpha =) per file.
    model = (
        log10_scale = true,
        colormap = :Spectral,
        max_depth_m = 50000.0,
        show_padding = false,
        pad_tolerance = 0.2,
        section_samples_along = 360,
        display_ranges = (
            resistivity = (1.0, 4.0),
            density = nothing,
            susceptibility = nothing,
        ),
    ),
    view = (
        default_view_direction = (-0.15, -1.05, 0.72),
        default_view_scale = 1.12,
        show_only_3d_scene = false,
        open_fullscreen = true,
        show_outer_ticks_axis = true,
        export_png_scale = 4,
    ),
    overlay = (
        z_fixed = 0.0,
        auto_reproject_to_wgs84 = true,
        line_color = :black,
        line_width = 1.5,
        section_line_color = :black,
        section_line_width = 2.0,
        show_north_arrow = true,
        show_scale_bar = true,
        annotation_color = :black,
        annotation_line_width = 2.0,
        survey_colormap = :viridis, survey_markersize = 5, survey_max_points = 60_000,
        data_marker_color = :black,
    ),
    isosurface = (
        enabled = false,
        alpha = 0.72,
        stride = 1,
        color_by_depth = false,
    ),
    coordinate = (
        target_crs = "EPSG:3067",
        selector_show_latlon_ticks = false,
    ),
    seismic = (
        show = true,
        trace_xy = :source,
        display_mode = :original,
        sample_spacing_m = 12.5,
        top_z_m = 0.0,
        max_traces = 1400,
        max_samples = 1200,
        clip_quantile = 0.995,
        curtain_alpha = 0.74,
        projected_resistivity_alpha = 0.88,
        colormap = :grays,
        envelope_colormap = [:white, :black],
        envelope_range = (0.0, 1.2),
        line_color = :orange,
        line_width = 3.0,
        show_model_section = true,
    ),
)

launch_config = @isdefined(TERRASCOPE_LAUNCH_CONFIG) ? _merge_launch_config(DEFAULT_TERRASCOPE_LAUNCH_CONFIG, TERRASCOPE_LAUNCH_CONFIG) : DEFAULT_TERRASCOPE_LAUNCH_CONFIG

_input_path(x) = x === nothing ? "" : String(strip(String(x)))

mt_model_file = _input_path(launch_config.inputs.MT_model)
mt_data_file = _input_path(launch_config.inputs.MT_data)
gravity_model_file = _input_path(launch_config.inputs.gravity_model)
gravity_data_file = _input_path(launch_config.inputs.gravity_data)
magnetic_model_file = _input_path(launch_config.inputs.magnetic_model)
magnetic_data_file = _input_path(launch_config.inputs.magnetic_data)
seismic_file = _input_path(launch_config.inputs.seismic_data)

# Every model input, in the order the property buttons appear. `kind` is the physical
# property the viewer colours and labels; the method name is what the user configures.
model_inputs = (
    (kind = :resistivity, method = "MT", model = mt_model_file, data = mt_data_file, units = "ohm m"),
    (kind = :density, method = "gravity", model = gravity_model_file, data = gravity_data_file, units = "kg/m^3"),
    (kind = :susceptibility, method = "magnetic", model = magnetic_model_file, data = magnetic_data_file, units = "SI"),
)

configured_inputs = [p for p in (mt_model_file, mt_data_file, gravity_model_file, gravity_data_file,
                                 magnetic_model_file, magnetic_data_file, seismic_file) if !isempty(p)]
data_root = isempty(configured_inputs) ? pwd() : dirname(first(configured_inputs))
model_name_for_export = isempty(configured_inputs) ? "TerraScope" : splitext(basename(first(configured_inputs)))[1]

# -------------------- Model Display --------------------
# Basic resistivity rendering options for the 3D view and section exports.
log10_scale = launch_config.model.log10_scale
colormap = launch_config.model.colormap
display_ranges = launch_config.model.display_ranges
resistivity_range = display_ranges.resistivity
max_depth = launch_config.model.max_depth_m
show_padding = launch_config.model.show_padding
pad_tolerance = launch_config.model.pad_tolerance
section_samples_along = launch_config.model.section_samples_along

# -------------------- View And Export --------------------
# Camera defaults, startup mode, and PNG export scaling.
default_view_direction = let d = launch_config.view.default_view_direction
    Vec3f(Float32(d[1]), Float32(d[2]), Float32(d[3]))
end
default_view_scale = Float32(launch_config.view.default_view_scale)
show_only_3d_scene = launch_config.view.show_only_3d_scene
open_fullscreen = launch_config.view.open_fullscreen
show_outer_ticks_axis = launch_config.view.show_outer_ticks_axis
export_png_scale = launch_config.view.export_png_scale

# -------------------- Map Overlay --------------------
# Shapefile and annotation styling drawn above the model. Each shapefile carries its
# own style; `overlay.line_*` below only fills in what an entry leaves out.
overlay_z_fixed = launch_config.overlay.z_fixed
overlay_auto_reproject_to_wgs84 = launch_config.overlay.auto_reproject_to_wgs84
overlay_line_color = launch_config.overlay.line_color
overlay_line_width = launch_config.overlay.line_width

shapefile_layers = [(
        path = _input_path(get(entry, :path, "")),
        color = get(entry, :color, overlay_line_color),
        width = get(entry, :width, overlay_line_width),
        alpha = Float64(get(entry, :alpha, 1.0)),
    ) for entry in launch_config.shapefiles]
filter!(entry -> !isempty(entry.path), shapefile_layers)
overlay_section_line_color = launch_config.overlay.section_line_color
overlay_section_line_width = launch_config.overlay.section_line_width
data_marker_color = launch_config.overlay.data_marker_color
survey_colormap = launch_config.overlay.survey_colormap
survey_markersize = launch_config.overlay.survey_markersize
survey_max_points = launch_config.overlay.survey_max_points
show_north_arrow = launch_config.overlay.show_north_arrow
show_scale_bar = launch_config.overlay.show_scale_bar
annotation_color = launch_config.overlay.annotation_color
annotation_line_width = launch_config.overlay.annotation_line_width

# -------------------- Isosurface Defaults --------------------
# Initial values for the interactive isosurface controls.
isosurface_defaults = launch_config.isosurface

# -------------------- Coordinate System --------------------
# Default target CRS is EPSG:3067. Use a projected CRS for plotting; the viewer
# assumes metric XY coordinates for sections, scale bars, and overlays. Set
# selector_show_latlon_ticks=true if you want geographic tick labels on the
# lower selector panel while keeping the scene itself projected.
target_crs = launch_config.coordinate.target_crs
selector_show_latlon_ticks = launch_config.coordinate.selector_show_latlon_ticks

# -------------------- Seismic Curtain --------------------
# SEG-Y line options for the seismic curtain and seismic-following model section.
show_seismic = launch_config.seismic.show
seismic_trace_xy = launch_config.seismic.trace_xy
seismic_display_mode = launch_config.seismic.display_mode
seismic_sample_spacing_m = launch_config.seismic.sample_spacing_m
seismic_top_z_m = launch_config.seismic.top_z_m
seismic_max_traces = launch_config.seismic.max_traces
seismic_max_samples = launch_config.seismic.max_samples
seismic_clip_quantile = launch_config.seismic.clip_quantile
seismic_curtain_alpha = launch_config.seismic.curtain_alpha
projected_resistivity_alpha = launch_config.seismic.projected_resistivity_alpha
seismic_colormap = launch_config.seismic.colormap
seismic_envelope_colormap = launch_config.seismic.envelope_colormap
seismic_envelope_range = launch_config.seismic.envelope_range
seismic_line_color = launch_config.seismic.line_color
seismic_line_width = launch_config.seismic.line_width
show_seismic_model_section = launch_config.seismic.show_model_section

function _compute_display_range(V::AbstractArray)
    vals = V[isfinite.(V)]
    isempty(vals) && return (0.0, 1.0)
    qlo, qhi = quantile(vec(vals), (0.02, 0.98))
    lo, hi = min(qlo, qhi), max(qlo, qhi)
    if lo == hi
        ϵ = max(1e-12, 1e-6 * abs(lo))
        lo -= ϵ
        hi += ϵ
    end
    return lo, hi
end

function _resolve_display_range(V::AbstractArray, range_override)
    if isnothing(range_override)
        return _compute_display_range(V)
    end
    lo, hi = Float64(range_override[1]), Float64(range_override[2])
    if lo > hi
        lo, hi = hi, lo
    end
    if lo == hi
        ϵ = max(1e-12, 1e-6 * abs(lo))
        lo -= ϵ
        hi += ϵ
    end
    return lo, hi
end

_volume_colormap(kind::Symbol, resistivity_cmap) = resistivity_cmap
_volume_colorbar_label(kind::Symbol, logscale::Bool) = kind == :density ? "Density (g/cc)" : (kind == :susceptibility ? "Susceptibility (SI)" : (logscale ? "log₁₀ ρ (Ω·m)" : "ρ (Ω·m)"))
_volume_units_label(kind::Symbol) = kind == :density ? "g/cc" : (kind == :susceptibility ? "SI" : "Ω·m")
_isosurface_depth_colormap(kind::Symbol) = kind == :density ? [:mintcream, :mediumseagreen, :darkslategray4] :
                                           (kind == :susceptibility ? [:cornsilk, :orange, :orangered4] :
                                            [:aliceblue, :royalblue1, :navy])

function _physical_to_internal(kind::Symbol, value::Real; logscale::Bool)
    kind == :density && return Float64(value)
    kind == :susceptibility && return Float64(value)
    return logscale ? log10(max(Float64(value), 1e-12)) : Float64(value)
end

function _internal_to_physical(kind::Symbol, value::Real; logscale::Bool)
    kind == :density && return Float64(value)
    kind == :susceptibility && return Float64(value)
    return logscale ? 10.0^Float64(value) : Float64(value)
end

function _local_tm_to_wgs84_transform(lat0::Real, lon0::Real)
    src = "+proj=tmerc +lat_0=$(float(lat0)) +lon_0=$(float(lon0)) +k=0.9996 +x_0=500000 +y_0=0 +datum=WGS84 +units=m +no_defs"
    return Proj.Transformation(src, "EPSG:4326"; always_xy = true)
end

function _convert_station_xy_to_latlon(d, trans)
    ns = size(d.loc, 1)
    lon_pred = zeros(ns)
    lat_pred = zeros(ns)

    for i in 1:ns
        ll = trans((Float64(d.y[i]) + 500000.0, Float64(d.x[i])))
        lon_pred[i] = Float64(ll[1])
        lat_pred[i] = Float64(ll[2])
    end

    return lat_pred, lon_pred
end

function model_xy_to_latlon_centers(M, d)
    lat_vals = d.loc[:, 1]
    lon_vals = d.loc[:, 2]

    lat0 = (length(d.origin) >= 1 && isfinite(d.origin[1])) ? Float64(d.origin[1]) : mean(lat_vals)
    lon0 = (length(d.origin) >= 2 && isfinite(d.origin[2])) ? Float64(d.origin[2]) : mean(lon_vals)

    trans = _local_tm_to_wgs84_transform(lat0, lon0)

    lon_centers = Float64[]
    for y in M.cy
        ll = trans((Float64(y) + 500000.0, 0.0))
        push!(lon_centers, Float64(ll[1]))
    end

    lat_centers = Float64[]
    for x in M.cx
        ll = trans((500000.0, Float64(x)))
        push!(lat_centers, Float64(ll[2]))
    end

    lat_pred, lon_pred = _convert_station_xy_to_latlon(d, trans)
    shiftlat = mean(lat_pred .- lat_vals)
    shiftlon = mean(lon_pred .- lon_vals)

    lat_centers .-= shiftlat
    lon_centers .-= shiftlon

    return lat_centers, lon_centers, lat0, lon0, shiftlat, shiftlon
end

function _resolve_wgs84_to_target_xy_transform(target_crs::AbstractString)
    crs = uppercase(strip(target_crs))
    if crs == "EPSG:4326"
        return (lon, lat) -> (Float64(lon), Float64(lat))
    end

    trans = Proj.Transformation("EPSG:4326", strip(target_crs); always_xy = true)
    return (lon, lat) -> begin
        p = trans((Float64(lon), Float64(lat)))
        return Float64(p[1]), Float64(p[2])
    end
end

function _resolve_target_xy_to_wgs84_transform(target_crs::AbstractString)
    crs = uppercase(strip(target_crs))
    if crs == "EPSG:4326"
        return (x, y) -> (Float64(x), Float64(y))
    end

    trans = Proj.Transformation(strip(target_crs), "EPSG:4326"; always_xy = true)
    return (x, y) -> begin
        p = trans((Float64(x), Float64(y)))
        return Float64(p[1]), Float64(p[2])
    end
end

function _validate_target_crs(target_crs::AbstractString)
    crs = uppercase(strip(target_crs))
    if crs == "EPSG:4326"
        error("target_crs=EPSG:4326 is not supported for plotting. TerraScope assumes projected metric XY coordinates for scale bars, section distances, and sampling. Keep target_crs projected, such as EPSG:3067, and use selector_show_latlon_ticks=true if you want WGS84 labels.")
    end
    return target_crs
end

function model_xy_to_target_crs_centers(M, d, target_crs::AbstractString)
    _validate_target_crs(target_crs)
    lat_centers, lon_centers, lat0, lon0, shiftlat, shiftlon = model_xy_to_latlon_centers(M, d)
    lat_ref = mean(lat_centers)
    lon_ref = mean(lon_centers)

    src_local_tm = "+proj=tmerc +lat_0=$(float(lat0)) +lon_0=$(float(lon0)) +k=0.9996 +x_0=500000 +y_0=0 +datum=WGS84 +units=m +no_defs"
    local_tm_to_target = Proj.Transformation(src_local_tm, strip(target_crs); always_xy = true)

    x_target = Float64[]
    for y_local in M.cy
        p = local_tm_to_target((Float64(y_local) + 500000.0, 0.0))
        push!(x_target, Float64(p[1]))
    end

    y_target = Float64[]
    for x_local in M.cx
        p = local_tm_to_target((500000.0, Float64(x_local)))
        push!(y_target, Float64(p[2]))
    end

    station_tx = Float64[]
    station_ty = Float64[]
    for i in eachindex(d.x)
        p = local_tm_to_target((Float64(d.y[i]) + 500000.0, Float64(d.x[i])))
        push!(station_tx, Float64(p[1]))
        push!(station_ty, Float64(p[2]))
    end

    epsv = eps(Float64)
    span_x_model = max(maximum(x_target) - minimum(x_target), epsv)
    span_y_model = max(maximum(y_target) - minimum(y_target), epsv)
    span_e_sta = max(maximum(station_tx) - minimum(station_tx), epsv)
    span_n_sta = max(maximum(station_ty) - minimum(station_ty), epsv)

    mismatch_dim_consistent = abs(log(span_x_model / span_e_sta)) + abs(log(span_y_model / span_n_sta))

    return x_target, y_target, lat0, lon0, shiftlat, shiftlon, lat_ref, lon_ref, mismatch_dim_consistent, station_tx, station_ty
end

function _nice_scale_length(target::Float64)
    target <= 0 && return 1.0
    expo = floor(log10(target))
    base = 10.0^expo
    frac = target / base
    nice_frac = if frac < 1.5
        1.0
    elseif frac < 3.5
        2.0
    elseif frac < 7.5
        5.0
    else
        10.0
    end
    return nice_frac * base
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
        δ = max(1e-8, 1e-4 * max(abs(lo), abs(Float64(cmax - cmin)), 1.0))
        lo -= δ
        hi += δ
    end
    return lo, hi
end

function _lerp_iso_levels(vmin::Real, vmax::Real, nlevels::Int)
    n = max(1, nlevels)
    lo = Float64(vmin)
    hi = Float64(vmax)
    if n == 1
        return [0.5 * (lo + hi)]
    end
    return collect(range(lo, hi; length = n))
end

const _CUBE_TETRA = (
    (1, 2, 4, 8),
    (1, 4, 3, 8),
    (1, 3, 7, 8),
    (1, 7, 5, 8),
    (1, 5, 6, 8),
    (1, 6, 2, 8),
)

const _TETRA_EDGES = (
    (1, 2), (1, 3), (1, 4),
    (2, 3), (2, 4), (3, 4),
)

function _interp_iso_point(p1::NTuple{3, Float64}, p2::NTuple{3, Float64}, v1::Float64, v2::Float64, iso::Float64)
    if abs(v2 - v1) < eps(Float64)
        t = 0.5
    else
        t = clamp((iso - v1) / (v2 - v1), 0.0, 1.0)
    end
    return (
        p1[1] + t * (p2[1] - p1[1]),
        p1[2] + t * (p2[2] - p1[2]),
        p1[3] + t * (p2[3] - p1[3]),
    )
end

function _tetra_isotriangles(points::NTuple{4, NTuple{3, Float64}}, vals::NTuple{4, Float64}, iso::Float64)
    intersections = NTuple{3, Float64}[]
    for (a, b) in _TETRA_EDGES
        v1 = vals[a]
        v2 = vals[b]
        crosses = (v1 < iso && v2 > iso) || (v1 > iso && v2 < iso)
        on_vertex = (v1 == iso) ⊻ (v2 == iso)
        if crosses || on_vertex
            push!(intersections, _interp_iso_point(points[a], points[b], v1, v2, iso))
        end
    end

    n = length(intersections)
    if n < 3
        return NTuple{3, NTuple{3, Float64}}[]
    elseif n == 3
        return [(intersections[1], intersections[2], intersections[3])]
    elseif n == 4
        return [
            (intersections[1], intersections[2], intersections[3]),
            (intersections[1], intersections[3], intersections[4]),
        ]
    else
        return NTuple{3, NTuple{3, Float64}}[]
    end
end

function extract_isosurface_triangles(xv::AbstractVector{<:Real}, yv::AbstractVector{<:Real}, zv::AbstractVector{<:Real},
    V::Array{<:Real, 3}, iso::Real; stride::Int = 1, depth_start_m::Real = 0.0, depth_end_m::Real = Inf)
    nx, ny, nz = size(V)
    if nx < 2 || ny < 2 || nz < 2
        return NTuple{3, NTuple{3, Float64}}[]
    end

    step = max(1, stride)
    d0 = max(0.0, min(Float64(depth_start_m), Float64(depth_end_m)))
    d1 = max(0.0, max(Float64(depth_start_m), Float64(depth_end_m)))
    tris = NTuple{3, NTuple{3, Float64}}[]

    for i in 1:step:(nx - 1), j in 1:step:(ny - 1), k in 1:step:(nz - 1)
        depth_mid = -0.5 * (Float64(zv[k]) + Float64(zv[k + 1]))
        if depth_mid < d0 || depth_mid > d1
            continue
        end

        p = (
            (Float64(xv[i]),     Float64(yv[j]),     Float64(zv[k])),
            (Float64(xv[i + 1]), Float64(yv[j]),     Float64(zv[k])),
            (Float64(xv[i]),     Float64(yv[j + 1]), Float64(zv[k])),
            (Float64(xv[i + 1]), Float64(yv[j + 1]), Float64(zv[k])),
            (Float64(xv[i]),     Float64(yv[j]),     Float64(zv[k + 1])),
            (Float64(xv[i + 1]), Float64(yv[j]),     Float64(zv[k + 1])),
            (Float64(xv[i]),     Float64(yv[j + 1]), Float64(zv[k + 1])),
            (Float64(xv[i + 1]), Float64(yv[j + 1]), Float64(zv[k + 1])),
        )

        s = (
            Float64(V[i, j, k]),
            Float64(V[i + 1, j, k]),
            Float64(V[i, j + 1, k]),
            Float64(V[i + 1, j + 1, k]),
            Float64(V[i, j, k + 1]),
            Float64(V[i + 1, j, k + 1]),
            Float64(V[i, j + 1, k + 1]),
            Float64(V[i + 1, j + 1, k + 1]),
        )

        all(isfinite, s) || continue

        smin = minimum(s)
        smax = maximum(s)
        if Float64(iso) < smin || Float64(iso) > smax
            continue
        end

        for tet in _CUBE_TETRA
            ptet = (p[tet[1]], p[tet[2]], p[tet[3]], p[tet[4]])
            stet = (s[tet[1]], s[tet[2]], s[tet[3]], s[tet[4]])
            append!(tris, _tetra_isotriangles(ptet, stet, Float64(iso)))
        end
    end

    return tris
end

function _padded_axis(vals::AbstractVector{<:Real})
    n = length(vals)
    n == 0 && return Float64[]
    n == 1 && return [Float64(vals[1]) - 1.0, Float64(vals[1]), Float64(vals[1]) + 1.0]
    first_step = Float64(vals[2]) - Float64(vals[1])
    last_step = Float64(vals[end]) - Float64(vals[end - 1])
    return vcat(Float64(vals[1]) - first_step, Float64.(vals), Float64(vals[end]) + last_step)
end

function build_range_isosurface_triangles(xv::AbstractVector{<:Real}, yv::AbstractVector{<:Real}, zv::AbstractVector{<:Real},
    V::Array{<:Real, 3}, vmin::Real, vmax::Real, dstart_m::Real, dend_m::Real; stride::Int = 1)
    finite_values = V[isfinite.(V)]
    isempty(finite_values) && return NTuple{3, NTuple{3, Float64}}[], 0, Float64[]

    lo, hi = _sanitize_iso_range(vmin, vmax, minimum(finite_values), maximum(finite_values))
    d0 = max(0.0, min(Float64(dstart_m), Float64(dend_m)))
    d1 = max(0.0, max(Float64(dstart_m), Float64(dend_m)))
    value_scale = max(0.5 * abs(hi - lo), 1e-9 * max(abs(lo), abs(hi), 1.0))
    depth_scale = max(0.5 * abs(d1 - d0), 1.0)

    nx, ny, nz = size(V)
    score = fill(-1.0, nx, ny, nz)
    selected_samples = 0
    for i in 1:nx, j in 1:ny, k in 1:nz
        value = Float64(V[i, j, k])
        isfinite(value) || continue
        depth = -Float64(zv[k])
        value_score = min((value - lo) / value_scale, (hi - value) / value_scale)
        depth_score = min((depth - d0) / depth_scale, (d1 - depth) / depth_scale)
        score[i, j, k] = min(value_score, depth_score)
        score[i, j, k] >= 0.0 && (selected_samples += 1)
    end

    selected_samples == 0 && return NTuple{3, NTuple{3, Float64}}[], 0, Float64[lo, hi]

    padded_score = fill(-1.0, nx + 2, ny + 2, nz + 2)
    padded_score[2:(nx + 1), 2:(ny + 1), 2:(nz + 1)] .= score
    tris = extract_isosurface_triangles(_padded_axis(xv), _padded_axis(yv), _padded_axis(zv), padded_score, 0.0;
        stride = max(1, stride),
        depth_start_m = 0.0,
        depth_end_m = Inf)

    return tris, selected_samples, Float64[lo, hi]
end

function _triangles_to_vertices_faces(tris::Vector{NTuple{3, NTuple{3, Float64}}})
    vertices = GLMakie.Point3f[]
    faces = GLMakie.TriangleFace{Int32}[]
    for tri in tris
        base = length(vertices) + 1
        push!(vertices, GLMakie.Point3f(tri[1][1], tri[1][2], tri[1][3]))
        push!(vertices, GLMakie.Point3f(tri[2][1], tri[2][2], tri[2][3]))
        push!(vertices, GLMakie.Point3f(tri[3][1], tri[3][2], tri[3][3]))
        push!(faces, GLMakie.TriangleFace(Int32(base), Int32(base + 1), Int32(base + 2)))
    end
    return vertices, faces
end

function _bracket_index_and_weight_monotonic(vals::AbstractVector{<:Real}, query::Real)
    n = length(vals)
    n <= 1 && return 1, 1, 0.0
    ascending = vals[1] <= vals[end]

    if ascending
        query <= vals[1] && return 1, 2, 0.0
        query >= vals[end] && return n - 1, n, 1.0
    else
        query >= vals[1] && return 1, 2, 0.0
        query <= vals[end] && return n - 1, n, 1.0
    end

    lo = 1
    hi = n
    while lo < hi
        mid = (lo + hi) >>> 1
        if ascending ? vals[mid] < query : vals[mid] > query
            lo = mid + 1
        else
            hi = mid
        end
    end

    i1 = clamp(lo, 2, n)
    i0 = i1 - 1
    v0 = Float64(vals[i0])
    v1 = Float64(vals[i1])
    w = v0 == v1 ? 0.0 : (Float64(query) - v0) / (v1 - v0)
    return i0, i1, clamp(w, 0.0, 1.0)
end

function _sample_volume_at_point(vol, point, fallback::Real)
    ix0, ix1, wx = _bracket_index_and_weight_monotonic(vol.x, Float64(point[1]))
    iy0, iy1, wy = _bracket_index_and_weight_monotonic(vol.y, Float64(point[2]))
    iz0, iz1, wz = _bracket_index_and_weight_monotonic(vol.z, Float64(point[3]))

    v000 = Float64(vol.values[ix0, iy0, iz0])
    v100 = Float64(vol.values[ix1, iy0, iz0])
    v010 = Float64(vol.values[ix0, iy1, iz0])
    v110 = Float64(vol.values[ix1, iy1, iz0])
    v001 = Float64(vol.values[ix0, iy0, iz1])
    v101 = Float64(vol.values[ix1, iy0, iz1])
    v011 = Float64(vol.values[ix0, iy1, iz1])
    v111 = Float64(vol.values[ix1, iy1, iz1])

    if !all(isfinite, (v000, v100, v010, v110, v001, v101, v011, v111))
        return Float64(fallback)
    end

    v00 = (1.0 - wx) * v000 + wx * v100
    v10 = (1.0 - wx) * v010 + wx * v110
    v01 = (1.0 - wx) * v001 + wx * v101
    v11 = (1.0 - wx) * v011 + wx * v111
    v0 = (1.0 - wy) * v00 + wy * v10
    v1 = (1.0 - wy) * v01 + wy * v11
    return (1.0 - wz) * v0 + wz * v1
end

function _draw_isosurface_mesh!(target_ax, verts, faces, vol; color_by_depth::Bool, depth_start_m::Real, depth_end_m::Real, alpha_val::Real, vmin_internal::Real, vmax_internal::Real)
    alpha_clamped = clamp(Float64(alpha_val), 0.05, 0.95)
    return if color_by_depth
        color_data = Float32[-Float64(v[3]) for v in verts]
        mesh!(target_ax, verts, faces;
            color = color_data,
            colormap = _isosurface_depth_colormap(vol.kind),
            colorrange = (Float64(depth_start_m), Float64(depth_end_m)),
            transparency = true,
            alpha = alpha_clamped,
            shading = FastShading)
    else
        property_mid = 0.5 * (Float64(vmin_internal) + Float64(vmax_internal))
        color_data = Float32[_sample_volume_at_point(vol, v, property_mid) for v in verts]
        mesh!(target_ax, verts, faces;
            color = color_data,
            colormap = vol.cmap,
            colorrange = (vol.cmin, vol.cmax),
            transparency = true,
            alpha = alpha_clamped,
            shading = FastShading)
    end
end

function _write_dxf_3dface!(io, p1::NTuple{3, Float64}, p2::NTuple{3, Float64}, p3::NTuple{3, Float64}; layer::AbstractString = "0")
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

function draw_north_and_scale!(ax;
    xv,
    yv,
    z_fixed::Real,
    target_crs::AbstractString,
    north_axis::Symbol = :y,
    show_north::Bool = true,
    show_scale::Bool = true,
    color = :black,
    line_width::Real = 2.0)

    isempty(xv) && return
    isempty(yv) && return

    xmin, xmax = extrema(xv)
    ymin, ymax = extrema(yv)
    dx = xmax - xmin
    dy = ymax - ymin
    (dx <= 0 || dy <= 0) && return

    z = Float64(z_fixed)
    x_north = xmin + 0.86 * dx
    y_north = ymin + 0.10 * dy
    x_scale = xmin + 0.68 * dx
    y_scale = ymin + 0.10 * dy

    if show_north
        arrow_len = 0.06 * min(dx, dy)
        if north_axis == :x
            x1 = x_north + arrow_len
            y1 = y_north
            ah = 0.025 * min(dx, dy)
            lines!(ax, [x_north, x1], [y_north, y1], [z, z], color = color, linewidth = line_width)
            lines!(ax, [x1 - ah, x1], [y1 - ah, y1], [z, z], color = color, linewidth = line_width)
            lines!(ax, [x1 - ah, x1], [y1 + ah, y1], [z, z], color = color, linewidth = line_width)
            text!(ax, [x1 + 0.02 * dx], [y1], [z], text = ["N"], color = color, fontsize = 16)
        else
            x1 = x_north
            y1 = y_north + arrow_len
            ah = 0.025 * min(dx, dy)
            lines!(ax, [x_north, x1], [y_north, y1], [z, z], color = color, linewidth = line_width)
            lines!(ax, [x1 - ah, x1], [y1 - ah, y1], [z, z], color = color, linewidth = line_width)
            lines!(ax, [x1 + ah, x1], [y1 - ah, y1], [z, z], color = color, linewidth = line_width)
            text!(ax, [x1], [y1 + 0.02 * dy], [z], text = ["N"], color = color, fontsize = 16)
        end
    end

    if show_scale
        target_len = 0.10 * dx
        scale_len = _nice_scale_length(target_len)
        xb0 = x_scale
        xb1 = xb0 + scale_len
        yb = y_scale

        lines!(ax, [xb0, xb1], [yb, yb], [z, z], color = color, linewidth = line_width)

        tick = 0.008 * dy
        lines!(ax, [xb0, xb0], [yb - tick, yb + tick], [z, z], color = color, linewidth = line_width)
        lines!(ax, [xb1, xb1], [yb - tick, yb + tick], [z, z], color = color, linewidth = line_width)

        unit_label = uppercase(strip(target_crs)) == "EPSG:4326" ? "deg" : "m"
        label_val = unit_label == "m" && scale_len >= 1000 ? "$(round(scale_len / 1000; digits = 2)) km" : "$(round(scale_len; sigdigits = 3)) $unit_label"
        text!(ax, [0.5 * (xb0 + xb1)], [yb + 0.02 * dy], [z], text = [label_val], color = color, fontsize = 12)
    end
end

function _prj_path_from_shp(shp::AbstractString)
    root, _ = splitext(shp)
    return root * ".prj"
end

function _detect_crs_type(shp::AbstractString)
    prj_path = _prj_path_from_shp(shp)
    if !isfile(prj_path)
        return :unknown, ""
    end
    wkt = read(prj_path, String)
    wktu = uppercase(wkt)
    if occursin("PROJCS", wktu) || occursin("PROJCRS", wktu)
        return :projected, wkt
    elseif occursin("GEOGCS", wktu) || occursin("GEOGRAPHICCRS", wktu)
        return :geographic, wkt
    else
        return :unknown, wkt
    end
end

function _make_coord_transform(shp_path::AbstractString, crs_type::Symbol; auto_reproject_to_wgs84::Bool = true)
    if !(auto_reproject_to_wgs84 && crs_type == :projected)
        return (x, y) -> (x, y), false, "none"
    end
    prj_path = _prj_path_from_shp(shp_path)
    if !isfile(prj_path)
        return (x, y) -> (x, y), false, "missing .prj"
    end
    wkt = read(prj_path, String)
    try
        trans = Proj.Transformation(wkt, "EPSG:4326"; always_xy = true)
        f = (x, y) -> begin
            ll = trans((x, y))
            return Float64(ll[1]), Float64(ll[2])
        end
        return f, true, "WKT -> EPSG:4326"
    catch
        return (x, y) -> (x, y), false, "transformation failed"
    end
end

function plot_shapefile_on_3d!(ax, shapefile_path;
    z_fixed::Real = 0.0,
    line_color = :black,
    line_width = 1.5,
    alpha::Real = 1.0,
    auto_reproject_to_wgs84 = true,
    post_transform = (x, y) -> (x, y),
    xlim::Union{Nothing, Tuple{<:Real, <:Real}} = nothing,
    ylim::Union{Nothing, Tuple{<:Real, <:Real}} = nothing)
    if !isfile(shapefile_path)
        @warn "Shapefile not found: $shapefile_path"
        return 0
    end
    table = Shapefile.Table(shapefile_path)
    rows = collect(table)
    crs_type, _ = _detect_crs_type(shapefile_path)
    coord_transform, _, _ = _make_coord_transform(shapefile_path, crs_type; auto_reproject_to_wgs84 = auto_reproject_to_wgs84)

    function _is_xy(c)
        return (c isa Tuple || c isa AbstractVector) && length(c) >= 2 && c[1] isa Real && c[2] isa Real
    end

    xlo, xhi = isnothing(xlim) ? (-Inf, Inf) : (min(Float64(xlim[1]), Float64(xlim[2])), max(Float64(xlim[1]), Float64(xlim[2])))
    ylo, yhi = isnothing(ylim) ? (-Inf, Inf) : (min(Float64(ylim[1]), Float64(ylim[2])), max(Float64(ylim[1]), Float64(ylim[2])))
    inside = (x, y) -> (x >= xlo && x <= xhi && y >= ylo && y <= yhi)

    # Collect all segments into batched arrays with NaN separators
    all_x = Float64[]
    all_y = Float64[]
    segments_count = 0

    function collect_coords_recursive!(coords)
        if _is_xy(coords)
            return
        elseif coords isa AbstractVector
            isempty(coords) && return
            first_item = first(coords)
            if _is_xy(first_item)
                xy = Tuple{Float64, Float64}[]
                for p in coords
                    if _is_xy(p)
                        x0, y0 = coord_transform(Float64(p[1]), Float64(p[2]))
                        x, y = post_transform(x0, y0)
                        push!(xy, (x, y))
                    end
                end

                run_x = Float64[]
                run_y = Float64[]
                for (x, y) in xy
                    if inside(x, y)
                        push!(run_x, x)
                        push!(run_y, y)
                    else
                        if length(run_x) >= 2
                            if !isempty(all_x)
                                push!(all_x, NaN)
                                push!(all_y, NaN)
                            end
                            append!(all_x, run_x)
                            append!(all_y, run_y)
                            segments_count += 1
                        end
                        empty!(run_x)
                        empty!(run_y)
                    end
                end

                if length(run_x) >= 2
                    if !isempty(all_x)
                        push!(all_x, NaN)
                        push!(all_y, NaN)
                    end
                    append!(all_x, run_x)
                    append!(all_y, run_y)
                    segments_count += 1
                end
            else
                for part in coords
                    collect_coords_recursive!(part)
                end
            end
        end
    end

    for row in rows
        geom = GeoInterface.geometry(row)
        coords = try
            GeoInterface.coordinates(geom)
        catch
            nothing
        end
        if !isnothing(coords)
            collect_coords_recursive!(coords)
        end
    end

    if !isempty(all_x)
        all_z = [isnan(x) ? NaN : Float64(z_fixed) for x in all_x]
        lines!(ax, all_x, all_y, all_z; color = line_color, linewidth = line_width,
            alpha = Float64(alpha), transparency = alpha < 1)
    end
    return segments_count
end

function nearest_index(vals::AbstractVector{<:Real}, x::Real)
    i = searchsortedfirst(vals, x)
    if i <= 1
        return 1
    elseif i > length(vals)
        return length(vals)
    else
        return abs(vals[i] - x) < abs(vals[i - 1] - x) ? i : i - 1
    end
end

function bracket_index_and_weight(vals::AbstractVector{<:Real}, q::Real)
    n = length(vals)
    if n <= 1
        return 1, 1, 0.0
    end

    if q <= vals[1]
        return 1, 2, 0.0
    elseif q >= vals[end]
        return n - 1, n, 1.0
    end

    i1 = searchsortedfirst(vals, q)
    i0 = i1 - 1
    v0 = Float64(vals[i0])
    v1 = Float64(vals[i1])
    if v1 == v0
        return i0, i1, 0.0
    end
    w = (Float64(q) - v0) / (v1 - v0)
    return i0, i1, clamp(w, 0.0, 1.0)
end

function compute_offset_limits_for_segment(p1::Tuple{Float64, Float64}, p2::Tuple{Float64, Float64},
    n̂::Tuple{Float64, Float64}, xlim::Tuple{Float64, Float64}, ylim::Tuple{Float64, Float64})

    xmin, xmax = min(xlim[1], xlim[2]), max(xlim[1], xlim[2])
    ymin, ymax = min(ylim[1], ylim[2]), max(ylim[1], ylim[2])

    function point_limits(px, py)
        nx, ny = n̂

        lx, hx = if abs(nx) < 1e-12
            if px < xmin || px > xmax
                (Inf, -Inf)
            else
                (-Inf, Inf)
            end
        else
            t1 = (xmin - px) / nx
            t2 = (xmax - px) / nx
            (min(t1, t2), max(t1, t2))
        end

        ly, hy = if abs(ny) < 1e-12
            if py < ymin || py > ymax
                (Inf, -Inf)
            else
                (-Inf, Inf)
            end
        else
            t1 = (ymin - py) / ny
            t2 = (ymax - py) / ny
            (min(t1, t2), max(t1, t2))
        end

        return max(lx, ly), min(hx, hy)
    end

    l1, h1 = point_limits(p1[1], p1[2])
    l2, h2 = point_limits(p2[1], p2[2])
    lo = max(l1, l2)
    hi = min(h1, h2)

    if !isfinite(lo) || !isfinite(hi) || lo >= hi
        diag_len = hypot(xmax - xmin, ymax - ymin)
        return -0.25 * diag_len, 0.25 * diag_len
    end

    return lo, hi
end

function build_section_surface(xv, yv, zv, R, p1::Tuple{Float64, Float64}, p2::Tuple{Float64, Float64}; nsamp::Int = 360)
    ns = max(8, nsamp)
    t = range(0.0, 1.0; length = ns)

    xs = [p1[1] + τ * (p2[1] - p1[1]) for τ in t]
    ys = [p1[2] + τ * (p2[2] - p1[2]) for τ in t]

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

            v00 = R[ix0, iy0, k]
            v10 = R[ix1, iy0, k]
            v01 = R[ix0, iy1, k]
            v11 = R[ix1, iy1, k]

            v0 = (1.0 - wx) * v00 + wx * v10
            v1 = (1.0 - wx) * v01 + wx * v11
            C[i, k] = (1.0 - wy) * v0 + wy * v1
        end
    end

    return X, Y, Z, C
end

function sample_polyline(points::Vector{Tuple{Float64, Float64}}, nsamp::Int)
    n = length(points)
    if n < 2
        return Float64[], Float64[], Float64[]
    end

    seglen = Float64[]
    push!(seglen, 0.0)
    for i in 2:n
        dx = points[i][1] - points[i - 1][1]
        dy = points[i][2] - points[i - 1][2]
        push!(seglen, seglen[end] + hypot(dx, dy))
    end

    total = seglen[end]
    if total <= 0
        xs = fill(points[1][1], nsamp)
        ys = fill(points[1][2], nsamp)
        ss = zeros(nsamp)
        return xs, ys, ss
    end

    s_query = collect(range(0.0, total; length = max(8, nsamp)))
    xs = Vector{Float64}(undef, length(s_query))
    ys = Vector{Float64}(undef, length(s_query))

    j = 2
    for (k, s) in enumerate(s_query)
        while j < n && seglen[j] < s
            j += 1
        end
        j0 = max(1, j - 1)
        j1 = min(n, j)
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

function build_section_surface_polyline(xv, yv, zv, R, path::Vector{Tuple{Float64, Float64}}; nsamp::Int = 360)
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

            v00 = R[ix0, iy0, k]
            v10 = R[ix1, iy0, k]
            v01 = R[ix0, iy1, k]
            v11 = R[ix1, iy1, k]

            v0 = (1.0 - wx) * v00 + wx * v10
            v1 = (1.0 - wx) * v01 + wx * v11
            C[i, k] = (1.0 - wy) * v0 + wy * v1
        end
    end

    return X, Y, Z, C, sdist
end

function sample_model_section_to_depth_grid(xv, yv, zv, R,
    xq::AbstractVector{<:Real}, yq::AbstractVector{<:Real}, zq::AbstractVector{<:Real})

    xvals = collect(Float64.(xv))
    yvals = collect(Float64.(yv))
    zvals = collect(Float64.(zv))
    rvals = Float64.(R)

    if !issorted(xvals)
        if issorted(xvals; rev = true)
            xvals = reverse(xvals)
            rvals = reverse(rvals; dims = 1)
        else
            perm = sortperm(xvals)
            xvals = xvals[perm]
            rvals = rvals[perm, :, :]
        end
    end

    if !issorted(yvals)
        if issorted(yvals; rev = true)
            yvals = reverse(yvals)
            rvals = reverse(rvals; dims = 2)
        else
            perm = sortperm(yvals)
            yvals = yvals[perm]
            rvals = rvals[:, perm, :]
        end
    end

    if !issorted(zvals)
        if issorted(zvals; rev = true)
            zvals = reverse(zvals)
            rvals = reverse(rvals; dims = 3)
        else
            perm = sortperm(zvals)
            zvals = zvals[perm]
            rvals = rvals[:, :, perm]
        end
    end

    nt = min(length(xq), length(yq))
    nzq = length(zq)
    section = fill(NaN, nt, nzq)

    xmin, xmax = extrema(xvals)
    ymin, ymax = extrema(yvals)
    zmin, zmax = extrema(zvals)

    for i in 1:nt
        xi = Float64(xq[i])
        yi = Float64(yq[i])
        if xi < xmin || xi > xmax || yi < ymin || yi > ymax
            continue
        end

        ix0, ix1, wx = bracket_index_and_weight(xvals, xi)
        iy0, iy1, wy = bracket_index_and_weight(yvals, yi)

        for k in 1:nzq
            zk = Float64(zq[k])
            if zk < zmin || zk > zmax
                continue
            end

            iz0, iz1, wz = bracket_index_and_weight(zvals, zk)

            v00a = rvals[ix0, iy0, iz0]
            v10a = rvals[ix1, iy0, iz0]
            v01a = rvals[ix0, iy1, iz0]
            v11a = rvals[ix1, iy1, iz0]

            v00b = rvals[ix0, iy0, iz1]
            v10b = rvals[ix1, iy0, iz1]
            v01b = rvals[ix0, iy1, iz1]
            v11b = rvals[ix1, iy1, iz1]

            v0a = (1.0 - wx) * v00a + wx * v10a
            v1a = (1.0 - wx) * v01a + wx * v11a
            va = (1.0 - wy) * v0a + wy * v1a

            v0b = (1.0 - wx) * v00b + wx * v10b
            v1b = (1.0 - wx) * v01b + wx * v11b
            vb = (1.0 - wy) * v0b + wy * v1b

            section[i, k] = (1.0 - wz) * va + wz * vb
        end
    end

    return section
end

function _segy_scalar_factor(s::Integer)
    s == 0 && return 1.0
    s > 0 && return Float64(s)
    return 1.0 / Float64(abs(s))
end

function _extract_trace_xy(h; pref::Symbol = :source)
    scale = _segy_scalar_factor(getproperty(h, :RecSourceScalar))

    sx = Float64(getproperty(h, :SourceX)) * scale
    sy = Float64(getproperty(h, :SourceY)) * scale
    gx = Float64(getproperty(h, :GroupX)) * scale
    gy = Float64(getproperty(h, :GroupY)) * scale

    source_ok = isfinite(sx) && isfinite(sy) && !(sx == 0.0 && sy == 0.0)
    group_ok = isfinite(gx) && isfinite(gy) && !(gx == 0.0 && gy == 0.0)

    if pref == :group
        return group_ok ? (gx, gy) : (sx, sy)
    else
        return source_ok ? (sx, sy) : (gx, gy)
    end
end

function _normalize_amplitude(A::AbstractMatrix{<:Real}; clip_quantile::Real = 0.995)
    vals = abs.(vec(Float64.(A)))
    isempty(vals) && return zeros(Float64, size(A))
    q = quantile(vals, clamp(Float64(clip_quantile), 0.5, 0.9999))
    q = isfinite(q) && q > 0 ? q : maximum(vals)
    q = (isfinite(q) && q > 0) ? q : 1.0
    return clamp.(Float64.(A) ./ q, -1.0, 1.0)
end

function compute_seismic_envelope(seis::AbstractMatrix{<:Real})
    nsamples = size(seis, 2)
    nsamples == 0 && return zeros(Float64, size(seis))

    hilbert_filter = zeros(Float64, nsamples)
    hilbert_filter[1] = 1.0
    if iseven(nsamples)
        hilbert_filter[nsamples ÷ 2 + 1] = 1.0
        hilbert_filter[2:(nsamples ÷ 2)] .= 2.0
    else
        hilbert_filter[2:((nsamples + 1) ÷ 2)] .= 2.0
    end

    analytic_signal = ifft(fft(Float64.(seis), 2) .* reshape(hilbert_filter, 1, :), 2)
    return abs.(analytic_signal)
end

function _resolve_seismic_display_mode(mode)
    mode_sym = Symbol(lowercase(strip(string(mode))))
    if mode_sym in (:original, :envelope)
        return mode_sym
    end
    @warn "Invalid seismic_display_mode; using :original." seismic_display_mode = mode
    return :original
end

function load_seismic_curtain_from_segy(path::AbstractString;
    trace_xy::Symbol = :source,
    display_mode::Symbol = :original,
    sample_spacing_m::Real = 12.5,
    top_z_m::Real = 0.0,
    max_traces::Int = 1400,
    max_samples::Int = 1200,
    clip_quantile::Real = 0.995)

    isfile(path) || error("SEG-Y file not found: $path")

    segy = segy_read(path)
    data = Float32.(segy.data)
    headers = segy.traceheaders
    n_samples, n_traces = size(data)
    length(headers) == n_traces || error("SEG-Y trace header count ($(length(headers))) != trace count ($(n_traces))")

    it = unique(round.(Int, range(1, n_traces; length = min(max_traces, n_traces))))
    is = unique(round.(Int, range(1, n_samples; length = min(max_samples, n_samples))))

    xs = Vector{Float64}(undef, length(it))
    ys = Vector{Float64}(undef, length(it))
    for (k, i_trace) in enumerate(it)
        x, y = _extract_trace_xy(headers[i_trace]; pref = trace_xy)
        xs[k] = x
        ys[k] = y
    end

    nt = length(it)
    ns = length(is)
    X = Matrix{Float64}(undef, nt, ns)
    Y = Matrix{Float64}(undef, nt, ns)
    Z = Matrix{Float64}(undef, nt, ns)
    A = Matrix{Float32}(undef, nt, ns)

    for i in 1:nt
        xi = xs[i]
        yi = ys[i]
        for (k, i_sample) in enumerate(is)
            X[i, k] = xi
            Y[i, k] = yi
            Z[i, k] = -(Float64(top_z_m) + (i_sample - 1) * Float64(sample_spacing_m))
            A[i, k] = data[i_sample, it[i]]
        end
    end

    display_mode = _resolve_seismic_display_mode(display_mode)
    C = if display_mode == :envelope
        _normalize_amplitude(compute_seismic_envelope(A); clip_quantile = clip_quantile)
    else
        _normalize_amplitude(A; clip_quantile = clip_quantile)
    end

    return (
        X = X,
        Y = Y,
        Z = Z,
        C = C,
        line_x = xs,
        line_y = ys,
        line_z = -Float64(top_z_m),
        n_traces = n_traces,
        n_samples = n_samples,
        n_traces_used = nt,
        n_samples_used = ns
    )
end

function clip_seismic_curtain_to_depth(seismic_curtain, min_z::Real)
    seismic_curtain === nothing && return nothing
    keep = vec(seismic_curtain.Z[1, :] .>= Float64(min_z))
    any(keep) || return seismic_curtain
    return (
        X = seismic_curtain.X[:, keep],
        Y = seismic_curtain.Y[:, keep],
        Z = seismic_curtain.Z[:, keep],
        C = seismic_curtain.C[:, keep],
        line_x = seismic_curtain.line_x,
        line_y = seismic_curtain.line_y,
        line_z = seismic_curtain.line_z,
        n_traces = seismic_curtain.n_traces,
        n_samples = seismic_curtain.n_samples,
        n_traces_used = seismic_curtain.n_traces_used,
        n_samples_used = count(keep)
    )
end

function display_figure(fig; fullscreen::Bool = true)
    # Force first frame render off-screen so window opens with content, not a black flash
    try
        Makie.colorbuffer(fig)
    catch
    end
    if fullscreen
        try
            screen = GLMakie.Screen(; fullscreen = true, float = false, focus_on_show = true)
            display(screen, fig)
            return screen
        catch err
            @warn "Fullscreen display failed; falling back to normal window." exception=(err, catch_backtrace())
        end
    end
    screen = GLMakie.Screen(; focus_on_show = true)
    display(screen, fig)
    return screen
end

function _nice_tick_values(vmin::Real, vmax::Real; target_count::Int = 5)
    span = Float64(vmax) - Float64(vmin)
    span <= 0 && return [Float64(vmin)]
    step = _nice_scale_length(span / max(target_count - 1, 1))
    start = ceil(Float64(vmin) / step) * step
    vals = collect(start:step:(Float64(vmax) + 0.5 * step))
    isempty(vals) && return [Float64(vmin), Float64(vmax)]
    return vals
end

function _format_tick_value(v::Real; depth_axis::Bool = false)
    val = depth_axis ? abs(Float64(v)) : Float64(v)
    if abs(val) >= 1000
        return string(round(Int, val))
    end
    return string(round(val; digits = 1))
end

function draw_outer_axes!(ax; xv, yv, zv, color = :gray65)
    isempty(xv) && return Any[]
    isempty(yv) && return Any[]
    isempty(zv) && return Any[]

    xmin, xmax = extrema(xv)
    ymin, ymax = extrema(yv)
    zmin, zmax = extrema(zv)
    dx = xmax - xmin
    dy = ymax - ymin
    dz = max(zmax - zmin, eps(Float64))

    tick_x = 0.025 * dx
    tick_y = 0.025 * dy
    tick_z = 0.025 * dz

    plots = Any[]
    push!(plots, lines!(ax, [xmin, xmax], [ymin, ymin], [zmin, zmin], color = color, linewidth = 2.0))
    push!(plots, lines!(ax, [xmin, xmin], [ymin, ymax], [zmin, zmin], color = color, linewidth = 2.0))
    push!(plots, lines!(ax, [xmin, xmin], [ymin, ymin], [zmin, zmax], color = color, linewidth = 2.0))

    for xt in _nice_tick_values(xmin, xmax)
        push!(plots, lines!(ax, [xt, xt], [ymin, ymin - 0.35 * tick_y], [zmin, zmin], color = color, linewidth = 1.5))
        push!(plots, text!(ax, [xt], [ymin - 0.85 * tick_y], [zmin], text = [_format_tick_value(xt)], color = color, fontsize = 13, align = (:center, :top)))
    end
    for yt in _nice_tick_values(ymin, ymax)
        push!(plots, lines!(ax, [xmin - 0.35 * tick_x, xmin], [yt, yt], [zmin, zmin], color = color, linewidth = 1.5))
        push!(plots, text!(ax, [xmin - 0.85 * tick_x], [yt], [zmin], text = [_format_tick_value(yt)], color = color, fontsize = 13, align = (:right, :center)))
    end
    for zt in _nice_tick_values(zmin, zmax)
        push!(plots, lines!(ax, [xmin - 0.35 * tick_x, xmin], [ymin, ymin], [zt, zt], color = color, linewidth = 1.5))
        push!(plots, text!(ax, [xmin - 0.85 * tick_x], [ymin], [zt], text = [_format_tick_value(zt; depth_axis = true)], color = color, fontsize = 13, align = (:right, :center)))
    end

    push!(plots, text!(ax, [xmax + 0.55 * tick_x], [ymin], [zmin], text = ["X"], color = color, fontsize = 16, align = (:left, :center)))
    push!(plots, text!(ax, [xmin], [ymax + 0.55 * tick_y], [zmin], text = ["Y"], color = color, fontsize = 16, align = (:center, :bottom)))
    push!(plots, text!(ax, [xmin], [ymin], [zmax + 0.55 * tick_z], text = ["Z"], color = color, fontsize = 16, align = (:center, :bottom)))
    return plots
end

function fit_camera!(scene, xv, yv, zv)
    xmin, xmax = extrema(xv)
    ymin, ymax = extrema(yv)
    zmin, zmax = extrema(zv)
    center = Vec3f((xmin + xmax) / 2, (ymin + ymax) / 2, (zmin + zmax) / 2)
    spanx = Float32(xmax - xmin)
    spany = Float32(ymax - ymin)
    spanz = Float32(zmax - zmin)
    horiz = max(spanx, spany)
    zlift = max(spanz, 0.45f0 * horiz)
    dir_norm = sqrt(default_view_direction[1]^2 + default_view_direction[2]^2 + default_view_direction[3]^2)
    dirx = default_view_direction[1] / dir_norm
    diry = default_view_direction[2] / dir_norm
    dirz = default_view_direction[3] / dir_norm
    eye = center + Vec3f(default_view_scale * dirx * horiz,
                         default_view_scale * diry * horiz,
                         default_view_scale * dirz * zlift)
    update_cam!(scene, eye, center, Vec3f(0, 0, 1))
end

# XY extent for a scene with no model in it: whatever non-model content was configured,
# else a default box. Only ever called when nothing else defines the scene's size.
function _blank_scene_extent(seismic_curtain, overlays, overlay_transform, auto_reproject::Bool)
    xs, ys = Float64[], Float64[]
    if seismic_curtain !== nothing
        append!(xs, collect(extrema(seismic_curtain.X)))
        append!(ys, collect(extrema(seismic_curtain.Y)))
    end
    for entry in overlays, segment in TerraScope.shapefile_segments(entry.path;
            auto_reproject_to_wgs84 = auto_reproject, post_transform = overlay_transform)
        for (px, py) in segment
            push!(xs, px)
            push!(ys, py)
        end
    end
    isempty(xs) && return (-5000.0, 5000.0), (-5000.0, 5000.0)
    xlo, xhi = extrema(xs)
    ylo, yhi = extrema(ys)
    return (xlo - max(0.05 * (xhi - xlo), 500.0), xhi + max(0.05 * (xhi - xlo), 500.0)),
           (ylo - max(0.05 * (yhi - ylo), 500.0), yhi + max(0.05 * (yhi - ylo), 500.0))
end

function modem_3d_viewer_crosssections(
    M;
    primary_kind::Symbol = :resistivity,
    primary_name::AbstractString = "Resistivity",
    primary_available::Bool = true,
    density_model = nothing,
    susceptibility_model = nothing,
    overlays = NamedTuple[],
    data_layers = Dict{Symbol, Any}(),
    log10scale::Bool = true,
    cmap = :Spectral,
    figsize = (1760, 960),
    withPadding::Bool = true,
    max_depth::Union{Nothing, Real} = nothing,
    pad_tol::Real = 0.2,
    resistivity_range::Union{Nothing, Tuple{<:Real,<:Real}} = nothing,
    volume_display_ranges = (;
        density = nothing,
        susceptibility = nothing,
    ),
    overlay_transform = (x, y) -> (x, y),
    north_axis::Symbol = :y,
    xy_to_latlon = nothing,
    selector_show_latlon_ticks::Bool = false,
    seismic_curtain = nothing,
    seismic_display_mode::Symbol = :original,
    show_seismic_model_section_default::Bool = true,
    scene_only_default::Bool = false
)

    x_all = M.cx
    y_all = M.cy
    z_all = M.cz
    A_all = log10scale ? log10.(M.A) : M.A

    ix_full = 1:length(x_all)
    iy_full = 1:length(y_all)
    ix_core = core_indices(x_all; tol = pad_tol)
    iy_core = core_indices(y_all; tol = pad_tol)

    if withPadding
        ix = ix_full
        iy = iy_full
    else
        ix = ix_core
        iy = iy_core
    end

    if isnothing(max_depth)
        kz = 1:length(z_all)
    else
        kz = z_indices_for_max_depth(z_all, float(max_depth))
    end

    x = x_all[ix]
    y = y_all[iy]
    z = -z_all[kz]
    R = A_all[ix, iy, kz]

    export_stamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    export_dir_3d = joinpath(@__DIR__, "$(model_name_for_export)_Export3D_$(export_stamp)")
    export_dir_2d = joinpath(@__DIR__, "$(model_name_for_export)_Export2D_$(export_stamp)")
    export_dir_iso = joinpath(@__DIR__, "$(model_name_for_export)_ExportIso_$(export_stamp)")

    cmin, cmax = _resolve_display_range(R, resistivity_range)

    resistivity_volume = (
        name = primary_name,
        kind = primary_kind,
        x = x,
        y = y,
        z = z,
        values = R,
        cmin = cmin,
        cmax = cmax,
        cmap = cmap,
        label = _volume_colorbar_label(primary_kind, log10scale),
        logscale = log10scale,
    )

    density_volume = if density_model === nothing
        nothing
    else
        d_kz = isnothing(max_depth) ? (1:length(density_model.cz)) : z_indices_for_max_depth(density_model.cz, float(max_depth))
        d_vals = density_model.A[:, :, d_kz]
        d_cmin, d_cmax = _resolve_display_range(d_vals, get(volume_display_ranges, :density, nothing))
        (
            name = getproperty(density_model, :name),
            kind = :density,
            x = density_model.cx,
            y = density_model.cy,
            z = -density_model.cz[d_kz],
            values = d_vals,
            cmin = d_cmin,
            cmax = d_cmax,
            cmap = _volume_colormap(:density, cmap),
            label = _volume_colorbar_label(:density, false),
            logscale = false,
        )
    end

    susceptibility_volume = if susceptibility_model === nothing
        nothing
    else
        s_kz = isnothing(max_depth) ? (1:length(susceptibility_model.cz)) : z_indices_for_max_depth(susceptibility_model.cz, float(max_depth))
        s_vals = susceptibility_model.A[:, :, s_kz]
        s_cmin, s_cmax = _resolve_display_range(s_vals, get(volume_display_ranges, :susceptibility, nothing))
        (
            name = getproperty(susceptibility_model, :name),
            kind = :susceptibility,
            x = susceptibility_model.cx,
            y = susceptibility_model.cy,
            z = -susceptibility_model.cz[s_kz],
            values = s_vals,
            cmin = s_cmin,
            cmax = s_cmax,
            cmap = _volume_colormap(:susceptibility, cmap),
            label = _volume_colorbar_label(:susceptibility, false),
            logscale = false,
        )
    end

    volumes = Dict{Symbol, Any}(primary_kind => resistivity_volume)
    density_volume !== nothing && (volumes[:density] = density_volume)
    susceptibility_volume !== nothing && (volumes[:susceptibility] = susceptibility_volume)
    volume_order = Symbol[primary_kind]
    for (kind, volume) in ((:density, density_volume), (:susceptibility, susceptibility_volume))
        kind == primary_kind || volume === nothing || push!(volume_order, kind)
    end
    current_kind = Observable(first(volume_order))
    current_volume() = volumes[current_kind[]]

    layout_toggle_label(show_full::Bool) = show_full ? "Show 3D Only" : "Show Both Panels"
    drape_toggle_label(has_drape::Bool, visible::Bool) = !has_drape ? "Drape N/A" : (visible ? "Hide Drape" : "Show Drape")
    seismic_section_toggle_label(has_drape::Bool, visible::Bool) = !has_drape ? "Seismic Section N/A" : (visible ? "Hide Seismic Section" : "Show Seismic Section")

    function set_button_enabled!(btn, enabled::Bool, enabled_label::AbstractString, disabled_label::AbstractString)
        btn.label[] = enabled ? enabled_label : disabled_label
        if hasproperty(btn, :buttoncolor)
            btn.buttoncolor[] = enabled ? :gray92 : :gray78
        end
        if hasproperty(btn, :labelcolor)
            btn.labelcolor[] = enabled ? :black : :gray35
        end
        return nothing
    end

    _volume_buttons = Dict{Symbol, Any}()
    _volume_base_labels = Dict{Symbol, String}()
    function highlight_active_volume_button!(active_kind::Symbol)
        for (kind, btn) in _volume_buttons
            is_active = (kind == active_kind)
            base = get(_volume_base_labels, kind, String(kind))
            btn.font[] = is_active ? "TeX Gyre Heros Makie Bold" : "TeX Gyre Heros Makie"
        end
        return nothing
    end

    seismic_display_mode = _resolve_seismic_display_mode(seismic_display_mode)
    seismic_curtain_colormap = seismic_display_mode == :envelope ? seismic_envelope_colormap : seismic_colormap
    seismic_curtain_colorrange = seismic_display_mode == :envelope ? seismic_envelope_range : (-1.0, 1.0)

    fig = Figure(size = figsize, backgroundcolor = :gray95)
    ax = LScene(fig[1, 1], show_axis = false)
    controls = fig[2, 1] = GridLayout()
    selector_grid = fig[3, 1] = GridLayout()
    footer = fig[4, 1] = GridLayout()

    rowsize!(fig.layout, 1, Relative(0.60))
    rowsize!(fig.layout, 2, Auto(248))
    rowsize!(fig.layout, 3, Relative(0.30))
    rowsize!(fig.layout, 4, Auto(44))
    colsize!(fig.layout, 1, Relative(0.94))

    colorbar_slot = fig[1, 2] = GridLayout(tellwidth = false, tellheight = false, valign = :top)
    rowsize!(colorbar_slot, 1, Fixed(36))
    colorbar_widget = Colorbar(colorbar_slot[2, 1], colormap = current_volume().cmap, limits = (current_volume().cmin, current_volume().cmax), label = current_volume().label, width = 16)
    colsize!(fig.layout, 2, Relative(0.04))

    show_map_slice = Observable(false)
    show_seis_curtain = Observable(seismic_curtain !== nothing)
    show_data = Observable(false)
    show_seis_model_section = Observable(show_seismic_model_section_default)
    show_full_layout = Observable(!scene_only_default)

    view_controls = controls[1, 1] = GridLayout()
    section_controls = controls[2, 1] = GridLayout()
    iso_controls = controls[3, 1] = GridLayout()

    depth_slider = Slider(view_controls[1, 3], range = 1:length(z), startvalue = round(Int, length(z) / 2), width = 250)
    Label(view_controls[1, 1], "Depth:", halign = :right, fontsize = 12)
    btn_prev_depth = Button(view_controls[1, 2], label = "Prev", fontsize = 10)
    btn_next_depth = Button(view_controls[1, 4], label = "Next", fontsize = 10)
    depth_lbl = Label(view_controls[1, 5], "Depth: $(round(-z[depth_slider.value[]], digits=0)) m", fontsize = 10, color = :gray35)

    btn_toggle_map = Button(view_controls[1, 6], label = "Show Map Slice", fontsize = 10)
    btn_toggle_seis_curtain = Button(view_controls[1, 7], label = drape_toggle_label(seismic_curtain !== nothing, show_seis_model_section[]), fontsize = 10)
    btn_toggle_seis_section = Button(view_controls[1, 8], label = seismic_section_toggle_label(seismic_curtain !== nothing, show_seis_curtain[]), fontsize = 10)
    btn_reset = Button(view_controls[1, 9], label = "Reset View", fontsize = 10)
    btn_export_3d = Button(view_controls[1, 10], label = "Export 3D", fontsize = 10)
    # One button per property, whether or not a file was configured for it; a property
    # with no volume behind it reads "N/A" and does nothing when pressed.
    property_labels = ((:resistivity, "Resistivity"), (:density, "Density"), (:susceptibility, "Susceptibility"))
    for (offset, (kind, label)) in enumerate(property_labels)
        have = haskey(volumes, kind) && (kind != primary_kind || primary_available)
        text = have ? label : "$label N/A"
        _volume_buttons[kind] = Button(view_controls[1, 10 + offset], label = text, fontsize = 10)
        _volume_base_labels[kind] = text
    end
    highlight_active_volume_button!(current_kind[])

    # Measured data for whichever property is on screen: MT site locations, or the
    # survey points behind a gravity/magnetic model.
    data_toggle_label() = !haskey(data_layers, current_kind[]) ? "Data N/A" :
        (show_data[] ? "Hide Data" : "Show Data")
    btn_toggle_data = Button(view_controls[1, 14], label = data_toggle_label(), fontsize = 10)

    btn_finish_section = Button(section_controls[1, 1], label = "Finish Section", fontsize = 9)
    btn_clear_points = Button(section_controls[1, 2], label = "Clear Points", fontsize = 9)
    btn_undo = Button(section_controls[1, 3], label = "Undo Section", fontsize = 9)
    btn_clear_all = Button(section_controls[1, 4], label = "Clear Sections", fontsize = 9)
    Label(section_controls[1, 5], "Active:", halign = :right, fontsize = 11)
    btn_prev_sec = Button(section_controls[1, 6], label = "Prev", fontsize = 9)
    active_sec_label = Label(section_controls[1, 7], "S0", fontsize = 10, color = :gray35)
    btn_next_sec = Button(section_controls[1, 8], label = "Next", fontsize = 9)
    btn_export_2d = Button(section_controls[1, 9], label = "Export 2D Sections", fontsize = 10)
    Label(section_controls[1, 10], "2D max depth (km):", halign = :right, fontsize = 10)
    default_export_depth_km = round(maximum(-z) / 1000.0; digits = 2)
    export_2d_depth_km_tb = Textbox(section_controls[1, 11], stored_string = string(default_export_depth_km), width = 70)

    function iso_defaults(volume)
        defaults = if volume.kind == :resistivity
            (0.0, 10.0)
        elseif volume.kind == :density
            (2.8, 2.85)
        else
            (0.005, 0.05)
        end
        return (
            default_iso_min = defaults[1],
            default_iso_max = defaults[2],
            default_iso_depth_start_km = 0.0,
            default_iso_depth_end_km = round(maximum(-volume.z) / 1000.0; digits = 2),
        )
    end

    iso0 = iso_defaults(current_volume())
    Label(iso_controls[1, 1], "Isosurface", halign = :left, fontsize = 11, color = :gray25)
    iso_min_label = Label(iso_controls[1, 2], "Iso min ($(_volume_units_label(current_volume().kind))):", halign = :right, fontsize = 10)
    iso_min_tb = Textbox(iso_controls[1, 3], stored_string = string(iso0.default_iso_min), width = 70)
    iso_max_label = Label(iso_controls[1, 4], "Iso max ($(_volume_units_label(current_volume().kind))):", halign = :right, fontsize = 10)
    iso_max_tb = Textbox(iso_controls[1, 5], stored_string = string(iso0.default_iso_max), width = 70)
    Label(iso_controls[1, 6], "Start depth (km):", halign = :right, fontsize = 10)
    iso_depth_start_tb = Textbox(iso_controls[1, 7], stored_string = string(iso0.default_iso_depth_start_km), width = 70)
    Label(iso_controls[1, 8], "End depth (km):", halign = :right, fontsize = 10)
    iso_depth_end_tb = Textbox(iso_controls[1, 9], stored_string = string(iso0.default_iso_depth_end_km), width = 70)
    Label(iso_controls[1, 10], "Opacity (0.05-0.95):", halign = :right, fontsize = 10)
    iso_opacity_tb = Textbox(iso_controls[1, 11], stored_string = string(round(isosurface_defaults.alpha, digits = 2)), width = 80)
    btn_iso_color_mode = Button(iso_controls[1, 12], label = isosurface_defaults.color_by_depth ? "Color: Depth" : "Color: Property", fontsize = 9, width = 130)
    btn_apply_iso = Button(iso_controls[1, 13], label = "Apply Iso", fontsize = 9, width = 90)
    btn_clear_iso = Button(iso_controls[1, 14], label = "Clear Iso", fontsize = 9, width = 90)
    btn_export_iso = Button(iso_controls[1, 15], label = "Export Iso DXF", fontsize = 10)
    Label(iso_controls[2, 1], "Visible:", halign = :right, fontsize = 10)
    iso_checkboxes = Dict{Symbol, Any}()
    for (offset, (kind, label)) in enumerate(property_labels)
        have = haskey(volumes, kind) && (kind != primary_kind || primary_available)
        iso_checkboxes[kind] = Checkbox(iso_controls[2, 2offset], checked = have)
        Label(iso_controls[2, 2offset + 1], have ? label : "$label N/A", fontsize = 10,
            color = have ? :gray30 : :gray55)
    end

    selector_ax = Axis(selector_grid[1, 1], title = "XY selector: left-click to add points, right-click/Finish to create section", aspect = DataAspect())

    function update_selector_ticks!()
        vol = current_volume()
        xtick_vals = _nice_tick_values(minimum(vol.x), maximum(vol.x); target_count = 4)
        ytick_vals = _nice_tick_values(minimum(vol.y), maximum(vol.y); target_count = 4)

        selector_ax.xticks = xtick_vals
        selector_ax.yticks = ytick_vals
    end

    if selector_show_latlon_ticks && xy_to_latlon !== nothing
        yref = mean(y)
        xref = mean(x)
        selector_ax.xlabel = "Lon (°)"
        selector_ax.ylabel = "Lat (°)"
        selector_ax.xtickformat = vals -> [begin
            lon, _ = xy_to_latlon(Float64(v), yref)
            string(round(lon, digits = 2))
        end for v in vals]
        selector_ax.ytickformat = vals -> [begin
            _, lat = xy_to_latlon(xref, Float64(v))
            string(round(lat, digits = 2))
        end for v in vals]
    else
        selector_ax.xlabel = "Easting (m)"
        selector_ax.ylabel = "Northing (m)"
        selector_ax.xtickformat = vals -> [_format_tick_value(v) for v in vals]
        selector_ax.ytickformat = vals -> [_format_tick_value(v) for v in vals]
    end

    x_edges = edges_from_centers(current_volume().x)
    y_edges = edges_from_centers(current_volume().y)
    selector_slice = Observable(copy(current_volume().values[:, :, depth_slider.value[]]))
    selector_hm = heatmap!(selector_ax, x_edges, y_edges, selector_slice, colormap = current_volume().cmap, colorrange = (current_volume().cmin, current_volume().cmax))
    update_selector_ticks!()
    colsize!(selector_grid, 1, Relative(1.0))

    section_paths = Observable(Vector{Vector{Tuple{Float64, Float64}}}())
    active_section = Observable(0)
    pending_points = Observable(Point2f[])
    axis_info = Observable("")
    export_status = Observable("No exports yet")

    selector_section_lines = Observable(Point2f[])
    lines!(selector_ax, selector_section_lines, color = :black, linewidth = 1.5)
    scatter!(selector_ax, pending_points, color = :red, markersize = 8)
    pending_line = @lift length($pending_points) >= 2 ? $pending_points : Point2f[]
    lines!(selector_ax, pending_line, color = :red, linewidth = 2, linestyle = :dash)

    Label(footer[1, 1], axis_info, fontsize = 11, color = :gray30, halign = :left, tellwidth = false)
    Label(footer[1, 2], "CRS: $(target_crs)", fontsize = 11, color = :gray35, halign = :right)
    Label(footer[2, 1:2], export_status, fontsize = 11, color = :gray25, halign = :left, tellwidth = false)

    rowgap!(controls, 4)
    colgap!(controls, 5)
    colgap!(view_controls, 6)
    colgap!(section_controls, 6)
    colgap!(iso_controls, 6)

    seismic_path_model = Tuple{Float64, Float64}[]
    if seismic_curtain !== nothing
        xmin, xmax = extrema(x)
        ymin, ymax = extrema(y)
        for i in eachindex(seismic_curtain.line_x)
            sx = Float64(seismic_curtain.line_x[i])
            sy = Float64(seismic_curtain.line_y[i])
            if !(isfinite(sx) && isfinite(sy))
                continue
            end
            if sx < xmin || sx > xmax || sy < ymin || sy > ymax
                continue
            end
            if !isempty(seismic_path_model)
                px, py = seismic_path_model[end]
                hypot(sx - px, sy - py) < 1e-6 && continue
            end
            push!(seismic_path_model, (sx, sy))
        end
    end
    seismic_curtain_clipped = clip_seismic_curtain_to_depth(seismic_curtain, minimum(z))

    corner_controls = GridLayout(fig[1, 1], tellwidth = false, tellheight = false, halign = :right, valign = :top)
    rowsize!(corner_controls, 1, Fixed(36))
    btn_toggle_view_mode = Button(corner_controls[2, 1], label = layout_toggle_label(show_full_layout[]), fontsize = 11, width = 150)
    section_count() = length(section_paths[])

    function update_selector_lines!()
        pts = Point2f[]
        for i in 1:section_count()
            path = section_paths[][i]
            for p in path
                push!(pts, Point2f(p[1], p[2]))
            end
            push!(pts, Point2f(NaN, NaN))
        end
        selector_section_lines[] = pts
    end

    function set_active_section!(idx::Int)
        n = section_count()
        if n == 0
            active_section[] = 0
            active_sec_label.text[] = "S0"
            return
        end

        idxc = clamp(idx, 1, n)
        active_section[] = idxc
        active_sec_label.text[] = "S$(idxc) / $(n)"
    end

    function add_section_from_polyline!(pts::Vector{Point2f})
        length(pts) < 2 && return false
        path = [(Float64(p[1]), Float64(p[2])) for p in pts]
        p1 = first(path)
        p2 = last(path)
        dx = p2[1] - p1[1]
        dy = p2[2] - p1[2]
        seglen = hypot(dx, dy)
        seglen < 1e-6 && return false

        paths = copy(section_paths[])
        push!(paths, path)

        section_paths[] = paths

        set_active_section!(length(paths))
        return true
    end

    function update_axis_info!()
        vol = current_volume()
        dval = -vol.z[depth_slider.value[]]
        drape_status = (seismic_curtain !== nothing && show_seis_model_section[]) ? "ON" : "OFF"
        seismic_section_status = (seismic_curtain !== nothing && show_seis_curtain[]) ? "ON" : "OFF"
        axis_info[] = "Volume: $(vol.name)   |   Depth: $(round(dval, digits=0)) m   |   Sections: $(section_count())   |   Map slice: $(show_map_slice[] ? "ON" : "OFF")   |   Drape: $(drape_status)   |   Seismic section: $(seismic_section_status)"
    end

    function update_volume_controls!()
        vol = current_volume()
        depth_lbl.text[] = "Depth: $(round(-vol.z[depth_slider.value[]], digits=0)) m"
        colorbar_widget.colormap = vol.cmap
        colorbar_widget.limits = (vol.cmin, vol.cmax)
        colorbar_widget.label = vol.label
        selector_hm.colormap = vol.cmap
        selector_hm.colorrange = (vol.cmin, vol.cmax)
        selector_slice[] = copy(vol.values[:, :, depth_slider.value[]])
        update_selector_ticks!()
        btn_iso_color_mode.label[] = iso_color_by_depth[] ? "Color: Depth" : "Color: Property"
        iso_min_label.text[] = "Iso min ($(_volume_units_label(vol.kind))):"
        iso_max_label.text[] = "Iso max ($(_volume_units_label(vol.kind))):"
        defs = iso_defaults(vol)
        _set_textbox!(iso_min_tb, string(defs.default_iso_min))
        _set_textbox!(iso_max_tb, string(defs.default_iso_max))
        _set_textbox!(iso_depth_start_tb, string(defs.default_iso_depth_start_km))
        _set_textbox!(iso_depth_end_tb, string(defs.default_iso_depth_end_km))
        _set_textbox!(iso_opacity_tb, string(round(get(iso_alpha_by_kind, vol.kind, clamp(Float64(isosurface_defaults.alpha), 0.05, 0.95)), digits = 2)))
        highlight_active_volume_button!(current_kind[])
    end

    dynamic_plots = Any[]
    isosurface_plots = Any[]
    axis_overlay_plots = Any[]

    # Observable data for the map slice so depth changes update in-place
    _map_slice_z = Observable(fill(z[1], length(x), length(y)))
    _map_slice_color = Observable(zeros(Float64, length(x), length(y)))
    _map_slice_handle = Ref{Any}(nothing)
    isosurface_triangles = Dict{Symbol, Vector{NTuple{3, NTuple{3, Float64}}}}()
    isosurface_params = Dict{Symbol, Dict{String, Any}}()
    iso_color_by_depth = Observable(Bool(isosurface_defaults.color_by_depth))
    iso_alpha_by_kind = Dict{Symbol, Float64}(kind => clamp(Float64(isosurface_defaults.alpha), 0.05, 0.95) for kind in volume_order)
    iso_visibility = Dict(kind => box.checked for (kind, box) in iso_checkboxes)

    function clear_dynamic_plots!()
        for p in reverse(dynamic_plots)
            try
                delete!(ax.scene, p)
            catch
                try
                    delete!(ax, p)
                catch
                end
            end
        end
        empty!(dynamic_plots)
        _map_slice_handle[] = nothing
    end

    function clear_isosurface_plots!(kind::Union{Nothing, Symbol} = nothing)
        for p in reverse(isosurface_plots)
            try
                delete!(ax.scene, p)
            catch
                try
                    delete!(ax, p)
                catch
                end
            end
        end
        empty!(isosurface_plots)
        if isnothing(kind)
            empty!(isosurface_triangles)
            empty!(isosurface_params)
        else
            pop!(isosurface_triangles, kind, nothing)
            pop!(isosurface_params, kind, nothing)
        end
    end

    function clear_isosurface_scene_plots!()
        for p in reverse(isosurface_plots)
            try
                delete!(ax.scene, p)
            catch
                try
                    delete!(ax, p)
                catch
                end
            end
        end
        empty!(isosurface_plots)
    end

    function clear_axis_overlay!()
        for p in reverse(axis_overlay_plots)
            try
                delete!(ax.scene, p)
            catch
                try
                    delete!(ax, p)
                catch
                end
            end
        end
        empty!(axis_overlay_plots)
    end

    _textbox_text(tb) = hasproperty(tb, :displayed_string) ? strip(tb.displayed_string[]) :
                        (hasproperty(tb, :stored_string) ? strip(tb.stored_string[]) : "")

    function _set_textbox!(tb, val::AbstractString)
        if hasproperty(tb, :stored_string)
            tb.stored_string[] = val
        end
        if hasproperty(tb, :displayed_string)
            tb.displayed_string[] = val
        end
    end

    function parse_isosurface_controls!()
        vol = current_volume()
        defs = iso_defaults(vol)
        raw_min = _textbox_text(iso_min_tb)
        raw_max = _textbox_text(iso_max_tb)
        raw_dstart = _textbox_text(iso_depth_start_tb)
        raw_dend = _textbox_text(iso_depth_end_tb)
        raw_alpha = _textbox_text(iso_opacity_tb)

        vmin_disp = try
            isempty(raw_min) ? defs.default_iso_min : parse(Float64, raw_min)
        catch
            defs.default_iso_min
        end
        vmax_disp = try
            isempty(raw_max) ? defs.default_iso_max : parse(Float64, raw_max)
        catch
            defs.default_iso_max
        end

        dstart_km = try
            isempty(raw_dstart) ? defs.default_iso_depth_start_km : parse(Float64, raw_dstart)
        catch
            defs.default_iso_depth_start_km
        end
        dend_km = try
            isempty(raw_dend) ? defs.default_iso_depth_end_km : parse(Float64, raw_dend)
        catch
            defs.default_iso_depth_end_km
        end
        alpha_val = try
            isempty(raw_alpha) ? get(iso_alpha_by_kind, vol.kind, clamp(Float64(isosurface_defaults.alpha), 0.05, 0.95)) : parse(Float64, raw_alpha)
        catch
            get(iso_alpha_by_kind, vol.kind, clamp(Float64(isosurface_defaults.alpha), 0.05, 0.95))
        end

        dstart_km = max(0.0, dstart_km)
        dend_km = max(0.0, dend_km)
        if dstart_km > dend_km
            dstart_km, dend_km = dend_km, dstart_km
        end
        alpha_val = clamp(alpha_val, 0.05, 0.95)

        cmin_display = _internal_to_physical(vol.kind, vol.cmin; logscale = vol.logscale)
        cmax_display = _internal_to_physical(vol.kind, vol.cmax; logscale = vol.logscale)
        vmin_disp, vmax_disp = _sanitize_iso_range(vmin_disp, vmax_disp, cmin_display, cmax_display)
        vmin_internal = _physical_to_internal(vol.kind, vmin_disp; logscale = vol.logscale)
        vmax_internal = _physical_to_internal(vol.kind, vmax_disp; logscale = vol.logscale)
        vmin_internal, vmax_internal = _sanitize_iso_range(vmin_internal, vmax_internal, vol.cmin, vol.cmax)

        _set_textbox!(iso_min_tb, string(round(vmin_disp, digits = 4)))
        _set_textbox!(iso_max_tb, string(round(vmax_disp, digits = 4)))
        _set_textbox!(iso_depth_start_tb, string(round(dstart_km, digits = 4)))
        _set_textbox!(iso_depth_end_tb, string(round(dend_km, digits = 4)))
        _set_textbox!(iso_opacity_tb, string(round(alpha_val, digits = 2)))
        iso_alpha_by_kind[vol.kind] = alpha_val
        return vmin_disp, vmax_disp, vmin_internal, vmax_internal, dstart_km * 1000.0, dend_km * 1000.0, alpha_val
    end

    function apply_isosurfaces!()
        vol = current_volume()
        clear_isosurface_plots!(vol.kind)

        vmin_disp, vmax_disp, vmin_internal, vmax_internal, dstart_m, dend_m, alpha_val = parse_isosurface_controls!()
        tris, selected_samples, iso_levels = build_range_isosurface_triangles(vol.x, vol.y, vol.z, vol.values, vmin_internal, vmax_internal, dstart_m, dend_m;
            stride = max(1, isosurface_defaults.stride))

        if isempty(tris)
            export_status[] = "Isosurface volume: no cells in selected value/depth range"
            isosurface_triangles[vol.kind] = NTuple{3, NTuple{3, Float64}}[]
            isosurface_params[vol.kind] = Dict(
                "vmin_display" => vmin_disp,
                "vmax_display" => vmax_disp,
                "vmin_internal" => vmin_internal,
                "vmax_internal" => vmax_internal,
                "depth_start_m" => dstart_m,
                "depth_end_m" => dend_m,
                "volume_kind" => vol.kind,
                "color_by_depth" => iso_color_by_depth[],
                "stride" => max(1, isosurface_defaults.stride),
                "alpha" => alpha_val,
                "selected_samples" => 0,
                "iso_levels" => iso_levels,
                "triangles" => 0,
            )
        else
            verts, faces = _triangles_to_vertices_faces(tris)

            h_iso = _draw_isosurface_mesh!(ax, verts, faces, vol;
                color_by_depth = iso_color_by_depth[],
                depth_start_m = dstart_m,
                depth_end_m = dend_m,
                alpha_val = alpha_val,
                vmin_internal = vmin_internal,
                vmax_internal = vmax_internal)
            push!(isosurface_plots, h_iso)

            isosurface_triangles[vol.kind] = tris
            isosurface_params[vol.kind] = Dict(
                "vmin_display" => vmin_disp,
                "vmax_display" => vmax_disp,
                "vmin_internal" => vmin_internal,
                "vmax_internal" => vmax_internal,
                "depth_start_m" => dstart_m,
                "depth_end_m" => dend_m,
                "volume_kind" => vol.kind,
                "color_by_depth" => iso_color_by_depth[],
                "stride" => max(1, isosurface_defaults.stride),
                "alpha" => alpha_val,
                "selected_samples" => selected_samples,
                "iso_levels" => iso_levels,
                "triangles" => length(tris),
            )
            export_status[] = "Smooth isosurface $(vol.name) updated: $(round(vmin_disp, digits=3))–$(round(vmax_disp, digits=3)) $(_volume_units_label(vol.kind)), opacity=$(round(alpha_val, digits=2)), samples=$(selected_samples), faces=$(length(tris))"
        end
    end

    function draw_active_isosurfaces!(target_ax)
        isempty(isosurface_triangles) && return nothing
        last_plot = nothing
        for kind in volume_order
            tris = get(isosurface_triangles, kind, NTuple{3, NTuple{3, Float64}}[])
            isempty(tris) && continue
            haskey(iso_visibility, kind) || continue
            Bool(iso_visibility[kind][]) || continue
            verts, faces = _triangles_to_vertices_faces(tris)
            params = get(isosurface_params, kind, Dict{String, Any}())
            color_by_depth = Bool(get(params, "color_by_depth", false))
            depth_start_m = Float64(get(params, "depth_start_m", 0.0))
            depth_end_m = Float64(get(params, "depth_end_m", maximum(-current_volume().z)))
            alpha_val = Float64(get(params, "alpha", clamp(isosurface_defaults.alpha, 0.05, 0.95)))
            vol = volumes[kind]
            vmin_internal = Float64(get(params, "vmin_internal", vol.cmin))
            vmax_internal = Float64(get(params, "vmax_internal", vol.cmax))

            h_iso = _draw_isosurface_mesh!(target_ax, verts, faces, vol;
                color_by_depth = color_by_depth,
                depth_start_m = depth_start_m,
                depth_end_m = depth_end_m,
                alpha_val = alpha_val,
                vmin_internal = vmin_internal,
                vmax_internal = vmax_internal)

            if target_ax === ax
                push!(isosurface_plots, h_iso)
            end
            last_plot = h_iso
        end
        return last_plot
    end

    function export_isosurfaces_dxf!()
        vol = current_volume()
        tris = get(isosurface_triangles, vol.kind, NTuple{3, NTuple{3, Float64}}[])
        if isempty(tris)
            export_status[] = "DXF export skipped: no isosurfaces"
            println("No isosurface geometry to export.")
            return nothing
        end

        mkpath(export_dir_iso)
        params = get(isosurface_params, vol.kind, Dict{String, Any}())
        vmin_display = get(params, "vmin_display", NaN)
        vmax_display = get(params, "vmax_display", NaN)
        vol_kind = vol.kind

        function _fmt_range_token(v)
            s = string(round(Float64(v), digits = 6))
            if occursin('.', s)
                s = rstrip(s, '0')
                s = rstrip(s, '.')
            end
            isempty(s) && (s = "0")
            return replace(replace(s, "." => "p"), "-" => "m")
        end
        units_token = vol_kind == :density ? "g_cc" : "ohm_m"
        range_tag = if isfinite(vmin_display) && isfinite(vmax_display)
            "_iso_range_$( _fmt_range_token(vmin_display) )_to_$( _fmt_range_token(vmax_display) )_$(units_token)"
        else
            "_iso_range"
        end

        outpath = joinpath(export_dir_iso, "$(model_name_for_export)_$(String(vol.kind))$(range_tag).dxf")
        open(outpath, "w") do io
            println(io, "0")
            println(io, "SECTION")
            println(io, "2")
            println(io, "ENTITIES")

            for tri in tris
                _write_dxf_3dface!(io, tri[1], tri[2], tri[3]; layer = "ISO_VOLUME")
            end

            println(io, "0")
            println(io, "ENDSEC")
            println(io, "0")
            println(io, "EOF")
        end

        tri_count = length(tris)
        export_status[] = "Exported iso-volume DXF: $(basename(outpath)) ($(tri_count) faces)"
        println("Exported iso-volume DXF: $outpath")
        return outpath
    end

    function draw_scene_on_axis!(target_ax; include_map_slice::Bool)
        vol = current_volume()
        iz = min(depth_slider.value[], length(vol.z))

        layer = show_data[] ? get(data_layers, current_kind[], nothing) : nothing
        if layer !== nothing
            step = max(1, cld(length(layer.x), survey_max_points))
            inds = 1:step:length(layer.x)
            h_data = if layer.values === nothing
                scatter!(target_ax, layer.x[inds], layer.y[inds], layer.z[inds];
                    color = data_marker_color, markersize = 1.6 * survey_markersize,
                    marker = :utriangle)
            else
                scatter!(target_ax, layer.x[inds], layer.y[inds], layer.z[inds];
                    color = layer.values[inds], colormap = survey_colormap,
                    colorrange = layer.colorrange, markersize = survey_markersize)
            end
            target_ax === ax && push!(dynamic_plots, h_data)
        end

        if include_map_slice
            if target_ax === ax
                # Use persistent Observable-backed map slice for the main axis
                _map_slice_z[] = fill(vol.z[iz], length(vol.x), length(vol.y))
                _map_slice_color[] = vol.values[:, :, iz]
                if _map_slice_handle[] === nothing
                    h_map = surface!(ax, vol.x, vol.y, _map_slice_z;
                        color = _map_slice_color,
                        colormap = vol.cmap,
                        colorrange = (vol.cmin, vol.cmax),
                        shading = NoShading)
                    _map_slice_handle[] = h_map
                    push!(dynamic_plots, h_map)
                end
            else
                # Export path: create a fresh one-off surface
                zmap = fill(vol.z[iz], length(vol.x), length(vol.y))
                cmap_slice = vol.values[:, :, iz]
                h_map = surface!(target_ax, vol.x, vol.y, zmap;
                    color = cmap_slice,
                    colormap = vol.cmap,
                    colorrange = (vol.cmin, vol.cmax),
                    shading = NoShading)
            end
        end

        if seismic_curtain_clipped !== nothing && show_seis_curtain[]
            h_curtain = surface!(target_ax,
                seismic_curtain_clipped.X,
                seismic_curtain_clipped.Y,
                seismic_curtain_clipped.Z;
                color = seismic_curtain_clipped.C,
                colormap = seismic_curtain_colormap,
                colorrange = seismic_curtain_colorrange,
                shading = NoShading,
                transparency = true,
                alpha = seismic_curtain_alpha)
            h_line = lines!(target_ax,
                seismic_curtain_clipped.line_x,
                seismic_curtain_clipped.line_y,
                fill(seismic_curtain_clipped.line_z, length(seismic_curtain_clipped.line_x));
                color = seismic_line_color,
                linewidth = seismic_line_width)
            if target_ax === ax
                push!(dynamic_plots, h_curtain)
                push!(dynamic_plots, h_line)
            end
        end

        for i in 1:section_count()
            path = section_paths[][i]
            Xs, Ys, Zs, Cs, _ = build_section_surface_polyline(vol.x, vol.y, vol.z, vol.values, path; nsamp = section_samples_along)
            h_sec = surface!(target_ax,
                Xs,
                Ys,
                Zs;
                color = Cs,
                colormap = vol.cmap,
                colorrange = (vol.cmin, vol.cmax),
                shading = NoShading,
                transparency = true,
                alpha = 0.94)
            target_ax === ax && push!(dynamic_plots, h_sec)
        end

        if seismic_curtain !== nothing && show_seis_model_section[] && length(seismic_path_model) >= 2
            Xs, Ys, Zs, Cs, _ = build_section_surface_polyline(vol.x, vol.y, vol.z, vol.values, seismic_path_model; nsamp = section_samples_along)
            h_seis_sec = surface!(target_ax,
                Xs,
                Ys,
                Zs;
                color = Cs,
                colormap = vol.cmap,
                colorrange = (vol.cmin, vol.cmax),
                shading = NoShading,
                transparency = true,
                alpha = projected_resistivity_alpha)
            target_ax === ax && push!(dynamic_plots, h_seis_sec)
        end
    end

    function draw_static_overlays!(target_scene)
        vol = current_volume()
        for entry in overlays
            plot_shapefile_on_3d!(target_scene, entry.path;
                z_fixed = overlay_z_fixed,
                line_color = entry.color,
                line_width = entry.width,
                alpha = entry.alpha,
                auto_reproject_to_wgs84 = overlay_auto_reproject_to_wgs84,
                post_transform = overlay_transform,
                xlim = extrema(vol.x),
                ylim = extrema(vol.y))
        end

        draw_north_and_scale!(target_scene;
            xv = vol.x,
            yv = vol.y,
            z_fixed = overlay_z_fixed,
            target_crs = target_crs,
            north_axis = north_axis,
            show_north = show_north_arrow,
            show_scale = show_scale_bar,
            color = annotation_color,
            line_width = annotation_line_width)
    end

    function redraw_scene!()
        eye, look, up = get_camera_triplet(ax.scene)
        clear_dynamic_plots!()
        clear_isosurface_scene_plots!()
        draw_scene_on_axis!(ax; include_map_slice = show_map_slice[])
        draw_active_isosurfaces!(ax)
        update_selector_lines!()
        clear_axis_overlay!()
        vol = current_volume()
        if show_outer_ticks_axis
            append!(axis_overlay_plots, draw_outer_axes!(ax; xv = vol.x, yv = vol.y, zv = vol.z, color = :gray65))
        end
        if eye !== nothing && look !== nothing && up !== nothing
            update_cam!(ax.scene, eye, look, up)
        end
    end

    function update_depth_slice!()
        vol = current_volume()
        iz = min(depth_slider.value[], length(vol.z))
        depth_lbl.text[] = "Depth: $(round(-vol.z[iz], digits=0)) m"
        selector_slice[] = vol.values[:, :, iz]
        if show_map_slice[]
            _map_slice_z[] = fill(vol.z[iz], length(vol.x), length(vol.y))
            _map_slice_color[] = vol.values[:, :, iz]
        end
    end

    function update_layout_mode!()
        if show_full_layout[]
            rowsize!(fig.layout, 1, Relative(0.60))
            rowsize!(fig.layout, 2, Auto(248))
            rowsize!(fig.layout, 3, Relative(0.30))
            rowsize!(fig.layout, 4, Auto(44))
            colsize!(fig.layout, 2, Relative(0.04))
        else
            rowsize!(fig.layout, 1, Relative(1.0))
            rowsize!(fig.layout, 2, Fixed(0))
            rowsize!(fig.layout, 3, Fixed(0))
            rowsize!(fig.layout, 4, Fixed(0))
            colsize!(fig.layout, 2, Fixed(0))
        end
        colorbar_widget.blockscene.visible[] = show_full_layout[]
        selector_ax.blockscene.visible[] = show_full_layout[]
        btn_toggle_view_mode.label[] = layout_toggle_label(show_full_layout[])
    end

    function get_camera_triplet(scene)
        cam = cameracontrols(scene)
        if hasproperty(cam, :eyeposition) && hasproperty(cam, :lookat) && hasproperty(cam, :upvector)
            return Vec3f(cam.eyeposition[]), Vec3f(cam.lookat[]), Vec3f(cam.upvector[])
        end
        return nothing, nothing, nothing
    end

    function camera_filename_tag(eye::Vec3f, look::Vec3f)
        dx = Float64(eye[1] - look[1])
        dy = Float64(eye[2] - look[2])
        dz = Float64(eye[3] - look[3])
        az = atan(dy, dx) * 180.0 / pi
        horiz = hypot(dx, dy)
        el = atan(dz, max(horiz, eps(Float64))) * 180.0 / pi
        dist = sqrt(dx^2 + dy^2 + dz^2)

        fmt(v) = replace(string(round(v, digits = 1)), "-" => "m", "." => "p")
        return "az$(fmt(az))_el$(fmt(el))_d$(fmt(dist))"
    end

    function export_3d_view!()
        vol = current_volume()
        eye, look, up = get_camera_triplet(ax.scene)

        view_tag = (eye === nothing || look === nothing) ? "view_unknown" : camera_filename_tag(eye, look)

        filename = "$(model_name_for_export)_$(String(vol.kind))_3D_CA($(view_tag)).png"
        mkpath(export_dir_3d)
        outpath = joinpath(export_dir_3d, filename)

        export_fig = Figure(size = figsize)
        export_ax = LScene(export_fig[1, 1], show_axis = false)
        colsize!(export_fig.layout, 1, Relative(0.96))
        cb = Colorbar(export_fig[1, 2], colormap = vol.cmap, limits = (vol.cmin, vol.cmax), label = vol.label, width = 16)
        colsize!(export_fig.layout, 2, Relative(0.04))

        draw_scene_on_axis!(export_ax; include_map_slice = show_map_slice[])
        draw_active_isosurfaces!(export_ax)
        draw_static_overlays!(export_ax)
        if show_outer_ticks_axis
            draw_outer_axes!(export_ax; xv = x, yv = y, zv = z, color = :gray65)
        end

        if eye !== nothing && look !== nothing && up !== nothing
            update_cam!(export_ax.scene, eye, look, up)
        else
            fit_camera!(export_ax.scene, vol.x, vol.y, vol.z)
        end

        resize_to_layout!(export_fig)
        cb.blockscene.visible[] = true
        save(outpath, export_fig, px_per_unit = export_png_scale)

        println("Exported 3D view: $outpath")
        export_status[] = "Exported 3D: $(basename(outpath))"
        return outpath
    end

    function export_2d_all_sections!()
        vol = current_volume()
        nsec = section_count()
        if nsec == 0
            println("No sections to export.")
            export_status[] = "2D export skipped: no sections"
            return
        end

        raw_depth_txt = ""
        if hasproperty(export_2d_depth_km_tb, :displayed_string)
            raw_depth_txt = strip(export_2d_depth_km_tb.displayed_string[])
        elseif hasproperty(export_2d_depth_km_tb, :stored_string)
            raw_depth_txt = strip(export_2d_depth_km_tb.stored_string[])
        end

        max_depth_km = try
            isempty(raw_depth_txt) ? default_export_depth_km : parse(Float64, raw_depth_txt)
        catch
            default_export_depth_km
        end
        max_depth_km = max(0.0, max_depth_km)

        if hasproperty(export_2d_depth_km_tb, :stored_string)
            export_2d_depth_km_tb.stored_string[] = string(max_depth_km)
        end
        if hasproperty(export_2d_depth_km_tb, :displayed_string)
            export_2d_depth_km_tb.displayed_string[] = string(max_depth_km)
        end

        max_depth_m = max(0.0, max_depth_km * 1000.0)

        depth_centers_full = -vol.z
        keep = findall(depth_centers_full .<= max_depth_m)
        if isempty(keep)
            println("No depth samples available up to $(round(max_depth_km, digits=2)) km for 2D export.")
            export_status[] = "2D export skipped: no samples within depth limit"
            return
        end
 
        depth_centers = depth_centers_full[keep]
        depth_query_m = depth_centers
        depth_query_interp_m = collect(range(minimum(depth_centers), maximum(depth_centers); length = max(length(depth_centers), 240)))
        d_edges_km = edges_from_centers(depth_query_m ./ 1000.0)
        d_edges_interp_km = edges_from_centers(depth_query_interp_m ./ 1000.0)
        mkpath(export_dir_2d)

        exported = 0
        for idx in 1:nsec
            path = section_paths[][idx]
            xs, ys, sdist = sample_polyline(path, section_samples_along)
            isempty(sdist) && continue

            export_fonts = (; regular = "TeX Gyre Heros Makie", bold = "TeX Gyre Heros Makie")
            axis_title_size = 30
            axis_label_size = 28
            tick_label_size = 24
            tick_size = 14
            tick_width = 2
            colorbar_label_size = 26
            colorbar_tick_label_size = 22

            section_grid = sample_model_section_to_depth_grid(vol.x, vol.y, -vol.z, vol.values, xs, ys, depth_query_m)
            section_grid_interp = sample_model_section_to_depth_grid(vol.x, vol.y, -vol.z, vol.values, xs, ys, depth_query_interp_m)
            s_edges_km = edges_from_centers(sdist ./ 1000.0)

            export_fig = Figure(size = (2600, 1200), figure_padding = (10, 10, 10, 10), fonts = export_fonts)
            colgap!(export_fig.layout, 6)

            path_len_km = sdist[end] / 1000.0
            title_txt = "Section S$(idx) | points=$(length(path)) | length=$(round(path_len_km, digits = 2)) km | max depth=$(round(max_depth_km, digits = 2)) km"

            ax2 = Axis(export_fig[1, 1],
                title = title_txt,
                xlabel = "Distance along section (km)",
                ylabel = "Depth (km)",
                titlefont = :regular,
                xlabelfont = :regular,
                ylabelfont = :regular,
                titlesize = axis_title_size,
                xlabelsize = axis_label_size,
                ylabelsize = axis_label_size,
                xticklabelsize = tick_label_size,
                yticklabelsize = tick_label_size,
                xticksize = tick_size,
                yticksize = tick_size,
                xtickwidth = tick_width,
                ytickwidth = tick_width,
                yreversed = true,
                xautolimitmargin = (0.0f0, 0.0f0),
                yautolimitmargin = (0.0f0, 0.0f0))
            hm = heatmap!(ax2, s_edges_km, d_edges_km, section_grid, colormap = vol.cmap, colorrange = (vol.cmin, vol.cmax), interpolate = false)
            Colorbar(export_fig[1, 2], hm, label = vol.label, labelfont = :regular, labelsize = colorbar_label_size, ticklabelsize = colorbar_tick_label_size, ticksize = tick_size, tickwidth = tick_width)

            filename = "$(model_name_for_export)_$(String(vol.kind))_2DCS_S$(idx).png"
            outpath = joinpath(export_dir_2d, filename)
            save(outpath, export_fig, px_per_unit = export_png_scale)

            export_fig_interp = Figure(size = (2600, 1200), figure_padding = (10, 10, 10, 10), fonts = export_fonts)
            colgap!(export_fig_interp.layout, 6)

            ax2_interp = Axis(export_fig_interp[1, 1],
                title = title_txt * " | interpolated",
                xlabel = "Distance along section (km)",
                ylabel = "Depth (km)",
                titlefont = :regular,
                xlabelfont = :regular,
                ylabelfont = :regular,
                titlesize = axis_title_size,
                xlabelsize = axis_label_size,
                ylabelsize = axis_label_size,
                xticklabelsize = tick_label_size,
                yticklabelsize = tick_label_size,
                xticksize = tick_size,
                yticksize = tick_size,
                xtickwidth = tick_width,
                ytickwidth = tick_width,
                yreversed = true,
                xautolimitmargin = (0.0f0, 0.0f0),
                yautolimitmargin = (0.0f0, 0.0f0))
            hm_interp = heatmap!(ax2_interp, s_edges_km, d_edges_interp_km, section_grid_interp, colormap = vol.cmap, colorrange = (vol.cmin, vol.cmax), interpolate = true)
            Colorbar(export_fig_interp[1, 2], hm_interp, label = vol.label, labelfont = :regular, labelsize = colorbar_label_size, ticklabelsize = colorbar_tick_label_size, ticksize = tick_size, tickwidth = tick_width)

            interp_filename = "$(model_name_for_export)_$(String(vol.kind))_2DCS_S$(idx)_interp.png"
            interp_outpath = joinpath(export_dir_2d, interp_filename)
            save(interp_outpath, export_fig_interp, px_per_unit = export_png_scale)

            txtpath = splitext(outpath)[1] * ".txt"
            open(txtpath, "w") do io
                for p in path
                    x_t = Float64(p[1])
                    y_t = Float64(p[2])
                    if xy_to_latlon !== nothing
                        lon, lat = xy_to_latlon(x_t, y_t)
                        println(io, "$(lat) $(lon)")
                    else
                        println(io, "$(y_t) $(x_t)")
                    end
                end
            end

            println("Exported 2D section: $outpath")
            println("Exported interpolated 2D section: $interp_outpath")
            println("Exported section points: $txtpath")
            exported += 1
        end

        export_status[] = "Exported 2D sections: $(exported)/$(nsec)"
        return exported
    end

    cam3d!(ax.scene, projectiontype = Makie.Perspective)
    draw_static_overlays!(ax.scene)
    redraw_scene!()
    fit_camera!(ax.scene, current_volume().x, current_volume().y, current_volume().z)
    update_volume_controls!()
    update_axis_info!()
    set_active_section!(0)
    update_layout_mode!()

    deregister_interaction!(selector_ax, :rectanglezoom)
    on(events(selector_ax).mousebutton) do event
        if event.button == Mouse.left && event.action == Mouse.press
            pos = mouseposition(selector_ax)
            x_click, y_click = Float64(pos[1]), Float64(pos[2])
            vol = current_volume()
            if x_click < minimum(vol.x) || x_click > maximum(vol.x) || y_click < minimum(vol.y) || y_click > maximum(vol.y)
                return
            end
            pts = copy(pending_points[])
            push!(pts, Point2f(x_click, y_click))
            pending_points[] = pts
        elseif event.button == Mouse.right && event.action == Mouse.press
            ok = add_section_from_polyline!(pending_points[])
            pending_points[] = Point2f[]
            if ok
                redraw_scene!()
                update_axis_info!()
            end
        end
    end

    on(btn_finish_section.clicks) do _
        ok = add_section_from_polyline!(pending_points[])
        pending_points[] = Point2f[]
        if ok
            redraw_scene!()
            update_axis_info!()
        end
    end

    on(btn_clear_points.clicks) do _
        pending_points[] = Point2f[]
    end

    on(depth_slider.value) do v
        update_depth_slice!()
        update_axis_info!()
    end

    on(btn_prev_depth.clicks) do _
        set_close_to!(depth_slider, max(1, depth_slider.value[] - 1))
    end
    on(btn_next_depth.clicks) do _
        set_close_to!(depth_slider, min(length(current_volume().z), depth_slider.value[] + 1))
    end

    function switch_volume!(kind::Symbol)
        if !haskey(volumes, kind)
            export_status[] = "$(uppercasefirst(String(kind))) volume is not available"
            return
        end
        current_kind[] = kind
        set_close_to!(depth_slider, min(depth_slider.value[], length(current_volume().z)))
        btn_toggle_data.label[] = data_toggle_label()
        highlight_active_volume_button!(kind)
        update_volume_controls!()
        redraw_scene!()
        update_axis_info!()
    end

    for (kind, button) in _volume_buttons
        on(button.clicks) do _
            switch_volume!(kind)
        end
    end

    on(btn_toggle_data.clicks) do _
        if !haskey(data_layers, current_kind[])
            export_status[] = "No data file is configured for $(_volume_base_labels[current_kind[]])"
            return
        end
        show_data[] = !show_data[]
        btn_toggle_data.label[] = data_toggle_label()
        redraw_scene!()
    end

    on(btn_toggle_map.clicks) do _
        show_map_slice[] = !show_map_slice[]
        btn_toggle_map.label[] = show_map_slice[] ? "Hide Map Slice" : "Show Map Slice"
        redraw_scene!()
        update_axis_info!()
    end

    on(btn_toggle_seis_curtain.clicks) do _
        if seismic_curtain === nothing
            export_status[] = "No seismic drape available"
            return
        end
        show_seis_model_section[] = !show_seis_model_section[]
        btn_toggle_seis_curtain.label[] = drape_toggle_label(true, show_seis_model_section[])
        redraw_scene!()
        update_axis_info!()
    end

    on(btn_toggle_seis_section.clicks) do _
        if seismic_curtain === nothing
            export_status[] = "No seismic section available"
            return
        end
        show_seis_curtain[] = !show_seis_curtain[]
        btn_toggle_seis_section.label[] = seismic_section_toggle_label(true, show_seis_curtain[])
        redraw_scene!()
        update_axis_info!()
    end

    on(btn_toggle_view_mode.clicks) do _
        show_full_layout[] = !show_full_layout[]
        update_layout_mode!()
    end

    on(btn_prev_sec.clicks) do _
        n = section_count()
        n == 0 && return
        set_active_section!(max(1, active_section[] - 1))
        update_axis_info!()
    end

    on(btn_next_sec.clicks) do _
        n = section_count()
        n == 0 && return
        set_active_section!(min(n, active_section[] + 1))
        update_axis_info!()
    end

    on(btn_undo.clicks) do _
        n = section_count()
        n == 0 && return

        paths = copy(section_paths[])

        pop!(paths)

        section_paths[] = paths

        set_active_section!(length(paths))
        redraw_scene!()
        update_axis_info!()
    end

    on(btn_clear_all.clicks) do _
        section_paths[] = Vector{Vector{Tuple{Float64, Float64}}}()
        pending_points[] = Point2f[]
        set_active_section!(0)
        redraw_scene!()
        update_axis_info!()
    end

    on(btn_reset.clicks) do _
        fit_camera!(ax.scene, current_volume().x, current_volume().y, current_volume().z)
    end

    on(btn_export_3d.clicks) do _
        try
            export_3d_view!()
        catch err
            export_status[] = "3D export failed (see terminal)"
            @warn "3D export failed; viewer remains open" exception=(err, catch_backtrace())
        end
    end

    on(btn_export_2d.clicks) do _
        try
            export_2d_all_sections!()
        catch err
            export_status[] = "2D export failed (see terminal)"
            @warn "2D export failed; viewer remains open" exception=(err, catch_backtrace())
        end
    end

    on(btn_iso_color_mode.clicks) do _
        iso_color_by_depth[] = !iso_color_by_depth[]
        btn_iso_color_mode.label[] = iso_color_by_depth[] ? "Color: Depth" : "Color: Property"
        export_status[] = iso_color_by_depth[] ? "Iso color mode: depth" : "Iso color mode: $(current_volume().name)"
    end

    for (kind, obs) in iso_visibility
        on(obs) do _
            redraw_scene!()
            export_status[] = "$(uppercasefirst(String(kind))) isosurface visibility updated"
        end
    end

    on(btn_apply_iso.clicks) do _
        try
            apply_isosurfaces!()
            redraw_scene!()
        catch err
            export_status[] = "Isosurface update failed (see terminal)"
            @warn "Isosurface update failed" exception=(err, catch_backtrace())
        end
    end

    on(btn_clear_iso.clicks) do _
        clear_isosurface_plots!(current_volume().kind)
        redraw_scene!()
        export_status[] = "$(current_volume().name) isosurface cleared"
    end

    btn_toggle_map.label[] = show_map_slice[] ? "Hide Map Slice" : "Show Map Slice"
    btn_toggle_seis_curtain.label[] = drape_toggle_label(seismic_curtain !== nothing, show_seis_model_section[])
    btn_toggle_seis_section.label[] = seismic_section_toggle_label(seismic_curtain !== nothing, show_seis_curtain[])

    on(btn_export_iso.clicks) do _
        try
            export_isosurfaces_dxf!()
        catch err
            export_status[] = "Isosurface DXF export failed (see terminal)"
            @warn "Isosurface DXF export failed" exception=(err, catch_backtrace())
        end
    end

    if isosurface_defaults.enabled
        try
            apply_isosurfaces!()
        catch err
            @warn "Initial isosurface build failed" exception=(err, catch_backtrace())
        end
    end

    return fig, (
        ax = ax,
        current_kind = current_kind,
        depth_slider = depth_slider,
        active_section = active_section,
        section_count = section_count,
        show_map_slice = show_map_slice,
        show_full_layout = show_full_layout,
        colorrange = (cmin = cmin, cmax = cmax),
        volumes = volumes,
        volume_buttons = _volume_buttons,
        data_layers = data_layers,
        show_data = show_data,
        toggle_data_button = btn_toggle_data
    )
end

# `open_window = false` builds the scene without opening an OpenGL window; used by
# the headless smoke test in scripts/import_smoketest.jl. `show_banner = false` is
# for callers that already printed it, such as the launcher's pre-flight check.
function main(; open_window::Bool = true, show_banner::Bool = true)
    show_banner && TerraScope.print_banner(; data_root = data_root)

    # ── Progress helpers ─────────────────────────────────────────────────
    _total_steps = 9
    _current_step = Ref(0)

    function _step!(label::AbstractString; done::Bool = false)
        _current_step[] += 1
        n = _current_step[]
        filled = round(Int, n / _total_steps * 30)
        bar = "█"^filled * "░"^(30 - filled)
        pct = lpad(string(round(Int, 100 * n / _total_steps)), 3)
        icon = done ? "\e[32m✓\e[0m" : "\e[36m›\e[0m"
        print("  $icon \e[90m[\e[0m$bar\e[90m]\e[0m $pct%%  $label")
        done || print("…")
        println()
        flush(stdout)
    end

    # ── Coordinate frame ─────────────────────────────────────────────────
    # A ModEM mesh is local metres about its own origin, and only becomes georeferenced
    # once its data file supplies that origin. So: MT model plus MT data puts the scene
    # in the project CRS; an MT model on its own is drawn in its own local metres; with
    # no MT model the scene is in the project CRS, which is what every other input is
    # read into anyway.
    _step!("Loading MT model")
    M = isempty(mt_model_file) ? nothing : load_model_modem(mt_model_file)
    d = (M !== nothing && !isempty(mt_data_file)) ? load_data_modem(mt_data_file) : nothing

    _step!("Georeferencing")
    local x_target, y_target, overlay_transform, xy_to_latlon
    georeferenced = M === nothing || d !== nothing
    if M !== nothing && d !== nothing
        x_target, y_target, lat0, lon0, shiftlat, shiftlon, lat_ref, lon_ref, mismatch_dim_consistent,
            station_x, station_y = model_xy_to_target_crs_centers(M, d, target_crs)
        wgs84_to_target = _resolve_wgs84_to_target_xy_transform(target_crs)
        target_to_wgs84 = _resolve_target_xy_to_wgs84_transform(target_crs)
        overlay_transform = (lon, lat) ->
            wgs84_to_target(Float64(lon) + Float64(shiftlon), Float64(lat) + Float64(shiftlat))
        xy_to_latlon = (xv, yv) -> begin
            lon, lat = target_to_wgs84(Float64(xv), Float64(yv))
            return lon - Float64(shiftlon), lat - Float64(shiftlat)
        end
    elseif M !== nothing
        # ModEM keeps north in cx and east in cy; the scene plots east along x.
        x_target = collect(Float64, M.cy)
        y_target = collect(Float64, M.cx)
        overlay_transform = (xv, yv) -> (Float64(xv), Float64(yv))
        xy_to_latlon = nothing
        @info "No MT data file: the model is drawn in its own local coordinates, and georeferenced overlays are left out."
    else
        _validate_target_crs(target_crs)
        wgs84_to_target = _resolve_wgs84_to_target_xy_transform(target_crs)
        target_to_wgs84 = _resolve_target_xy_to_wgs84_transform(target_crs)
        x_target = Float64[]
        y_target = Float64[]
        overlay_transform = (lon, lat) -> wgs84_to_target(Float64(lon), Float64(lat))
        xy_to_latlon = (xv, yv) -> target_to_wgs84(Float64(xv), Float64(yv))
    end

    M_target = M === nothing ? nothing :
        (A = permutedims(M.A, (2, 1, 3)), cx = x_target, cy = y_target, cz = M.cz)

    # ── Model volumes ────────────────────────────────────────────────────
    # With an MT mesh present the other methods are resampled onto its core cells, so
    # the properties share one grid and compare cell for cell. Without one, each file is
    # gridded on axes taken from its own points.
    function load_local_mt_aligned_volume(path::AbstractString)
        voxel = load_density_volume(path)
        ix_core = core_indices(M.cx; tol = pad_tolerance)
        iy_core = core_indices(M.cy; tol = pad_tolerance)
        return (
            A = permutedims(voxel.values, (2, 1, 3)),
            cx = x_target[iy_core],
            cy = y_target[ix_core],
            cz = -voxel.z,
            name = voxel.name,
        )
    end

    function load_project_crs_volume(path::AbstractString)
        voxel = load_density_volume(path)
        return (
            A = permutedims(voxel.values, (2, 1, 3)),
            cx = voxel.y,
            cy = voxel.x,
            cz = -voxel.z,
            name = voxel.name,
        )
    end

    # `longitude latitude elevation value` point files. The reader reprojects them into
    # `target_crs`, working the source CRS out from the coordinates when the file does
    # not state one, and the cloud is then resampled onto the scene's cells.
    function load_point_volume(path::AbstractString, kind::Symbol, units::AbstractString)
        session = TerraScope.ImportSession()
        TerraScope.set_project_crs!(session, target_crs)
        layer = TerraScope.import_layer!(session, path,
            TerraScope.ImportOptions(format = :xyz, kind = kind, units = units))
        points = layer.data::TerraScope.ImportedPoints
        if M_target === nothing
            cx, cy, elevations = TerraScope.axes_from_points(points)
            cz = filter(<=(Float64(max_depth)), sort(-elevations))
        else
            cx = x_target[core_indices(M.cx; tol = pad_tolerance)]
            cy = y_target[core_indices(M.cy; tol = pad_tolerance)]
            cz = M.cz[z_indices_for_max_depth(M.cz, Float64(max_depth))]
        end
        isempty(cz) && error("No cells fall inside the $(max_depth) m depth limit.")
        A, coverage = TerraScope.resample_points_to_axes(points, cx, cy, -cz)
        coverage < 0.02 && @warn "Only $(round(100 * coverage, digits = 1))% of the cells got a point from $(basename(path)); check that it covers the same area as the model."
        return (A = A, cx = cx, cy = cy, cz = cz, name = splitext(basename(path))[1])
    end

    function load_model_volume(path::AbstractString, kind::Symbol, units::AbstractString)
        volume = lowercase(splitext(path)[2]) == ".xyz" ? load_point_volume(path, kind, units) :
            (M_target === nothing ? load_project_crs_volume(path) : load_local_mt_aligned_volume(path))
        # Density is configured and read in kg/m^3 but displayed in g/cc throughout.
        kind === :density || return volume
        return (A = volume.A ./ 1000.0, cx = volume.cx, cy = volume.cy, cz = volume.cz, name = volume.name)
    end

    loaded_volumes = Dict{Symbol, Any}()
    for entry in model_inputs
        entry.kind === :resistivity && continue
        _step!("Loading $(entry.method) model")
        isempty(entry.model) && continue
        if !isfile(entry.model)
            @warn "$(entry.method) model not found; proceeding without it." path = entry.model
            continue
        end
        if !georeferenced
            @warn "$(entry.method) model skipped: the scene is in the MT model's local coordinates, which a georeferenced file cannot be placed in."
            continue
        end
        try
            loaded_volumes[entry.kind] = load_model_volume(entry.model, entry.kind, entry.units)
        catch err
            @warn "Failed to load the $(entry.method) model; proceeding without it." exception = (err, catch_backtrace())
        end
    end

    # ── Measured data ────────────────────────────────────────────────────
    # What "Show Data" draws for each property: the MT site locations, and the survey
    # points behind a gravity or magnetic model. An MT data file georeferences its model
    # as well; the point-file methods carry their own coordinates already.
    data_layers = Dict{Symbol, Any}()
    _step!("Loading measured data")
    if d !== nothing
        data_layers[:resistivity] = (name = "MT sites", x = station_x, y = station_y,
            z = -collect(Float64, d.z), values = nothing, colorrange = (0.0, 1.0))
    end
    for entry in model_inputs
        entry.kind === :resistivity && continue
        isempty(entry.data) && continue
        if !isfile(entry.data)
            @warn "$(entry.method) data not found; proceeding without it." path = entry.data
            continue
        end
        if !georeferenced
            @warn "$(entry.method) data skipped: the scene is in the MT model's local coordinates."
            continue
        end
        try
            session = TerraScope.ImportSession()
            TerraScope.set_project_crs!(session, target_crs)
            layer = TerraScope.import_layer!(session, entry.data,
                TerraScope.ImportOptions(format = :xyz, kind = entry.kind, units = entry.units))
            points = layer.data::TerraScope.ImportedPoints
            data_layers[entry.kind] = (name = "$(entry.method) data", x = points.x, y = points.y,
                z = points.z, values = points.values, colorrange = layer.colorrange)
        catch err
            @warn "Failed to load the $(entry.method) data; proceeding without it." exception = (err, catch_backtrace())
        end
    end

    seismic_curtain = nothing
    resolved_seismic_display_mode = _resolve_seismic_display_mode(seismic_display_mode)
    _step!("Loading seismic section")
    if show_seismic
        seismic_path = seismic_file === nothing ? "" : strip(String(seismic_file))
        if !isempty(seismic_path) && isfile(seismic_path)
            try
                seismic_curtain = load_seismic_curtain_from_segy(seismic_path;
                    trace_xy = seismic_trace_xy,
                    display_mode = resolved_seismic_display_mode,
                    sample_spacing_m = seismic_sample_spacing_m,
                    top_z_m = seismic_top_z_m,
                    max_traces = seismic_max_traces,
                    max_samples = seismic_max_samples,
                    clip_quantile = seismic_clip_quantile)
            catch err
                @warn "Failed to load seismic SEG-Y; proceeding without seismic overlay." exception=(err, catch_backtrace())
            end
        end
    end

    # ── Primary volume ───────────────────────────────────────────────────
    # The scene is laid out around one volume: the MT model when there is one, else the
    # first other method that loaded. With nothing at all the viewer opens on an empty
    # box covering whatever else was configured, so the controls stay consistent.
    primary_kind = :resistivity
    primary_name = "Resistivity"
    primary_logscale = log10_scale
    primary_volume = M_target
    if primary_volume === nothing
        for entry in model_inputs
            volume = pop!(loaded_volumes, entry.kind, nothing)
            volume === nothing && continue
            primary_kind, primary_name, primary_logscale, primary_volume =
                entry.kind, volume.name, false, volume
            break
        end
    end
    primary_available = primary_volume !== nothing
    if !primary_available
        xlim, ylim = _blank_scene_extent(seismic_curtain, shapefile_layers,
            overlay_transform, overlay_auto_reproject_to_wgs84)
        primary_name = "No model"
        primary_logscale = false
        primary_volume = (
            A = fill(NaN, 4, 4, 4),
            cx = collect(range(xlim[1], xlim[2]; length = 4)),
            cy = collect(range(ylim[1], ylim[2]; length = 4)),
            cz = collect(range(10.0, min(Float64(max_depth), 10_000.0); length = 4)),
        )
    end
    primary_range = !primary_available ? nothing :
        (primary_kind === :resistivity ? resistivity_range : getfield(display_ranges, primary_kind))

    _step!("Building 3D scene")
    fig, parts = modem_3d_viewer_crosssections(primary_volume;
        primary_kind = primary_kind,
        primary_name = primary_name,
        primary_available = primary_available,
        density_model = get(loaded_volumes, :density, nothing),
        susceptibility_model = get(loaded_volumes, :susceptibility, nothing),
        log10scale = primary_logscale,
        cmap = colormap,
        withPadding = show_padding,
        max_depth = max_depth,
        pad_tol = pad_tolerance,
        resistivity_range = primary_range,
        volume_display_ranges = (
            density = display_ranges.density,
            susceptibility = display_ranges.susceptibility,
        ),
        overlays = georeferenced ? shapefile_layers : empty(shapefile_layers),
        data_layers = data_layers,
        overlay_transform = overlay_transform,
        north_axis = :y,
        xy_to_latlon = xy_to_latlon,
        selector_show_latlon_ticks = selector_show_latlon_ticks,
        seismic_curtain = seismic_curtain,
        seismic_display_mode = resolved_seismic_display_mode,
        show_seismic_model_section_default = show_seismic_model_section,
        scene_only_default = show_only_3d_scene
    )

    if !open_window
        _step!("Scene built (window suppressed)"; done = true)
        return fig, parts
    end

    _step!("Opening viewer")
    screen = display_figure(fig; fullscreen = open_fullscreen)
    _step!("Viewer ready"; done = true)
    println("\n  \e[32m✓\e[0m TerraScope is ready. Close the window to exit.\n")
    flush(stdout)
    print("\e[5 q")   # switch to blinking bar cursor
    wait(screen)
    print("\e[0 q")   # restore default cursor

    return fig, parts
end

if abspath(PROGRAM_FILE) == @__FILE__
    fig, parts = main()
end
