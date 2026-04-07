# TerraScope.jl

TerraScope.jl is a Makie-based local viewer for MT, density, shapefile, and seismic datasets. The first implementation targets the same interaction model as the MTGeophysics 3D viewer examples while keeping all code isolated to this repository.

## Current Scope

- Load a bundled ModEM resistivity model and data file.
- Generate and persist a synthetic voxel density model on the MT core mesh.
- Discover bundled shapefiles and SEG-Y seismic lines in `Data/`.
- Open a GLMakie viewer with depth slicing, section drawing, seismic curtain overlay, shapefile overlays, and isovolume export.

## Quick Start

Run the app directly:

```bash
julia --project=. examples/TerraScope3D.jl
```

Or use the thin launcher wrapper:

```bash
julia --project=. examples/launch_TerraScope3D.jl
```

The package API `launch_viewer()` is still available if you want to launch from Julia code.

The default viewer looks in `Data/` under this repository.

## Data Layout

Bundled demo assets are expected in `Data/`.

- `.rho`: ModEM model
- `.dat`: ModEM data file
- `.shp` plus sidecars: shapefile overlays
- `.sgy` or `.segy`: 2D seismic line
- `.vox`: TerraScope synthetic density voxel file

