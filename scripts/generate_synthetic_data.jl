using Pkg

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(PROJECT_ROOT)

using Printf
using Proj
using TerraScope

const DEMO_CRS = "EPSG:3067"              # ETRS89 / TM35FIN, the demo project CRS.
const BACKGROUND_DENSITY = 2695.0         # kg/m^3, the reference the anomalies sit on.
const EARTH_FIELD_NT = 50_000.0           # Ambient field strength used to scale the TMI response.

function _gaussian3(x::Real, y::Real, z::Real, x0::Real, y0::Real, z0::Real, sx::Real, sy::Real, sz::Real)
    return exp(-0.5 * (((x - x0) / sx)^2 + ((y - y0) / sy)^2 + ((z - z0) / sz)^2))
end

# The field definitions live here once. Every product below evaluates them on
# normalised coordinates, so the models and the surveys stay consistent with each other.
function synthetic_density(xn::Real, yn::Real, zn::Real)
    shield_gradient = 55.0 * (0.45 - yn) + 35.0 * zn
    greenstone_belt = 220.0 * _gaussian3(xn, yn, zn, 0.18, -0.12, 0.24, 0.11, 0.08, 0.10)
    lapland_belt = 145.0 * _gaussian3(xn, yn, zn, -0.16, 0.22, 0.30, 0.16, 0.09, 0.12)
    rapakivi_granite = -165.0 * _gaussian3(xn, yn, zn, 0.24, 0.10, 0.18, 0.13, 0.11, 0.09)
    sedimentary_cover = -85.0 * _gaussian3(xn, yn, zn, -0.08, -0.22, 0.10, 0.24, 0.12, 0.07)
    crustal_root = 135.0 * _gaussian3(xn, yn, zn, -0.04, 0.02, 0.58, 0.28, 0.20, 0.16)
    mafic_intrusion = 175.0 * _gaussian3(xn, yn, zn, 0.04, 0.04, 0.42, 0.08, 0.07, 0.10)
    basin_rolloff = -40.0 * max(zn - 0.62, 0.0)
    value = BACKGROUND_DENSITY + shield_gradient + greenstone_belt + lapland_belt +
        rapakivi_granite + sedimentary_cover + crustal_root + mafic_intrusion + basin_rolloff
    return clamp(value, 2480.0, 3275.0)
end

function synthetic_susceptibility(xn::Real, yn::Real, zn::Real)
    greenstone_high = 0.060 * _gaussian3(xn, yn, zn, 0.16, -0.10, 0.22, 0.10, 0.07, 0.08)
    lapland_arc = 0.036 * _gaussian3(xn, yn, zn, -0.18, 0.20, 0.28, 0.18, 0.08, 0.10)
    mafic_root = 0.028 * _gaussian3(xn, yn, zn, -0.02, 0.02, 0.52, 0.24, 0.16, 0.14)
    rapakivi_low = -0.0065 * _gaussian3(xn, yn, zn, 0.26, 0.10, 0.18, 0.14, 0.11, 0.09)
    basin_low = -0.0032 * _gaussian3(xn, yn, zn, -0.10, -0.24, 0.12, 0.22, 0.12, 0.07)
    regional_decay = -0.0012 * zn + 0.0020 * max(0.15 - yn, 0.0)
    value = 0.0020 + greenstone_high + lapland_arc + mafic_root + rapakivi_low + basin_low + regional_decay
    return clamp(value, 1e-4, 0.095)
end

function _normalisers(x, y, z)
    xmid = 0.5 * (minimum(x) + maximum(x))
    ymid = 0.5 * (minimum(y) + maximum(y))
    xspan = max(maximum(x) - minimum(x), 1.0)
    yspan = max(maximum(y) - minimum(y), 1.0)
    zmax = max(maximum(-z), 1.0)
    return xmid, ymid, xspan, yspan, zmax
end

# Georeference the demo ModEM mesh through the package import path, so the synthetic
# products land exactly where the resistivity model does.
function georeferenced_demo_grid(model_path, data_path; max_depth::Real = 50_000.0)
    session = TerraScope.ImportSession()
    TerraScope.set_project_crs!(session, DEMO_CRS)
    layer = TerraScope.import_layer!(session, model_path,
        TerraScope.ImportOptions(format = :modem, data_path = data_path,
            trim_padding = true, max_depth_m = Float64(max_depth)))
    return layer.data::TerraScope.ImportedGrid
end

_cell_thickness(z) = abs.(diff(TerraScope.edges_from_centers(collect(z))))

_write_record(io, fmt, lon, lat, elevation, value) =
    Printf.format(io, fmt, lon, lat, elevation, value)

_record_format(value_format) = Printf.Format("%.6f %.6f %.1f " * value_format * "\n")

# A 3D point model, written as `longitude latitude elevation value` records.
function write_xyz_model(path, grid, to_wgs84, field; stride::Int = 2, header::AbstractString, value_format = "%.2f")
    nx, ny = size(grid.X)
    ix, iy, iz = 1:stride:nx, 1:stride:ny, 1:stride:length(grid.z)
    xmid, ymid, xspan, yspan, zmax = _normalisers(grid.X[ix, iy], grid.Y[ix, iy], grid.z[iz])
    fmt = _record_format(value_format)
    rows = 0
    open(path, "w") do io
        println(io, "# ", header)
        println(io, "# longitude(deg) latitude(deg) elevation(m) value")
        for k in iz, j in iy, i in ix
            lon, lat = to_wgs84(grid.X[i, j], grid.Y[i, j])
            value = field((grid.X[i, j] - xmid) / xspan, (grid.Y[i, j] - ymid) / yspan, -grid.z[k] / zmax)
            _write_record(io, fmt, lon, lat, grid.z[k], value)
            rows += 1
        end
    end
    return rows
end

# A surface dataset, written as `longitude latitude elevation value` records. The value
# is a depth-weighted column integral of the matching 3D model: enough to look like a
# survey flown over the same bodies, not a rigorous forward calculation.
function write_xyz_survey(path, grid, to_wgs84, field, response; survey_z::Real, header::AbstractString, value_format = "%.3f")
    nx, ny = size(grid.X)
    xmid, ymid, xspan, yspan, zmax = _normalisers(grid.X, grid.Y, grid.z)
    thickness = _cell_thickness(grid.z)
    fmt = _record_format(value_format)
    rows = 0
    open(path, "w") do io
        println(io, "# ", header)
        println(io, "# longitude(deg) latitude(deg) elevation(m) value")
        for j in 1:ny, i in 1:nx
            lon, lat = to_wgs84(grid.X[i, j], grid.Y[i, j])
            xn = (grid.X[i, j] - xmid) / xspan
            yn = (grid.Y[i, j] - ymid) / yspan
            total = 0.0
            for k in eachindex(grid.z)
                depth = -grid.z[k]
                weight = 1.0 / (1.0 + depth / 5000.0)^2          # Approximate inverse-square falloff.
                total += field(xn, yn, depth / zmax) * thickness[k] * weight
            end
            _write_record(io, fmt, lon, lat, Float64(survey_z), response(total))
            rows += 1
        end
    end
    return rows
end

function main()
    demo_root = joinpath(PROJECT_ROOT, "Data", "demo")
    model_path = joinpath(demo_root, "I_NLCG_140.rho")
    data_path = joinpath(demo_root, "I_NLCG_140.dat")

    # Georeferenced WGS84 lon/lat products. The files state no CRS, so the importer
    # detects degrees from the coordinates and converts them into the project CRS.
    grid = georeferenced_demo_grid(model_path, data_path)
    to_wgs84 = Proj.Transformation(DEMO_CRS, "EPSG:4326"; always_xy = true)
    println("Wrote WGS84 lon/lat point files (load them with the Import button):")

    n = write_xyz_model(joinpath(demo_root, "density.xyz"), grid, to_wgs84, synthetic_density;
        header = "Synthetic density model. WGS84 lon/lat, elevation in metres, density in kg/m^3.")
    println("  density.xyz         density model, kg/m^3     $n records")

    n = write_xyz_model(joinpath(demo_root, "susceptibility.xyz"), grid, to_wgs84, synthetic_susceptibility;
        header = "Synthetic magnetic susceptibility model. WGS84 lon/lat, elevation in metres, SI units.",
        value_format = "%.6f")
    println("  susceptibility.xyz  susceptibility model, SI  $n records")

    # 2 pi G = 4.1928e-10 m^3 kg^-1 s^-2; the 1e5 converts m/s^2 to mGal.
    gravity_response(column) = 4.1928e-5 * column
    n = write_xyz_survey(joinpath(demo_root, "gravity.xyz"), grid, to_wgs84,
        (xn, yn, zn) -> synthetic_density(xn, yn, zn) - BACKGROUND_DENSITY, gravity_response;
        survey_z = 0.0,
        header = "Synthetic Bouguer-style gravity anomaly. WGS84 lon/lat, ground level, mGal.")
    println("  gravity.xyz         gravity anomaly, mGal     $n records")

    magnetic_response(column) = EARTH_FIELD_NT * column / 10_000.0
    n = write_xyz_survey(joinpath(demo_root, "magnetic.xyz"), grid, to_wgs84,
        synthetic_susceptibility, magnetic_response;
        survey_z = 100.0, value_format = "%.2f",
        header = "Synthetic total magnetic intensity anomaly. WGS84 lon/lat, 100 m drape, nT.")
    println("  magnetic.xyz        TMI anomaly, nT          $n records")

    println("\nAll files written to $(demo_root)")
end

main()
