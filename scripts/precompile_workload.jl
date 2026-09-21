using Pkg

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(PROJECT_ROOT)

using TerraScope

const DEMO_ROOT = joinpath(PROJECT_ROOT, "Data", "demo")

bundle = TerraScope.load_dataset_bundle(DEMO_ROOT; with_padding = false, max_depth = 50_000.0)
volume = bundle.resistivity

if volume !== nothing
    x1, x2 = extrema(volume.x)
    y1, y2 = extrema(volume.y)
    TerraScope.build_section_surface_polyline(
        volume.x,
        volume.y,
        volume.z,
        volume.values,
        [(x1, y1), (x2, y2)];
        nsamp = 120,
    )
end

if !isempty(bundle.shapefiles)
    TerraScope.shapefile_segments(
        first(bundle.shapefiles);
        auto_reproject_to_wgs84 = false,
        xlim = extrema(volume.x),
        ylim = extrema(volume.y),
    )
end

if !isempty(bundle.segy_files)
    TerraScope.load_seismic_curtain_from_segy(
        first(bundle.segy_files);
        trace_xy = :source,
        display_mode = :envelope,
        sample_spacing_m = 12.5,
        max_traces = 400,
        max_samples = 400,
        clip_quantile = 0.995,
    )
end

println("TerraScope precompile workload completed.")