using Pkg

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(PROJECT_ROOT)

using TerraScope

function _gaussian3(x::Real, y::Real, z::Real, x0::Real, y0::Real, z0::Real, sx::Real, sy::Real, sz::Real)
    return exp(-0.5 * (((x - x0) / sx)^2 + ((y - y0) / sy)^2 + ((z - z0) / sz)^2))
end

function generate_synthetic_density_model(model; pad_tol::Real = 0.2, max_depth::Union{Nothing, Real} = nothing)
    ix = TerraScope.core_indices(model.cx; tol = pad_tol)
    iy = TerraScope.core_indices(model.cy; tol = pad_tol)
    kz = isnothing(max_depth) ? (1:length(model.cz)) : TerraScope.z_indices_for_max_depth(model.cz, float(max_depth))
    x = model.cx[ix]
    y = model.cy[iy]
    z = -model.cz[kz]
    nx, ny, nz = length(x), length(y), length(z)

    values = fill(2695.0, nx, ny, nz)
    xmid = 0.5 * (minimum(x) + maximum(x))
    ymid = 0.5 * (minimum(y) + maximum(y))
    xspan = max(maximum(x) - minimum(x), 1.0)
    yspan = max(maximum(y) - minimum(y), 1.0)
    zmax = max(maximum(-z), 1.0)

    for i in 1:nx, j in 1:ny, k in 1:nz
        depth = -z[k]
        xn = (x[i] - xmid) / xspan
        yn = (y[j] - ymid) / yspan
        zn = depth / zmax

        shield_gradient = 55.0 * (0.45 - yn) + 35.0 * zn
        greenstone_belt = 220.0 * _gaussian3(xn, yn, zn, 0.18, -0.12, 0.24, 0.11, 0.08, 0.10)
        lapland_belt = 145.0 * _gaussian3(xn, yn, zn, -0.16, 0.22, 0.30, 0.16, 0.09, 0.12)
        rapakivi_granite = -165.0 * _gaussian3(xn, yn, zn, 0.24, 0.10, 0.18, 0.13, 0.11, 0.09)
        sedimentary_cover = -85.0 * _gaussian3(xn, yn, zn, -0.08, -0.22, 0.10, 0.24, 0.12, 0.07)
        crustal_root = 135.0 * _gaussian3(xn, yn, zn, -0.04, 0.02, 0.58, 0.28, 0.20, 0.16)
        mafic_intrusion = 175.0 * _gaussian3(xn, yn, zn, 0.04, 0.04, 0.42, 0.08, 0.07, 0.10)
        basin_rolloff = -40.0 * max(zn - 0.62, 0.0)

        values[i, j, k] += shield_gradient + greenstone_belt + lapland_belt + rapakivi_granite + sedimentary_cover + crustal_root + mafic_intrusion + basin_rolloff
    end

    values .= clamp.(values, 2480.0, 3275.0)
    return TerraScope.ScalarVolume("Synthetic Density", :density, values, x, y, z, "kg/m^3", Dict{Symbol, Any}(:source => :synthetic, :value_scale => :linear))
end

function generate_synthetic_susceptibility_model(model; pad_tol::Real = 0.2, max_depth::Union{Nothing, Real} = nothing)
    ix = TerraScope.core_indices(model.cx; tol = pad_tol)
    iy = TerraScope.core_indices(model.cy; tol = pad_tol)
    kz = isnothing(max_depth) ? (1:length(model.cz)) : TerraScope.z_indices_for_max_depth(model.cz, float(max_depth))
    x = model.cx[ix]
    y = model.cy[iy]
    z = -model.cz[kz]
    nx, ny, nz = length(x), length(y), length(z)
    values = fill(0.0020, nx, ny, nz)

    xmid = 0.5 * (minimum(x) + maximum(x))
    ymid = 0.5 * (minimum(y) + maximum(y))
    xspan = max(maximum(x) - minimum(x), 1.0)
    yspan = max(maximum(y) - minimum(y), 1.0)
    zmax = max(maximum(-z), 1.0)

    for i in 1:nx, j in 1:ny, k in 1:nz
        depth = -z[k]
        xn = (x[i] - xmid) / xspan
        yn = (y[j] - ymid) / yspan
        zn = depth / zmax

        greenstone_high = 0.060 * _gaussian3(xn, yn, zn, 0.16, -0.10, 0.22, 0.10, 0.07, 0.08)
        lapland_arc = 0.036 * _gaussian3(xn, yn, zn, -0.18, 0.20, 0.28, 0.18, 0.08, 0.10)
        mafic_root = 0.028 * _gaussian3(xn, yn, zn, -0.02, 0.02, 0.52, 0.24, 0.16, 0.14)
        rapakivi_low = -0.0065 * _gaussian3(xn, yn, zn, 0.26, 0.10, 0.18, 0.14, 0.11, 0.09)
        basin_low = -0.0032 * _gaussian3(xn, yn, zn, -0.10, -0.24, 0.12, 0.22, 0.12, 0.07)
        regional_decay = -0.0012 * zn + 0.0020 * max(0.15 - yn, 0.0)

        values[i, j, k] += greenstone_high + lapland_arc + mafic_root + rapakivi_low + basin_low + regional_decay
    end

    values .= clamp.(values, 1e-4, 0.095)
    return TerraScope.ScalarVolume("Synthetic Susceptibility", :susceptibility, values, x, y, z, "SI", Dict{Symbol, Any}(:source => :synthetic, :value_scale => :linear))
end

function main()
    demo_root = joinpath(PROJECT_ROOT, "Data", "demo")
    model_path = joinpath(demo_root, "I_NLCG_140.rho")
    model = TerraScope.load_model_modem(model_path)

    density = generate_synthetic_density_model(model; max_depth = 50_000.0)
    susceptibility = generate_synthetic_susceptibility_model(model; max_depth = 50_000.0)

    TerraScope.save_density_volume(joinpath(demo_root, "Density3D.vox"), density)
    TerraScope.save_density_volume(joinpath(demo_root, "Susceptibility3D.vox"), susceptibility)

    println("Wrote synthetic density and susceptibility voxel files to:")
    println("  $(demo_root)")
end

main()