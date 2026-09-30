# Demo data

[`scripts/generate_synthetic_data.jl`](https://github.com/JuliaGeophysics/TerraScope.jl/blob/main/scripts/generate_synthetic_data.jl)
writes four WGS84 lon/lat point files into `Data/demo`, derived from the demo ModEM mesh:

```shell
julia --project=. scripts/generate_synthetic_data.jl
```

None of them states a CRS, so loading them exercises the [source CRS detection](inputs.md#source-crs-detection).

| File | Launcher input | Units | Records |
| --- | --- | --- | --- |
| `density.xyz` | `gravity_model` | kg/m³ | 37,044 |
| `susceptibility.xyz` | `magnetic_model` | SI | 37,044 |
| `gravity.xyz` | `gravity_data` | mGal | 7,056 |
| `magnetic.xyz` | `magnetic_data` | nT | 7,056 |

The two surveys are depth-weighted column integrals of the matching 3D model. They are good enough to
look like data flown over the same bodies, but not a rigorous forward calculation.

## Smoke test

A headless check that every launcher configuration builds a scene against the demo data:

```shell
julia --project=. scripts/startup_smoketest.jl         # every case
julia --project=. scripts/startup_smoketest.jl full    # one case
```
