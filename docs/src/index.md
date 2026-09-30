```@raw html
---
layout: home

hero:
  name: "TerraScope.jl"
  tagline: A Makie-based 3D viewer for MT, gravity, magnetic, shapefile and seismic datasets.
  actions:
    - theme: brand
      text: Getting Started
      link: /getting_started
    - theme: alt
      text: Inputs
      link: /inputs
    - theme: alt
      text: View on GitHub
      link: https://github.com/JuliaGeophysics/TerraScope.jl

features:
  - title: One launcher file
    details: Name your files, list your shapefiles, pick your settings. Every input is optional and is checked before the slow work starts.
    link: /getting_started
  - title: Many methods, one scene
    details: MT resistivity, density and susceptibility volumes share one grid, so properties compare cell for cell.
    link: /inputs
  - title: Georeferenced overlays
    details: Shapefiles, survey points and SEG-Y curtains are reprojected into a single projected CRS.
    link: /inputs#reading-point-files
  - title: Faster startup
    details: Build a custom sysimage once to strip most first-run compilation before a demo.
    link: /startup
---
```

## What is TerraScope.jl?

TerraScope.jl is a [Makie](https://docs.makie.org/)-based local viewer for MT, density,
susceptibility, shapefile and seismic datasets. Model and data IO, voxel handling, overlays, seismic
curtains and the 3D viewing tools all live in one Julia package, part of the
[JuliaGeophysics ecosystem](https://github.com/JuliaGeophysics).
