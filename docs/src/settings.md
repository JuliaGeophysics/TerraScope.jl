# Launcher settings

Section 3 of `examples/launch_TerraScope3D.jl` holds the startup settings. Every group and every key
is optional; anything left out keeps its default from `examples/TerraScope3D.jl`.

```julia
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

coordinate = (                                           # Must be projected and metric, never EPSG:4326.
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
```

Shapefiles are listed in section 2, one entry per file:

```julia
shapefiles = [
    (path = raw"C:\data\gis\faults.shp", color = :black, width = 1.5, alpha = 1.0),
],
```
