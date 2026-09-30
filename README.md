# TerraScope.jl

[![CI](https://github.com/JuliaGeophysics/TerraScope.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaGeophysics/TerraScope.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliageophysics.com/TerraScope.jl/dev/)

TerraScope.jl is a [Makie](https://docs.makie.org/)-based 3D viewer for MT, gravity, magnetic,
shapefile and seismic datasets, part of the [JuliaGeophysics](https://github.com/JuliaGeophysics)
ecosystem.

## Quick start

Requires Julia 1.12 or newer.

```shell
git clone https://github.com/JuliaGeophysics/TerraScope.jl
cd TerraScope.jl
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. examples/launch_TerraScope3D.jl
```

[examples/launch_TerraScope3D.jl](examples/launch_TerraScope3D.jl) is the only file you edit: list your
model, data, seismic and shapefile paths, and adjust the startup settings. On Windows you can run
`Launch-TerraScope.cmd` instead.

## Documentation

Supported inputs, launcher settings, demo data and faster startup are covered in the
[documentation](https://juliageophysics.com/TerraScope.jl/dev/).

Feedback and issues: [GitHub issues](https://github.com/JuliaGeophysics/TerraScope.jl/issues).
