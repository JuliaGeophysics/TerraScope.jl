```@raw html
---
layout: home

hero:
  name: "TerraScope.jl"
  tagline: A 3D viewer for MT, gravity, magnetic and seismic models and data, with geological maps from shapefiles.
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
  - title: Joint interpretation
    details: Resistivity, density and susceptibility models use the same mesh. Thus you can compare the physical properties cell by cell.
    link: /inputs
  - title: Georeferenced overlays
    details: TerraScope reprojects geological maps, measurement stations and seismic profiles into one projected CRS.
    link: /inputs#point-files
  - title: Faster startup
    details: Build a custom system image one time. Then the viewer opens much faster.
    link: /startup
---
```

## What is TerraScope.jl?

TerraScope.jl is a 3D viewer for geophysical models and data. It shows these datasets together in
one 3D view:

- MT resistivity models and MT sites
- Density models and gravity stations
- Magnetic susceptibility models and magnetic measurements
- 2D seismic sections from SEG-Y files
- Geological maps from any shapefile: fault traces, lithological contacts, geological units and
  survey outlines

TerraScope runs on your computer. It uses [Makie](https://docs.makie.org/) for the graphics.
It is part of the [JuliaGeophysics](https://github.com/JuliaGeophysics) ecosystem.

![The TerraScope viewer](assets/viewer.png)

!!! tip "Draw your own cross-sections"
    Click points on the map to draw a profile in any direction, with as many bends as you need.
    TerraScope cuts the model along the profile and shows the vertical cross-section in 3D. You
    can export each cross-section as an image. See [Draw a cross-section](getting_started.md#draw-a-cross-section).

## Where do I start?

Are you new to Julia? Then start at [Getting Started](getting_started.md). It shows how to
install Julia and how to open the viewer for the first time.

Do you have Julia already? Then read [Inputs](inputs.md) to find which files TerraScope can read.
