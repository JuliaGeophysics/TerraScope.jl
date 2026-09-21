# ══════════════════════════════════════════════════════════════════════════════
#  TerraScope — launcher.  This is the only file you edit.
#
#  1  INPUTS      the files to load, by method.  Absolute paths.  "" = not used.
#  2  SHAPEFILES  linework, each with its own colour, width and transparency.
#  3  SETTINGS    display, view, CRS, seismic, overlay, isosurface.
#
#  Every input is optional:
#    · nothing configured          → an empty 3D scene
#    · MT_model only               → the model in its own local coordinates
#    · MT_model + MT_data          → georeferenced into the CRS in section 3
#    · gravity/magnetic models     → resampled onto the MT cells when there is an MT
#                                    model, otherwise gridded on their own coordinates
#    · gravity/magnetic data       → drawn over the model at its own elevation
#
#  Run:  julia --project=. examples/launch_TerraScope3D.jl   (or Launch-TerraScope.cmd)
#  Anything left out of section 3 keeps its default from examples/TerraScope3D.jl.
# ══════════════════════════════════════════════════════════════════════════════

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

println("TerraScope launcher started.")
println("Preparing packages and viewer code. Startup progress will continue below...")
flush(stdout)

const TERRASCOPE_LAUNCH_CONFIG = (

	# ── 1. INPUTS ────────────────────────────────────────────────────────────────
	# `_model` is a 3D volume, `_data` is the measured dataset for the same method.
	# MT models read ModEM/WS `.rho`; the others read `.xyz` point files
	# (`longitude latitude elevation value`, or easting/northing in a projected CRS)
	# and TerraScope `.vox` volumes.
	inputs = (
		#MT_model       = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\I_NLCG_140.rho",
		#MT_data        = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\I_NLCG_140.dat",
		gravity_model  = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\density.xyz",
		gravity_data   = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\gravity.xyz",
		magnetic_model = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\susceptibility.xyz",
		magnetic_data  = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\magnetic.xyz",
		seismic_data   = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\fire_updated.sgy",
	),

	# ── 2. SHAPEFILES ────────────────────────────────────────────────────────────
	# One line per file: path, then how it is drawn. Add as many as you like.
	shapefiles = [
		(path = raw"D:\GitHub\JuliaGeophysics\TerraScope.jl\Data\demo\gis\Tnew\Tnew.shp", color = :black, width = 1.5, alpha = 1.0),
	],

	# ── 3. SETTINGS ──────────────────────────────────────────────────────────────
	model = (                                                # Volume rendering and sections.
		log10_scale = true, colormap = :Spectral,            # log10(rho) is the usual MT choice.
		max_depth_m = 50000.0,                               # Depth cut-off; deeper cells are dropped.
		show_padding = false, pad_tolerance = 0.2,           # Hide ModEM padding cells, and how they are detected.
		section_samples_along = 360,                         # Samples along a section; higher is smoother, slower.
		display_ranges = (resistivity = (1.0, 4.0), density = nothing, susceptibility = nothing),
	),                                                       # `nothing` auto-estimates; resistivity is log10(ohm.m) here.

	view = (                                                 # Window layout and startup camera.
		open_fullscreen = false, show_only_3d_scene = true,  # Start 3D-only; `false` also shows the control and selector panels.
		show_outer_ticks_axis = true, export_png_scale = 4,  # XYZ tick annotations, and PNG export resolution multiplier.
		default_view_direction = (-0.15, -1.05, 0.72), default_view_scale = 1.12,   # Looks north on open.
	),

	coordinate = (                                           # Must be projected and metric — never EPSG:4326.
		target_crs = "EPSG:3067", selector_show_latlon_ticks = true,
	),

	seismic = (                                              # SEG-Y curtain and model drape.
		show = true, display_mode = :envelope,               # `:original` for signed amplitudes.
		trace_xy = :source,                                  # Which header coordinates locate the traces.
		max_traces = 1400, max_samples = 1200,               # Caps that keep large files interactive.
		sample_spacing_m = 12.5, clip_quantile = 0.995,      # Trace resampling distance, and amplitude clipping.
		show_model_section = false,                          # Start with the model draped along the line.
	),

	overlay = (                                              # Annotations and survey styling.
		show_north_arrow = true, show_scale_bar = true,
		line_color = :black, line_width = 1.5,               # Fallback for a shapefile entry that omits them.
		survey_colormap = :viridis, survey_markersize = 5,   # How `_data` point files are drawn.
	),

	isosurface = (                                           # Starting values for the iso controls.
		enabled = false, alpha = 0.72, stride = 1, color_by_depth = false,
	),
)

# ── Pre-flight ────────────────────────────────────────────────────────────────
# Report what was found before the slow work starts, so a wrong path shows up now
# instead of as a silently missing layer ten steps later.

using TerraScope

let inputs = TERRASCOPE_LAUNCH_CONFIG.inputs, shapefiles = TERRASCOPE_LAUNCH_CONFIG.shapefiles
	entries = vcat([(String(name), getfield(inputs, name)) for name in keys(inputs)],
		[("shapefile", entry.path) for entry in shapefiles])
	configured = [path for (_, path) in entries if !isempty(path)]

	TerraScope.print_banner(; data_root = isempty(configured) ? "" : dirname(first(configured)))
	for (name, path) in entries
		label = rpad(replace(name, '_' => ' '), 16)
		if isempty(path)
			println("  \e[90m·  $(label)not used\e[0m")
		elseif isfile(path)
			println("  \e[32m✓\e[0m  \e[90m$(label)$(basename(path))\e[0m")
		else
			println("  \e[31m✗  $(label)not found: $(path)\e[0m")
		end
	end
	isempty(configured) && println("  \e[90m·  nothing configured — TerraScope will open an empty 3D scene\e[0m")
	println()
	flush(stdout)
end

include(joinpath(@__DIR__, "TerraScope3D.jl"))                              # Load the main TerraScope viewer.

main(; show_banner = false)                                                 # The banner was already printed by the pre-flight check.
