module TerraScope

using CairoMakie
using Dates
using DelimitedFiles
using FFTW
using GLMakie
using GeoInterface
using LinearAlgebra
using Printf
using Proj
using SegyIO
using Shapefile
using Statistics

include("Types.jl")
include("ModelIO.jl")
include("Geometry.jl")
include("SyntheticDensity.jl")
include("DataIO.jl")
include("GeoOverlay.jl")
include("Seismic.jl")
include("Viewer.jl")

export MTModel
export MTData
export ScalarVolume
export DatasetBundle
export default_data_dir
export discover_dataset_paths
export load_model_modem
export load_data_modem
export volume_from_model
export build_section_surface_polyline
export generate_synthetic_density
export save_density_volume
export load_density_volume
export load_dataset_bundle
export launch_viewer

end