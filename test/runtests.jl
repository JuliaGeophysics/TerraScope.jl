using Test
using TerraScope

@testset "Synthetic density" begin
    model = MTModel(
        fill(100.0, 6, 6, 4),
        fill(100.0, 6),
        fill(100.0, 6),
        fill(50.0, 4),
        6,
        6,
        4,
        collect(0.0:100.0:600.0),
        collect(0.0:100.0:600.0),
        collect(0.0:50.0:200.0),
        [0.0, 0.0, 0.0],
        collect(50.0:100.0:550.0),
        collect(50.0:100.0:550.0),
        collect(25.0:50.0:175.0),
        zeros(7, 7),
        zeros(7, 7),
        zeros(6, 6),
        zeros(6, 6),
        zeros(6, 6),
        (1, 1),
        "synthetic.rho",
        "",
    )
    density = generate_synthetic_density(model)
    @test density.kind == :density
    @test size(density.values) == (4, 4, 4)
    tmp = tempname() * ".vox"
    save_density_volume(tmp, density)
    loaded = load_density_volume(tmp)
    @test size(loaded.values) == size(density.values)
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