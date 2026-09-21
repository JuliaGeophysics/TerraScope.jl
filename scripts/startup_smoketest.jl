# Headless check that every launcher configuration builds a scene against the bundled
# Finland demo data. Each case runs in its own process, because TerraScope3D.jl reads
# TERRASCOPE_LAUNCH_CONFIG once at include time.
#
#   julia --project=. scripts/startup_smoketest.jl            # run every case
#   julia --project=. scripts/startup_smoketest.jl full       # run one case
using Pkg
Pkg.activate(normpath(joinpath(@__DIR__, "..")))

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEMO = joinpath(ROOT, "Data", "demo")
const VIEWER = joinpath(ROOT, "examples", "TerraScope3D.jl")
const BLANK = (MT_model = "", MT_data = "", gravity_model = "", gravity_data = "",
    magnetic_model = "", magnetic_data = "", seismic_data = "")

demo(name...) = joinpath(DEMO, name...)
const SHAPE = [(path = demo("gis", "Tnew", "Tnew.shp"), color = :black, width = 1.5, alpha = 1.0)]

# name => (inputs, shapefiles, what the case is checking)
const CASES = Dict(
    "full" => (merge(BLANK, (MT_model = demo("I_NLCG_140.rho"), MT_data = demo("I_NLCG_140.dat"),
            gravity_model = demo("density.xyz"), gravity_data = demo("gravity.xyz"),
            magnetic_model = demo("susceptibility.xyz"), magnetic_data = demo("magnetic.xyz"),
            seismic_data = demo("fire_updated.sgy"))), SHAPE,
        "every input configured"),
    "blank" => (BLANK, SHAPE, "no model at all: an empty scene over the shapefile"),
    "mt_local" => (merge(BLANK, (MT_model = demo("I_NLCG_140.rho"),)), SHAPE,
        "MT model with no data: the model in its own local coordinates"),
    "gravity_only" => (merge(BLANK, (gravity_model = demo("density.xyz"),
            gravity_data = demo("gravity.xyz"))), SHAPE,
        "no MT model: gravity gridded on its own coordinates"),
)

function run_case(name::AbstractString)
    inputs, shapefiles, description = CASES[name]
    println("\n══ $name — $description")
    @eval Main begin
        using TerraScope
        const TERRASCOPE_LAUNCH_CONFIG = (inputs = $inputs, shapefiles = $shapefiles,
            view = (show_only_3d_scene = true,))
        include($VIEWER)
        fig, parts = main(; open_window = false, show_banner = false)
        properties = sort(String.(collect(keys(parts.volumes))))
        data = sort(String.(collect(keys(parts.data_layers))))
        println("  volumes: ", join(properties, ", "), "  |  data: ",
            isempty(data) ? "none" : join(data, ", "), "  |  active: ", parts.current_kind[])
        for kind in keys(parts.data_layers)         # exercise the Show Data path
            parts.volume_buttons[kind].clicks[] += 1
            parts.toggle_data_button.clicks[] += 1
            parts.show_data[] || error("Show Data did not turn on for $kind")
            parts.toggle_data_button.clicks[] += 1
        end
    end
    return nothing
end

if isempty(ARGS)
    isdir(DEMO) || error("Demo data not found at $DEMO")
    failures = String[]
    for name in ["full", "blank", "mt_local", "gravity_only"]
        cmd = `$(Base.julia_cmd()) --project=$ROOT $(@__FILE__) $name`
        success(pipeline(cmd; stdout = stdout, stderr = stderr)) || push!(failures, name)
    end
    println()
    isempty(failures) || error("Startup smoke test failures: " * join(failures, ", "))
    println("Startup smoke test passed.")
else
    run_case(only(ARGS))
    println("  ✓ scene built")
end
