# Inputs

Every input is optional. A method's `_model` is the 3D volume and its `_data` is the measured dataset
for the same method.

| Input | Formats | Loaded as |
| --- | --- | --- |
| `MT_model` | ModEM/WS `.rho` | Resistivity volume |
| `MT_data` | ModEM `.dat` | Georeferences the mesh; **Show Data** draws the site locations |
| `gravity_model` | `.xyz`, `.vox` | Density volume, displayed in g/cc |
| `gravity_data` | `.xyz` | **Show Data** draws the survey points at their own elevation |
| `magnetic_model` | `.xyz`, `.vox` | Susceptibility volume |
| `magnetic_data` | `.xyz` | **Show Data** draws the survey points |
| `seismic_data` | SEG-Y | Seismic curtain and model drape |
| `shapefiles` | `.shp` | Linework, each entry with its own `color`, `width` and `alpha` |

## What you get

What you get depends on what you configure:

| Configured | Result |
| --- | --- |
| Nothing | An empty 3D scene, sized to the shapefiles or seismic line if there are any |
| `MT_model` only | The model in its own local coordinates; georeferenced overlays are left out |
| `MT_model` + `MT_data` | Georeferenced into `coordinate.target_crs` |
| A gravity/magnetic model with an MT model | Resampled onto the MT cells, so the properties compare cell for cell |
| A gravity/magnetic model without one | Gridded on axes taken from its own coordinates |

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
