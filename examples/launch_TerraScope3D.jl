using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using TerraScope

# Opens an empty project. All files and coordinate systems are selected in the GUI.
TerraScope.launch_viewer(; data_root=joinpath(dirname(@__DIR__), "data"), block=true)
