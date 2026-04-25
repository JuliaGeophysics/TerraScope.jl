using Pkg

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(PROJECT_ROOT)

using PackageCompiler

const BUILD_DIR = joinpath(PROJECT_ROOT, "build")
const SYSIMAGE_PATH = joinpath(BUILD_DIR, "TerraScopeSysimage.dll")
const PRECOMPILE_WORKLOAD = joinpath(@__DIR__, "precompile_workload.jl")

mkpath(BUILD_DIR)

PackageCompiler.create_sysimage(
    [:TerraScope, :GLMakie, :CairoMakie, :SegyIO, :Shapefile, :Proj, :FFTW];
    project = PROJECT_ROOT,
    sysimage_path = SYSIMAGE_PATH,
    precompile_execution_file = PRECOMPILE_WORKLOAD,
    incremental = true,
)

println()
println("Built sysimage:")
println("  $(SYSIMAGE_PATH)")
println()
println("Run TerraScope with:")
println("  julia --project=. -J build/TerraScopeSysimage.dll examples/launch_TerraScope3D.jl")