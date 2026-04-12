using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

demo_root = joinpath(dirname(@__DIR__), "Data", "demo")                     # Root folder for the bundled demo assets; point elsewhere to launch a different project.

const TERRASCOPE_LAUNCH_CONFIG = (
	paths = (                                                               # File inputs; replace these with your own project files for a different area.
		data_root = demo_root,                                               # Convenience root used to keep the file paths below readable.
		model_file = joinpath(demo_root, "I_NLCG_140.rho"),                 # Main ModEM/WS-style resistivity model.
		data_file = joinpath(demo_root, "I_NLCG_140.dat"),                  # ModEM data file used for georeferencing and alignment.
		shapefile_path = joinpath(demo_root, "gis", "Tnew", "Tnew.shp"), 	# Optional GIS linework draped on top of the model.
		density_file = joinpath(demo_root, "Density3D.vox"),                # Optional density voxel volume.
		susceptibility_file = joinpath(demo_root, "Susceptibility3D.vox"),  # Optional susceptibility voxel volume.
		gravity_file = joinpath(demo_root, "synthetic_gravity.vox"),        # Optional gravity voxel volume.
		magnetic_file = joinpath(demo_root, "synthetic_magnetic.vox"),      # Optional magnetic voxel volume.
		seismic_file = joinpath(demo_root, "fire_updated.sgy"),             # Optional SEG-Y line used for seismic section and model drape.
	),
	model = (                                                               # Controls for the 3D resistivity/voxel rendering and manual sections.
		log10_scale = true,                                                  # `true` shows resistivity as log10(rho); usually preferred for MT models.
		colormap = :Spectral,                                                # Makie colormap used for the active volume.
		max_depth_m = 50000.0,                                               # Viewer depth cutoff in meters; deeper cells are not shown/exported.
		show_padding = false,                                                # `false` hides padding cells and shows only the core model.
		pad_tolerance = 0.2,                                                 # Tolerance used to detect which edge cells are padding.
		section_samples_along = 360,                                         # Along-section samples for manual and seismic-following sections; higher is smoother but slower.
		display_ranges = (                                                   # Optional fixed display ranges; use `nothing` to auto-estimate.
			resistivity = (1.0, 4.0),                                         # For `log10_scale = true`, these are log10(ohm.m) values.
			density = nothing,                                                # Auto-estimate density color range.
			susceptibility = nothing,                                         # Auto-estimate susceptibility color range.
			gravity = nothing,                                                # Auto-estimate gravity color range.
			magnetic = nothing,                                               # Auto-estimate magnetic color range.
		),
	),
	view = (                                                                # Startup layout and camera behaviour.
		open_fullscreen = false,                                              # Open the Makie window in fullscreen on launch.
		show_only_3d_scene = true,                                          # `true` starts in 3D-only mode; `false` starts with controls and selector panel.
		show_outer_ticks_axis = true,                                        # Draw custom XYZ tick annotations around the 3D scene.
		export_png_scale = 4,                                                # Export resolution multiplier for PNG outputs.
		default_view_direction = (-0.15, -1.05, 0.72),                       # Default camera direction for the initial 3D view.
		default_view_scale = 1.12,                                           # Default camera zoom/scale at startup.
	),
	coordinate = (                                                          # Coordinate-system controls for the 3D scene and bottom selector map.
		target_crs = "EPSG:3067",                                           # Target projected CRS used for plotting.
		selector_show_latlon_ticks = false,                                 # `true` uses lat/lon labels below; `false` keeps Easting/Northing labels.
	),
	seismic = (                                                            # SEG-Y loading and rendering options.
		show = true,                                                        # Master on/off switch for loading any seismic product at startup.
		display_mode = :envelope,                                           # `:original` uses signed amplitudes; `:envelope` uses the trace envelope.
		trace_xy = :source,                                                 # Which SEG-Y coordinates to use for map location; `:source` is common.
		max_traces = 2320,                                                  # Downsampling cap for traces to keep large SEG-Y files interactive.
		max_samples = 2000,                                                 # Downsampling cap for samples to keep large SEG-Y files interactive.
		sample_spacing_m = 12.5,                                            # Approximate distance between resampled seismic traces in meters.
		clip_quantile = 0.995,                                              # Clips very large amplitudes for a cleaner seismic image.
		show_model_section = false,                                          # Startup state for the model draped along the seismic line.
	),
	overlay = (                                                            # GIS overlay styling and corner annotations.
		show_north_arrow = true,                                            # Draw compass arrow in the 3D scene.
		show_scale_bar = true,                                              # Draw scale bar in the 3D scene.
		line_color = :black,                                                # Shapefile/polyline overlay color.
		line_width = 1.5,                                                   # Shapefile/polyline overlay line width.
	),
	isosurface = (                                                         # Optional iso-volume generation settings used by the UI.
		enabled = false,                                                    # Build an isosurface immediately on launch.
		alpha = 0.72,                                                       # Initial iso opacity used by the UI controls.
		stride = 1,                                                         # Subsampling step for iso construction; higher is faster but coarser.
		color_by_depth = false,                                             # `true` colors the iso by depth instead of the active property values.
	),
)

include(joinpath(@__DIR__, "TerraScope3D.jl"))                           	# Load the main TerraScope viewer implementation.

main()