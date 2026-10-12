# Faster startup

Why is the first start slow? Julia compiles the code before it runs it. A system image (sysimage)
keeps the compiled code in a file, so Julia does not compile it again.

Build the sysimage one time. This can take 10 minutes or more:

```shell
julia --project=. scripts/build_sysimage.jl
```

Then start TerraScope with the sysimage:

```shell
julia --project=. -J build/TerraScopeSysimage.dll examples/launch_TerraScope3D.jl
```

The `-J` option tells Julia which sysimage to use.

The sysimage removes most of the compile time. It does not remove the time to read files, to set
up the display or to start the graphics. But the startup time becomes shorter and more regular.

Build the sysimage again after you update TerraScope or its packages.

## Windows launcher

On Windows, double-click `Launch-TerraScope.cmd` in the repository folder, or run it from a
terminal:

```shell
Launch-TerraScope.cmd
```

If the sysimage is available, the launcher uses it. If not, the launcher asks you to build it.
