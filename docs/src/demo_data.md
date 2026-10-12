# Demo data

The repository does not contain data files. The script
[`scripts/generate_synthetic_data.jl`](https://github.com/JuliaGeophysics/TerraScope.jl/blob/main/scripts/generate_synthetic_data.jl)
makes four synthetic point files from the demo ModEM mesh. The script reads the mesh from
`Data/demo` and writes the files into the same folder:

```shell
julia --project=. scripts/generate_synthetic_data.jl
```

| File | Launcher input | Units | Records |
| --- | --- | --- | --- |
| `density.xyz` | `gravity_model` | kg/m³ | 37,044 |
| `susceptibility.xyz` | `magnetic_model` | SI | 37,044 |
| `gravity.xyz` | `gravity_data` | mGal | 7,056 |
| `magnetic.xyz` | `magnetic_data` | nT | 7,056 |

The coordinates are WGS84 longitude and latitude. The files do not tell their CRS. Thus they also
test the [source CRS detection](inputs.md#source-crs-detection).

How are the two surveys made? Each survey point is a depth-weighted sum of the model cells below
it. The surveys thus look like data from a flight over the same bodies. But they are not the
result of a correct forward calculation. Do not use them to test an inversion.

## Smoke test

The smoke test makes a scene for each launcher configuration from the demo data. It does not
open a window:

```shell
julia --project=. scripts/startup_smoketest.jl         # all cases
julia --project=. scripts/startup_smoketest.jl full    # one case
```
