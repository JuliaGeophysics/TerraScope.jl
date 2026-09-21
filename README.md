# TerraScope.jl

TerraScope.jl is a [Makie](https://docs.makie.org/)-based local viewer for MT, density, shapefile, and seismic datasets. It keeps model/data IO, voxel handling, overlays, seismic curtains, and 3D viewing tools in one Julia package.

## Quick Start

```shell
julia --project=. examples/launch_TerraScope3D.jl
```

[examples/launch_TerraScope3D.jl](examples/launch_TerraScope3D.jl) is the only file you edit. Section 1
names the files by method, section 2 lists the shapefiles, and section 3 holds the startup settings;
anything left out of section 3 keeps its default from `examples/TerraScope3D.jl`. Paths are absolute.
The launcher checks each one before the slow work starts and prints what it found.

## Inputs

Every input is optional. A method's `_model` is the 3D volume and its `_data` is the measured dataset
for the same method.

| Input | Formats | Loaded as |
| --- | --- | --- |
| `MT_model` | ModEM/WS `.rho` | Resistivity volume |
| `MT_data` | ModEM `.dat` | Georeferences the mesh; **Show Data** draws the site locations |
| `gravity_model` | `.xyz`, `.vox` | Density volume, displayed in g/cc |
| `gravity_data` | `.xyz` | **Show Data** draws the survey points at their own elevation |
| `magnetic_model` | `.xyz`, `.vox` | Susceptibility volume |
| `magnetic_data` | `.xyz` | **Show Data** draws the survey points |
| `seismic_data` | SEG-Y | Seismic curtain and model drape |
| `shapefiles` | `.shp` | Linework, each entry with its own `color`, `width` and `alpha` |

What you get depends on what you configure:

| Configured | Result |
| --- | --- |
| Nothing | An empty 3D scene, sized to the shapefiles or seismic line if there are any |
| `MT_model` only | The model in its own local coordinates; georeferenced overlays are left out |
| `MT_model` + `MT_data` | Georeferenced into `coordinate.target_crs` |
| A gravity/magnetic model with an MT model | Resampled onto the MT cells, so the properties compare cell for cell |
| A gravity/magnetic model without one | Gridded on axes taken from its own coordinates |

The property buttons switch which volume the scene, sections, isosurfaces and exports work on; a
property with no file behind it reads `N/A`. **Show Data** overlays the measured data belonging to
whichever property is on screen.

## Reading point files

`.xyz` models and surveys are `longitude latitude elevation value` records, or easting/northing in any
projected CRS. They are reprojected into the project CRS and, for models, resampled onto the scene's
cells.

### Source CRS detection

A file that states no CRS has one worked out for it. Degrees and projected metres never overlap in
practice — longitude/latitude is bounded by ±180/±90, while a metric CRS puts survey data tens to
hundreds of kilometres from its false origin — so a file is read as WGS84 lon/lat
or as already being in the project CRS accordingly. When both columns fall inside ±90 and the
lon/lat order is therefore ambiguous, the project CRS's declared area of use decides which column is
longitude, so latitude-first files land in the right place too. `.prj` files and ModEM origins are still read from the
file itself.

### Demo datasets

[scripts/generate_synthetic_data.jl](scripts/generate_synthetic_data.jl) writes four WGS84 lon/lat point
files into `Data/demo`, derived from the demo ModEM mesh. None of them states a CRS, so loading them
exercises the detection above:

| File | Launcher input | Units | Records |
| --- | --- | --- | --- |
| `density.xyz` | `gravity_model` | kg/m³ | 37,044 |
| `susceptibility.xyz` | `magnetic_model` | SI | 37,044 |
| `gravity.xyz` | `gravity_data` | mGal | 7,056 |
| `magnetic.xyz` | `magnetic_data` | nT | 7,056 |

The two surveys are depth-weighted column integrals of the matching 3D model — enough to look like
data flown over the same bodies, not a rigorous forward calculation.

A headless check that every launcher configuration builds a scene against the demo data:

```shell
julia --project=. scripts/startup_smoketest.jl
```

## Faster Startup

If you want to remove most of the first-run compilation before a demo, build a custom sysimage once and launch TerraScope with it:

```shell
julia --project=. scripts/build_sysimage.jl
julia --project=. -J build/TerraScopeSysimage.dll examples/launch_TerraScope3D.jl
```

This does not eliminate file I/O, Windows display setup, or GL context creation, but it substantially reduces Julia compilation and makes startup more consistent across runs.

On Windows, you can also use the launcher in the repository root:

```shell
Launch-TerraScope.cmd
```

The launcher uses the sysimage automatically when it exists and offers to build it the first time.

## Demo Data Generation

The four lon/lat `.xyz` files above are generated outside the runtime viewer, from the demo ModEM mesh:

```shell
julia --project=. scripts/generate_synthetic_data.jl
```

### Example Output

```
  Activating project at `C:\Users\pmishra\OneDrive - Valtori GTK\Documents\Mac\GitHub\TerraScope.jl`

  ┌──────────────────────────────────────────────────────┐

▄▄▄▄▄▄▄▄▄                       ▄▄▄▄▄▄▄
▀▀▀███▀▀▀                      █████▀▀▀
   ███ ▄█▀█▄ ████▄ ████▄  ▀▀█▄  ▀████▄  ▄████ ▄███▄ ████▄ ▄█▀█▄
   ███ ██▄█▀ ██ ▀▀ ██ ▀▀ ▄█▀██    ▀████ ██    ██ ██ ██ ██ ██▄█▀
   ███ ▀█▄▄▄ ██    ██    ▀█▄██ ███████▀ ▀████ ▀███▀ ████▀ ▀█▄▄▄
                                                    ██
                                                    ▀▀
  └──────────────────────────────────────────────────────┘

  Let's look at diverse geophysical models together...
  Feedback / Issues → pankaj.mishra@gtk.fi
  Data directory    → C:\Users\pmishra\TerraScope.jl\Data\demo

  ✓  MT model        I_NLCG_140.rho
  ✓  MT data         I_NLCG_140.dat
  ✓  gravity model   density.xyz
  ✓  gravity data    gravity.xyz
  ✓  magnetic model  susceptibility.xyz
  ✓  magnetic data   magnetic.xyz
  ✓  seismic data    fire_updated.sgy
  ✓  shapefile       Tnew.shp

  › [███░░░░░░░░░░░░░░░░░░░░░░░░░░░]  11%  Loading MT model…
  › [███████░░░░░░░░░░░░░░░░░░░░░░░]  22%  Georeferencing…
  › [██████████░░░░░░░░░░░░░░░░░░░░]  33%  Loading gravity model…
  › [█████████████░░░░░░░░░░░░░░░░░]  44%  Loading magnetic model…
  › [█████████████████░░░░░░░░░░░░░]  56%  Loading measured data…
  › [████████████████████░░░░░░░░░░]  67%  Loading seismic section…
  › [███████████████████████░░░░░░░]  78%  Building 3D scene…
  › [███████████████████████████░░░]  89%  Opening viewer…
  ✓ [██████████████████████████████] 100%  Viewer ready

  ✓ TerraScope is ready. Close the window to exit.
```

