# TerraScope.jl

TerraScope.jl is a [Makie](https://docs.makie.org/)-based local viewer for MT, density, shapefile, and seismic datasets. The first implementation targets the same interaction model as the MTGeophysics 3D viewer examples while keeping all code isolated to this repository.

## Quick Start

```shell
julia --project=. examples/launch_TerraScope3D.jl
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

  › [███░░░░░░░░░░░░░░░░░░░░░░░░░░░]  11%  Loading resistivity model…
  › [███████░░░░░░░░░░░░░░░░░░░░░░░]  22%  Georeferencing model…
  › [██████████░░░░░░░░░░░░░░░░░░░░]  33%  Loading density volume…
  › [█████████████░░░░░░░░░░░░░░░░░]  44%  Loading susceptibility volume…
  › [█████████████████░░░░░░░░░░░░░]  56%  Loading gravity volume…
  › [████████████████████░░░░░░░░░░]  67%  Loading magnetic volume…
  › [███████████████████████░░░░░░░]  78%  Loading seismic section…
  › [███████████████████████████░░░]  89%  Building 3D scene…
  ✓ [██████████████████████████████] 100%  Opening viewer

  ✓ TerraScope is ready. Close the window to exit.
```

