mutable struct MTModel
    A::Array{Float64, 3}
    dx::Vector{Float64}
    dy::Vector{Float64}
    dz::Vector{Float64}
    nx::Int
    ny::Int
    nz::Int
    x::Vector{Float64}
    y::Vector{Float64}
    z::Vector{Float64}
    origin::Vector{Float64}
    cx::Vector{Float64}
    cy::Vector{Float64}
    cz::Vector{Float64}
    X::Matrix{Float64}
    Y::Matrix{Float64}
    Xc::Matrix{Float64}
    Yc::Matrix{Float64}
    Z::Matrix{Float64}
    npad::NTuple{2, Int}
    name::String
    niter::String
end

mutable struct MTData
    T::Vector{Float64}
    f::Vector{Float64}
    zrot::Matrix{Float64}
    trot::Matrix{Float64}
    site::Vector{String}
    loc::Matrix{Float64}
    ns::Int
    nf::Int
    nr::Int
    responses::Vector{String}
    Z::Array{ComplexF64, 3}
    Zerr::Array{ComplexF64, 3}
    rho::Array{Float64, 3}
    rhoerr::Array{Float64, 3}
    phi::Array{Float64, 3}
    phierr::Array{Float64, 3}
    tip::Array{ComplexF64, 3}
    tiperr::Array{ComplexF64, 3}
    x::Vector{Float64}
    y::Vector{Float64}
    z::Vector{Float64}
    origin::Vector{Float64}
    niter::String
    name::String
end

struct ScalarVolume
    name::String
    kind::Symbol
    values::Array{Float64, 3}
    x::Vector{Float64}
    y::Vector{Float64}
    z::Vector{Float64}
    units::String
    metadata::Dict{Symbol, Any}
end

struct DatasetBundle
    root::String
    model::Union{Nothing, MTModel}
    data::Union{Nothing, MTData}
    resistivity::Union{Nothing, ScalarVolume}
    density::Union{Nothing, ScalarVolume}
    shapefiles::Vector{String}
    segy_files::Vector{String}
end