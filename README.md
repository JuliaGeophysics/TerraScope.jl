# TerraScope.jl

[![CI](https://github.com/JuliaGeophysics/TerraScope.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaGeophysics/TerraScope.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliageophysics.com/TerraScope.jl/dev/)

A 3D viewer for MT, gravity, magnetic and seismic models and data, with geological maps from shapefiles.
Part of [JuliaGeophysics](https://github.com/JuliaGeophysics).

![The TerraScope viewer](docs/src/assets/viewer.png)

> [!TIP]
> **Draw your own cross-sections.** Click points on the map to draw a profile in any direction,
> with as many bends as you need. TerraScope cuts the model along the profile and shows the
> vertical cross-section in 3D. You can export each cross-section as an image.

## Quick start

```shell
git clone https://github.com/JuliaGeophysics/TerraScope.jl
cd TerraScope.jl
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. examples/launch_TerraScope3D.jl
```

Set your file paths in `examples/launch_TerraScope3D.jl`.
Julia 1.12 or newer is necessary. Julia 1.13.0 is recommended, because it precompiles faster.

![The launcher in the terminal](docs/src/assets/launcher.png)

## Documentation

[juliageophysics.com/TerraScope.jl](https://juliageophysics.com/TerraScope.jl/dev/)
