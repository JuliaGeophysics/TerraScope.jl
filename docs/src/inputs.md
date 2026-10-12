# Inputs

All inputs are optional. Each method has two inputs:

- `_model` is the 3D volume, for example the result of an inversion.
- `_data` is the measured dataset for the same method.

| Input | Formats | TerraScope shows |
| --- | --- | --- |
| `MT_model` | ModEM/WS `.rho`, jif3D `.nc` | A 3D resistivity model |
| `MT_data` | ModEM `.dat`, jif3D `.nc` | The MT sites. This file also georeferences the model. |
| `gravity_model` | `.xyz`, `.vox`, jif3D `.nc` | A 3D density or density-contrast model |
| `gravity_data` | `.xyz`, jif3D `.nc` (mGal) | The gravity stations, at the station elevation |
| `magnetic_model` | `.xyz`, `.vox`, jif3D `.nc` | A 3D magnetic susceptibility model |
| `magnetic_data` | `.xyz`, jif3D `.nc` (nT) | The magnetic measurement points, ground or airborne |
| `seismic_data` | SEG-Y, one path or a list | A vertical 2D seismic section along each profile, and the model section along the same profile |
| `shapefiles` | Any `.shp` | A geological map layer. Each entry has its own `color`, `width` and `alpha`. |

## What you get

What does the scene show? That depends on the inputs that you give:

| Inputs | Result |
| --- | --- |
| None | An empty 3D view. Its extent comes from the map data or the seismic profiles, if you give them. |
| `MT_model` only | The model in its local coordinates. Georeferenced overlays are not shown. |
| `MT_model` and `MT_data` | The model, georeferenced into `coordinate.target_crs` |
| A jif3D `.nc` `MT_model` | The model, georeferenced from `coordinate.jif3d_crs` (default EPSG:3067) |
| A gravity or magnetic model, with an MT model | The model, resampled onto the MT mesh. You can compare the physical properties cell by cell. |
| A gravity or magnetic model, without an MT model | The model on a mesh made from its own coordinates |

Why does a ModEM model need its data file? A ModEM `.rho` file gives the cells in metres from an
origin, but it does not give the location of that origin. The `.dat` file gives it.

## Density units and density contrast

Many inversions give a density contrast, not an absolute density. TerraScope shows the values as
they are in the file. A contrast model has the label `Δρ`.

To show absolute density, set the background density in the launcher:

```julia
model = (
    density_reference_kg_m3 = 2670.0,   # TerraScope adds this value to each cell.
    density_units = :g_cc,              # Or :kg_m3.
),
```

## jif3D NetCDF files

TerraScope reads a `.nc` file in any model or data input as
[jif3D](https://git.tu-berlin.de/applied-geophysics/jif3d) output. The variable in the file gives
the property:

- Models: `Conductivity` (shown as resistivity), `Density` or `Susceptibility`.
- Data: MT impedances, `Scalar_gravity` or the total field `T`.

A jif3D mesh is in absolute projected metres. Thus an MT model does not need a data file to be
georeferenced. If the inversion did not use the CRS of the scene, set `coordinate.jif3d_crs`.

## Shapefiles

You can add any shapefile and as many shapefiles as you need. TerraScope draws them on the
surface, above the model:

- Polyline features, for example fault traces, lithological contacts and shear zones.
- Polygon features as their boundaries, for example geological units and licence areas.

TerraScope does not draw point features, for example outcrop observations or drill-hole collars.

If the shapefile has a `.prj` file, TerraScope reads the CRS from it and reprojects the features
into the project CRS.

## More than one seismic profile

`seismic_data` can be a list. Each entry is a path, or a named tuple:

```julia
seismic_data = [
    raw"C:\data\seismic\line1.sgy",
    (path = raw"C:\data\seismic\line2.sgy", label = "Line 2", line_color = :red),
],
```

A named tuple can have these fields: `path`, `label`, `line_color`, `sample_spacing_m` and
`top_z_m`. A field that you do not give uses the value from the `seismic` settings.

If you set `seismic.trace_xy = :auto`, TerraScope uses the first trace header that has
coordinates: source, receiver group or CDP.

## Point files

An `.xyz` file has one record on each line. A record has four columns:

```
longitude  latitude  elevation  value
```

You can also use easting and northing in a projected CRS. TerraScope reprojects the points into
the project CRS. For a model, it then resamples the values onto the model mesh.

### Source CRS detection

An `.xyz` file does not tell its CRS. How does TerraScope find it?

Look at the numbers. A longitude is between −180 and 180, and a latitude is between −90 and 90.
A projected CRS puts survey data tens or hundreds of kilometres from its false origin. Thus the
two types of coordinates do not overlap, and the size of the numbers tells the CRS. TerraScope
reads the file as WGS84 longitude/latitude, or as coordinates that are already in the project CRS.

But one case is not clear. If the two columns are both between −90 and 90, which column is the
longitude? TerraScope then uses the area of use of the project CRS. Thus a file with latitude in
the first column also goes to the correct location.

TerraScope always reads `.prj` files and ModEM origins from the files.
