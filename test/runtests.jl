using Test
using TerraScope

@testset "Voxel volume IO" begin
    values = reshape(collect(1.0:24.0), 3, 4, 2)
    density = ScalarVolume(
        "Density",
        :density,
        values,
        collect(10.0:10.0:30.0),
        collect(100.0:100.0:400.0),
        [-50.0, -100.0],
        "kg/m^3",
        Dict{Symbol, Any}(:source => :test, :value_scale => :linear),
    )
    tmp = tempname() * ".vox"
    save_density_volume(tmp, density)
    loaded = load_density_volume(tmp)
    @test size(loaded.values) == size(density.values)
    @test loaded.kind == :density
    @test isapprox(loaded.values[2, 2, 2], density.values[2, 2, 2]; atol = 1e-8)
end

@testset "Section interpolation" begin
    xv = collect(0.0:10.0:40.0)
    yv = collect(0.0:10.0:40.0)
    zv = -collect(10.0:10.0:30.0)
    values = reshape(collect(1.0:length(xv) * length(yv) * length(zv)), length(xv), length(yv), length(zv))
    X, Y, Z, C, sdist = build_section_surface_polyline(xv, yv, zv, values, [(5.0, 5.0), (35.0, 35.0)]; nsamp = 32)
    @test size(X) == size(C)
    @test size(Y) == size(C)
    @test size(Z) == size(C)
    @test length(sdist) == size(C, 1)
end

@testset "Dataset discovery" begin
    root = mktempdir()
    touch(joinpath(root, "demo.rho"))
    touch(joinpath(root, "demo.dat"))
    touch(joinpath(root, "demo.sgy"))
    touch(joinpath(root, "demo.shp"))
    found = discover_dataset_paths(root)
    @test endswith(found.rho, "demo.rho")
    @test endswith(found.dat, "demo.dat")
    @test length(found.segy_files) == 1
    @test length(found.shapefiles) == 1
end

@testset "ModEM model writer" begin
    tmp = tempname() * ".rho"
    dx = [100.0, 100.0]
    dy = [200.0, 200.0]
    dz = [50.0, 75.0]
    values = reshape([10.0, 20.0, 30.0, 40.0, 50.0, NaN, 70.0, 80.0], 2, 2, 2)
    write_model_modem(tmp, dx, dy, dz, values, [1.0, 2.0, 3.0])
    loaded = load_model_modem(tmp)
    @test loaded.dx == dx
    @test loaded.dy == dy
    @test loaded.dz == dz
    @test isapprox(loaded.A[1, 1, 1], values[1, 1, 1]; rtol = 1e-4)
    @test isnan(loaded.A[2, 1, 2])
end

@testset "ModEM data writer" begin
    data = MTData(
        [1.0],
        [1.0],
        zeros(1, 1),
        zeros(1, 1),
        ["S001"],
        reshape([60.0, 24.0, 100.0], 1, 3),
        1,
        1,
        2,
        ["ZXX", "TX"],
        fill(ComplexF64(NaN, NaN), 1, 4, 1),
        fill(ComplexF64(NaN, NaN), 1, 4, 1),
        fill(NaN, 1, 4, 1),
        fill(NaN, 1, 4, 1),
        fill(NaN, 1, 4, 1),
        fill(NaN, 1, 4, 1),
        fill(ComplexF64(NaN, NaN), 1, 2, 1),
        fill(ComplexF64(NaN, NaN), 1, 2, 1),
        [500.0],
        [600.0],
        [100.0],
        [60.0, 24.0, 0.0],
        "",
        "test.dat",
    )
    data.Z[1, 1, 1] = 1.0 + 2.0im
    data.Zerr[1, 1, 1] = 0.1 + 0.1im
    data.tip[1, 1, 1] = 0.3 + 0.4im
    data.tiperr[1, 1, 1] = 0.05 + 0.05im

    tmp = tempname() * ".dat"
    write_data_modem(tmp, data)
    loaded = load_data_modem(tmp)
    @test loaded.ns == 1
    @test loaded.nf == 1
    @test loaded.site == ["S001"]
    @test loaded.Z[1, 1, 1] == data.Z[1, 1, 1]
    @test loaded.tip[1, 1, 1] == data.tip[1, 1, 1]
end
include("imports.jl")
