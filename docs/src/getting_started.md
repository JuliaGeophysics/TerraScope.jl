# Getting Started

## Installation

TerraScope.jl requires Julia 1.12 or newer. Clone the repository and instantiate the project:

```shell
git clone https://github.com/JuliaGeophysics/TerraScope.jl
cd TerraScope.jl
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

## Launching the viewer

```shell
julia --project=. examples/launch_TerraScope3D.jl
```

On Windows you can run `Launch-TerraScope.cmd` from the repository root instead; see
[Faster startup](startup.md).

[`examples/launch_TerraScope3D.jl`](https://github.com/JuliaGeophysics/TerraScope.jl/blob/main/examples/launch_TerraScope3D.jl)
is the only file you edit. It has three sections:

1. **Inputs**: the files to load, by method (see [Inputs](inputs.md)). Paths are absolute; `""` means not used.
2. **Shapefiles**: linework, each entry with its own `color`, `width` and `alpha`.
3. **Settings**: display, view, CRS, seismic, overlay and isosurface options. Anything left out
   keeps its default from `examples/TerraScope3D.jl`; see [Launcher settings](settings.md).

The launcher checks each path before the slow work starts and prints what it found:

```
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
  ...
  ✓ [██████████████████████████████] 100%  Viewer ready

  ✓ TerraScope is ready. Close the window to exit.
```

## Using the viewer

The property buttons switch which volume the scene, sections, isosurfaces and exports work on; a
property with no file behind it reads `N/A`. **Show Data** overlays the measured data belonging to
whichever property is on screen.
