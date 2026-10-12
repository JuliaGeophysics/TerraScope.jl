# Inputs

Every input is optional. A method's `_model` is the 3D volume and its `_data` is the measured dataset
for the same method.

| Input | Formats | Loaded as |
| --- | --- | --- |
| `MT_model` | ModEM/WS `.rho`, jif3D `.nc` | Resistivity volume |
| `MT_data` | ModEM `.dat`, jif3D `.nc` | Georeferences the mesh; **Show Data** draws the site locations |
| `gravity_model` | `.xyz`, `.vox`, jif3D `.nc` | Density volume, displayed in g/cc |
| `gravity_data` | `.xyz`, jif3D `.nc` (mGal) | **Show Data** draws the survey points at their own elevation |
| `magnetic_model` | `.xyz`, `.vox`, jif3D `.nc` | Susceptibility volume |
| `magnetic_data` | `.xyz`, jif3D `.nc` (nT) | **Show Data** draws the survey points |
| `seismic_data` | SEG-Y, one path or a list | Seismic curtain and model drape per line |
| `shapefiles` | `.shp` | Linework, each entry with its own `color`, `width` and `alpha` |

## What you get

What you get depends on what you configure:

| Configured | Result |
| --- | --- |
| Nothing | An empty 3D scene, sized to the shapefiles or seismic line if there are any |
| `MT_model` only | The model in its own local coordinates; georeferenced overlays are left out |
| `MT_model` + `MT_data` | Georeferenced into `coordinate.target_crs` |
| A jif3D `.nc` `MT_model` | Georeferenced on its own, from `coordinate.jif3d_crs` (default EPSG:3067) |
| A gravity/magnetic model with an MT model | Resampled onto the MT cells, so the properties compare cell for cell |
| A gravity/magnetic model without one | Gridded on axes taken from its own coordinates |

## jif3D NetCDF files

A `.nc` file in any model or data slot is read as [jif3D](https://git.tu-berlin.de/applied-geophysics/jif3d)
output. The property comes from the variable in the file: `Conductivity` (shown as resistivity),
`Density` or `Susceptibility` for models; MT impedances, `Scalar_gravity` or total-field `T` for data.
jif3D meshes are absolute projected metres, so an MT model needs no data file to be placed; set
`coordinate.jif3d_crs` when the inversion was not run in the scene's CRS.

## Several seismic lines

`seismic_data` takes a list. Each entry is a path, or `(path =, label =, line_color =,
sample_spacing_m =, top_z_m =)`; fields left out use the `seismic` settings. With `seismic.trace_xy =
:auto`, traces are located from the source, group or CDP headers, whichever is filled in.

## Reading point files

`.xyz` models and surveys are `longitude latitude elevation value` records, or easting/northing in any
projected CRS. They are reprojected into the project CRS and, for models, resampled onto the scene's
cells.

### Source CRS detection

A file that states no CRS has one worked out for it. Degrees and projected metres never overlap in
practice: longitude/latitude is bounded by ±180/±90, while a metric CRS puts survey data tens to
hundreds of kilometres from its false origin. A file is therefore read as WGS84 lon/lat or as already
being in the project CRS accordingly. When both columns fall inside ±90 and the lon/lat order is
ambiguous, the project CRS's declared area of use decides which column is longitude, so
latitude-first files land in the right place too. `.prj` files and ModEM origins are still read from
the file itself.
