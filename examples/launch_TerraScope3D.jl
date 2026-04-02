using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

demo_root = joinpath(dirname(@__DIR__), "Data", "demo")

const TERRASCOPE_LAUNCH_CONFIG = (
	paths = (
		data_root = demo_root,
		model_file = joinpath(demo_root, "I_NLCG_140.rho"),
		data_file = joinpath(demo_root, "I_NLCG_140.dat"),
		shapefile_path = joinpath(demo_root, "gis", "Tnew", "Tnew.shp"),
		density_file = joinpath(demo_root, "Density3D.vox"),
		susceptibility_file = joinpath(demo_root, "Susceptibility3D.vox"),
		gravity_file = joinpath(demo_root, "synthetic_gravity.vox"),
		magnetic_file = joinpath(demo_root, "synthetic_magnetic.vox"),
		seismic_file = joinpath(demo_root, "fire_updated.sgy"),
	),
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
			gravity = nothing,
			magnetic = nothing,
		),
	),
	view = (
		open_fullscreen = true,
		show_only_3d_scene = false,
		show_outer_ticks_axis = true,
		export_png_scale = 4,
		default_view_direction = (-1.05, -0.80, 0.72),
		default_view_scale = 1.12,
	),
	coordinate = (
		target_crs = "EPSG:3067",
		selector_show_latlon_ticks = false,
	),
	seismic = (
		show = true,
		display_mode = :original,
		trace_xy = :source,
		max_traces = 1400,
		max_samples = 1200,
		sample_spacing_m = 12.5,
		clip_quantile = 0.995,
		show_model_section = true,
	),
	overlay = (
		show_north_arrow = true,
		show_scale_bar = true,
		line_color = :black,
		line_width = 1.5,
	),
	isosurface = (
		enabled = false,
		alpha = 0.72,
		stride = 1,
		color_by_depth = false,
	),
)

include(joinpath(@__DIR__, "TerraScope3D.jl"))

main()