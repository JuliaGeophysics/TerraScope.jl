# TerraScope.jl

TerraScope is a local Julia/Makie viewer for geophysical models, GIS overlays and seismic sections.

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/launch_TerraScope3D.jl
```

The viewer opens an empty project. First choose a **project coordinate system** and click **Use CRS**. Then use **Import…**, choose a format, browse to a file, enter its source CRS/options, and click **Load layer**. Repeat for each model. Models of the same property remain separate layers. The layer selector controls visibility and the active model's horizontal/X/Y slice. Slice changes are applied explicitly with **Apply slice**.

Project coordinates must use a projected CRS in metres. Presets include GDA94 / MGA zone 54 (`EPSG:28354`), GDA2020 / MGA zone 54 (`EPSG:7854`), WGS84 / UTM 54S (`EPSG:32754`) and Finnish TM35FIN (`EPSG:3067`); other EPSG codes and PROJ CRS strings can be entered. The project CRS is locked after the first layer. Each import converts its XY coordinates to that CRS once, retaining curved/rotated grid geometry. Geographic sources use longitude, latitude order. Z is elevation in metres, with a common vertical datum supplied by the user; horizontal reprojection does not perform a vertical datum conversion.

| Format | Import options and conventions |
| --- | --- |
| ModEM `.rho` | Optional horizontal padding trim and depth cutoff (GUI defaults: trim, 50 km). LINEAR, LOGE and LOG10 storage; north/east/down axes and mesh rotation. Supply an absolute source CRS, or a local origin latitude/longitude, or a ModEM `.dat` file whose header supplies that origin. Local origins use the existing viewer's WGS84 transverse-Mercator convention with scale 0.9996. |
| XYZ `.xyz`, `.dat`, `.csv` | Whitespace, comma or semicolon separated points; choose X/Y/Z/value columns, header rows, elevation/depth convention and NoData. Irregular pointsets remain points, avoiding a large artificial Cartesian grid. |
| UBC3D tensor model | Density, susceptibility, resistivity or another scalar property. A same-basename `.msh` or `.mesh` is located automatically, case-insensitively, or enter a mesh path. Supports `n*width` mesh notation, southwest/top origin and Z-fastest, then X, then Y values. Set inactive/NoData explicitly. Octree and vector models are not supported. |
| TerraScope `.vox` | Existing voxel reader; provide the source CRS and property/units. |
| Shapefile `.shp` | Source CRS from `.prj`, or enter it explicitly. Points, multipart lines and polygon outlines are supported; sidecars must remain beside the `.shp`. |
| SEG-Y `.sgy` / `.segy` | Existing original-amplitude or envelope display; source/group coordinates, depth spacing per original sample, top depth and trace/sample caps. Supply the source CRS. Time-domain sections require an appropriate depth conversion before import. |
| GeoTIFF / NetCDF | Single-band raster/variable; embedded CRS or explicit override, NoData and plane elevation. Multi-variable NetCDF containers should first be exported to a single-variable raster. |

Property units are labels, not automatic unit conversions. The log10 option applies to positive physical values; invalid, inactive and nonpositive log values are masked.

## Cloncurry

The local `data/Cloncurry` collection can be imported without editing a launcher:

- `mt/model_release/MT076_CloncurryMT_Model_Release_Package/Model_files/ModEM/Isa_100hz_z_run4_NLCG_051.rho`: choose ModEM and enter the matching `.dat` in the origin-header field. Its header records latitude `-20.338`, longitude `140.711`.
- `.../Pointset/CloncurryMTModel.dat`: choose **XYZ / CSV**, columns `1,2,3,4`, zero header rows, Z as elevation, resistivity in ohm m. This file is a comma-separated model pointset, not ModEM impedance data. Supply its published source CRS; a bare pointset carries no CRS metadata, so TerraScope does not guess its datum.
- `gravity/*.tif`, `magnetics/*.tif` and corresponding `.nc`: choose **Raster grid**, using embedded CRS. Choose Other scalar and the file's units (for example gu or nT). These are map grids, not 3D density/susceptibility volumes.
- `.../Original_data/StationLocation.shp`: choose Shapefile and provide its source CRS if no `.prj` accompanies it.

No seismic file is required. Existing seismic files can still be added independently through the same importer.

## Performance and compatibility

Imports are serial and transactional: failures leave loaded layers intact. Changing a slice or layer visibility never rereads files or reprojects coordinates. Color ranges are computed once per import. Only the affected layer is redrawn. Grid slices are capped at 400 samples per side and point displays at 200,000 points; the session retains full-resolution values within the selected import bounds. SEG-Y is downsampled before amplitude conversion/envelope processing (the underlying SegyIO reader still reads the source file). GDAL and OpenGL are loaded only when needed.

The previous scripted viewer remains in `examples/TerraScope3D.jl`, including its existing seismic and export tools. The older bundle-based package viewer is available as `launch_demo_viewer(...)`. The new default import viewer supports independent layers and orthogonal slices; the legacy manual-polyline, isosurface and export controls remain in those legacy viewers.

For API use:

```julia
using TerraScope
session = ImportSession()
set_project_crs!(session, "EPSG:28354")
layer = import_layer!(session, "model.xyz", ImportOptions(
    format=:xyz, source_crs="EPSG:32754", kind=:resistivity,
    units="ohm m", log10_values=true))
```

Run tests with `julia --project=. test/runtests.jl`. Tests can run without a display; an interactive viewer requires OpenGL. Build a fresh sysimage after updating the package with `julia --project=. scripts/build_sysimage.jl`; the precompile workload uses small temporary fixtures and does not require demo data. On Windows, `Launch-TerraScope.cmd` uses the built sysimage when available.

UBC ordering follows the [UBC-GIF GRAV3D format documentation](https://www.eoas.ubc.ca/courses/eosc350/content/sftwrdocs/grav3d/elements.htm). CRS operations use [Proj.jl](https://github.com/JuliaGeo/Proj.jl).
