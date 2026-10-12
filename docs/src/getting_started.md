# Getting Started

This page takes you from an empty computer to an open TerraScope window. You do not need to
know Julia. You must know how to open a terminal and how to edit a text file.

## 1. Install Julia

TerraScope needs Julia 1.12 or newer. We recommend Julia 1.13.0, because it precompiles
faster. Thus the first start of TerraScope takes less time.

Get Julia from [julialang.org/downloads](https://julialang.org/downloads/). The page recommends
`juliaup`, a small tool that installs Julia and keeps it up to date. Use it. Then install
Julia 1.13.0 and make it the default:

```shell
juliaup add 1.13.0
juliaup default 1.13.0
```

To make sure that the installation is correct, open a new terminal and type:

```shell
julia --version
```

The terminal must show `julia version 1.13.0`. If it shows an error, the terminal cannot find Julia.
Close the terminal, open a new one and try again.

## 2. Get TerraScope

Download the code and go into its folder:

```shell
git clone https://github.com/JuliaGeophysics/TerraScope.jl
cd TerraScope.jl
```

Install the packages that TerraScope needs:

```shell
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

What does this command do? `--project=.` tells Julia to use the package list in the current
folder. `Pkg.instantiate()` downloads and installs all packages in that list. You do this one
time only. It can take 10 minutes or more.

## 3. Tell TerraScope where your files are

Open `examples/launch_TerraScope3D.jl` in a text editor. This is the only file that you edit.
It has three sections:

1. **Inputs**: the model and data files to load. See [Inputs](inputs.md).
2. **Shapefiles**: the geological maps to show, for example fault traces or geological units.
   You can add any shapefile. Each file has its own `color`, `width` and `alpha`.
3. **Settings**: display, view, CRS, seismic, overlay and isosurface options. See
   [Launcher settings](settings.md).

The file contains example paths. They are not correct on your computer. Replace them with the
paths to your files, or use `""` for an input that you do not have.

Let us look at one line:

```julia
MT_model = raw"C:\data\survey\model.rho",
```

- `MT_model` is the name of the input. Do not change it.
- `raw"..."` is a text that Julia reads exactly as written. Use it for Windows paths, because
  then you do not have to double each `\`.
- The comma at the end is necessary. Do not remove it.

To ignore an input, write `MT_model = "",`.

## 4. Open the viewer

```shell
julia --project=. examples/launch_TerraScope3D.jl
```

On Windows, you can also double-click `Launch-TerraScope.cmd` in the repository folder. See
[Faster startup](startup.md).

The first start is slow, because Julia compiles the code before it runs it. The next starts are
faster. To make them faster again, see [Faster startup](startup.md).

The launcher first checks each path. Then it shows the progress:

![The launcher in the terminal](assets/launcher.png)

A `✗` shows a path that is not correct. Correct the path and start again.

## 5. Use the viewer

![The TerraScope viewer](assets/viewer.png)

The 3D scene is in the center. The controls are at the bottom.

The property buttons select the volume. The scene, the sections, the isosurfaces and the exports
use the selected volume. If there is no file for a property, its button shows `N/A`.

**Show Data** shows the measured data for the property on the screen. For example, select density
and push **Show Data**. The viewer then shows the gravity stations.

### Draw a cross-section

!!! tip "Any profile, drawn by hand"
    You can cut a vertical cross-section along any profile through the model. The profile can
    follow a seismic line, cross a fault at right angles or connect two drill holes. It can have
    as many bends as you need.

    1. Push **Show Both Panels**. The map panel opens below the 3D view.
    2. In the map panel, left-click to add the vertices of the profile.
    3. Right-click, or push **Finish Section**. The cross-section appears in the 3D view.
    4. Draw more profiles if necessary. Use **Prev** and **Next** to select the active section.
    5. Set **2D max depth (km)**, then push **Export 2D Sections**. TerraScope saves each
       cross-section as a PNG image in a new `Export2D` folder in `examples`.

    **Clear Points** removes the vertices of the profile that you draw now. **Undo Section** removes
    the last cross-section.

## When something goes wrong

- **`julia` is not found.** Julia is not on your `PATH`. Install Julia again with `juliaup`, then
  open a new terminal.
- **A path shows `✗`.** The file is not at that location. Copy the full path from your file
  manager and paste it between the quotes of `raw"..."`.
- **The view has no map data or stations.** The MT model is not georeferenced. Add the
  `MT_data` file. See [What you get](inputs.md#what-you-get).
