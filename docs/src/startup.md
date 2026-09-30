# Faster startup

To remove most of the first-run compilation before a demo, build a custom sysimage once and launch
TerraScope with it:

```shell
julia --project=. scripts/build_sysimage.jl
julia --project=. -J build/TerraScopeSysimage.dll examples/launch_TerraScope3D.jl
```

This does not eliminate file I/O, Windows display setup or GL context creation, but it substantially
reduces Julia compilation and makes startup more consistent across runs.

## Windows launcher

On Windows, run the launcher in the repository root:

```shell
Launch-TerraScope.cmd
```

It uses the sysimage automatically when it exists and offers to build it the first time.
