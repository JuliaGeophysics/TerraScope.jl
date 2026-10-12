```@raw html
---
layout: home

hero:
  name: "TerraScope.jl"
  tagline: A 3D viewer for MT, gravity, magnetic, seismic and shapefile data.
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
    details: You write your file paths and settings in one file. All inputs are optional. The launcher checks each path before it loads the data.
    link: /getting_started
  - title: Many methods in one scene
    details: Resistivity, density and susceptibility models use the same grid. Thus you can compare the properties cell by cell.
    link: /inputs
  - title: Georeferenced overlays
    details: TerraScope moves shapefiles, survey points and SEG-Y lines into one projected CRS.
    link: /inputs#point-files
  - title: Faster startup
    details: Build a custom system image one time. Then the viewer opens much faster.
    link: /startup
---
```

## What is TerraScope.jl?

TerraScope.jl is a 3D viewer for geophysical models and data. It shows these items in one scene:

- MT resistivity models and MT sites
- Density models and gravity surveys
- Susceptibility models and magnetic surveys
- Seismic lines from SEG-Y files
- Linework from shapefiles

TerraScope runs on your computer. It uses [Makie](https://docs.makie.org/) for the graphics.
It is part of the [JuliaGeophysics](https://github.com/JuliaGeophysics) ecosystem.

![The TerraScope viewer](assets/viewer.png)

## Where do I start?

Are you new to Julia? Then start at [Getting Started](getting_started.md). It shows how to
install Julia and how to open the viewer for the first time.

Do you have Julia already? Then read [Inputs](inputs.md) to find which files TerraScope can read.
