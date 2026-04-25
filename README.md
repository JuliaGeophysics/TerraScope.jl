# TerraScope.jl

TerraScope.jl is a [Makie](https://docs.makie.org/)-based local viewer for MT, density, shapefile, and seismic datasets. It keeps model/data IO, voxel handling, overlays, seismic curtains, and 3D viewing tools in one Julia package.

## Quick Start

```shell
julia --project=. examples/launch_TerraScope3D.jl
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

## Demo Voxel Generation

The viewer loads 3D density and susceptibility from voxel files. Synthetic demo voxel generation is kept outside the runtime viewer in [scripts/generate_synthetic_voxels.jl](scripts/generate_synthetic_voxels.jl):

```shell
julia --project=. scripts/generate_synthetic_voxels.jl
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
  › [█████████████████████░░░░░░░░░]  71%  Loading seismic section…
  › [██████████████████████████░░░░]  86%  Building 3D scene…
  ✓ [██████████████████████████████] 100%  Opening viewer

  ✓ TerraScope is ready. Close the window to exit.
```

