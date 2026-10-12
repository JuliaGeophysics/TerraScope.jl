# Launcher settings

Section 3 of `examples/launch_TerraScope3D.jl` contains the startup settings. All groups and all
keys are optional. If you do not give a key, TerraScope uses its default value from
`examples/TerraScope3D.jl`.

## How to read a setting

The settings use Julia named tuples. A named tuple is a list of `name = value` pairs between
parentheses:

```julia
overlay = (show_north_arrow = true, line_width = 1.5),
```

You will see these types of values:

| Value | Meaning | Example |
| --- | --- | --- |
| `true`, `false` | On or off | `show_scale_bar = true` |
| A number | A number. Use a point for decimals. | `max_depth_m = 50000.0` |
| `"text"` | A text | `target_crs = "EPSG:3067"` |
| `:name` | A fixed choice, for example a colormap | `colormap = :Spectral` |
| `(a, b)` | A pair, for example a minimum and a maximum | `resistivity = (1.0, 4.0)` |
| `nothing` | No value. TerraScope calculates one. | `density = nothing` |

Put a comma after each entry. Text after `#` is a comment, and Julia ignores it.

## All settings

```julia
model = (                                                # Volume display and sections.
    log10_scale = true, colormap = :Spectral,            # log10(rho) is the usual MT choice.
    max_depth_m = 50000.0,                               # Cells below this depth are not shown.
    show_padding = false, pad_tolerance = 0.2,           # Hide ModEM padding cells, and how to find them.
    section_samples_along = 360,                         # Samples along a section. More is smoother but slower.
    density_reference_kg_m3 = nothing,                   # Added to density. `nothing` shows the file values.
    density_units = :g_cc,                               # `:g_cc` or `:kg_m3`.
    display_ranges = (resistivity = (1.0, 4.0), density = nothing, susceptibility = nothing),
),                                                       # `nothing` calculates the range. Resistivity is log10(ohm.m).

view = (                                                 # Window layout and start camera.
    open_fullscreen = false, show_only_3d_scene = true,  # `false` also shows the control and selector panels.
    show_outer_ticks_axis = true, export_png_scale = 4,  # XYZ tick labels, and PNG export resolution multiplier.
    default_view_direction = (-0.15, -1.05, 0.72), default_view_scale = 1.12,   # Looks north at start.
),

coordinate = (                                           # Must be a projected CRS in metres. Do not use EPSG:4326.
    target_crs = "EPSG:3067", selector_show_latlon_ticks = true,
    jif3d_crs = "EPSG:3067",                             # CRS of jif3D `.nc` meshes and stations.
),

seismic = (                                              # SEG-Y curtain and model drape.
    show = true, display_mode = :envelope,               # `:original` shows signed amplitudes.
    trace_xy = :source,                                  # The header coordinates that locate the traces.
    max_traces = 1400, max_samples = 1200,               # Limits that keep large files fast.
    sample_spacing_m = 12.5, clip_quantile = 0.995,      # Trace resample distance, and amplitude clip.
    show_model_section = false,                          # Show the model drape along the line at start.
),

overlay = (                                              # Annotations and survey style.
    show_north_arrow = true, show_scale_bar = true,
    line_color = :black, line_width = 1.5,               # For a shapefile entry without its own values.
    survey_colormap = :viridis, survey_markersize = 5,   # How `_data` point files are shown.
),

isosurface = (                                           # Start values for the isosurface controls.
    enabled = false, alpha = 0.72, stride = 1, color_by_depth = false,
),
```

## Shapefiles

Section 2 contains the shapefiles. Write one entry for each file:

```julia
shapefiles = [
    (path = raw"C:\data\gis\faults.shp", color = :black, width = 1.5, alpha = 1.0),
    (path = raw"C:\data\gis\lakes.shp",  color = :blue,  width = 1.0, alpha = 0.6),
],
```

`alpha` is the opacity: `1.0` is solid and `0.0` is invisible. If you have no shapefiles, write
`shapefiles = [],`.
