import ArchGDAL

@testset "Coordinate-first transactional imports" begin
    session = ImportSession()
    @test_throws ErrorException import_layer!(session,"missing.xyz",ImportOptions())
    @test_throws ErrorException set_project_crs!(session,"EPSG:4326")
    @test_throws ErrorException set_project_crs!(session,"EPSG:4269")
    @test_throws ErrorException set_project_crs!(session,"EPSG:2227") # US survey feet
    set_project_crs!(session,"EPSG:28354")
    mktempdir() do root
        path = joinpath(root,"points.xyz")
        write(path,"# coordinates\n500000,7700000,-10,100\n500100,7700100,-20,1000\n")
        opts = ImportOptions(source_crs="EPSG:28354",log10_values=true)
        layer = import_layer!(session,path,opts)
        @test layer.data.values == [2,3]
        @test layer.data.x == [500000,500100]
        @test layer.data.z == [-10,-20]
        @test layer.target_crs == "EPSG:28354"
        @test_throws ErrorException set_project_crs!(session,"EPSG:3067")
        @test_throws ErrorException import_layer!(session,path,ImportOptions())
        @test length(session.layers) == 1
        @test !session.busy
        import_layer!(session,path,opts)
        @test length(session.layers) == 2 # same property does not overwrite another layer
        session.busy = true
        @test_throws ErrorException import_layer!(session,path,opts)
        session.busy = false
        write(path,"lat lon depth rho\n-20 141 10 100\n")
        layer = load_import(path,ImportOptions(source_crs="EPSG:4326",columns=(2,1,3,4),
            skip_rows=1,positive_down=true),"EPSG:28354")
        @test isapprox(layer.data.x[1],500000;atol=2)
        @test 7.7e6 < layer.data.y[1] < 7.9e6
        @test layer.data.z == [-10]
        @test_throws ErrorException TerraScope.read_xyz_points(path)
        @test_throws ErrorException TerraScope.read_xyz_points(path;columns=(1,1,2,3))
    end
end

@testset "UBC mesh pairing, compressed widths and cell ordering" begin
    mktempdir() do root
        mesh = joinpath(root,"gravity.MSH")
        model = joinpath(root,"gravity.den")
        write(mesh,"! southwest top origin\n2 2 2\n100 200 50\n2*10\n20 30\n5 15\n")
        write(model,join(1:8,"\n"))
        x,y,z,v = read_ubc_model(model)
        @test x == [105,115]
        @test y == [210,235]
        @test z == [47.5,37.5]
        @test v[:,:,1] == [1 5;3 7]
        @test v[:,:,2] == [2 6;4 8]
        layer = load_import(model,ImportOptions(format=:ubc,source_crs="EPSG:28354",kind=:density,
            nodata=8.0),"EPSG:28354")
        @test isnan(layer.data.values[2,2,2])
        @test layer.data.X[:,1] == x
        @test layer.data.Y[1,:] == y
        write(model,"1\n2\n")
        @test_throws ErrorException read_ubc_model(model)
        write(model,join(1:9,"\n"))
        @test_throws ErrorException read_ubc_model(model)
        write(mesh,"2 2 2\n0 0 0\n2*10\n2*20\n2*-5\n")
        @test_throws ErrorException read_ubc_model(model)
    end
end

@testset "ModEM orientation, log scale and local georeferencing" begin
    mktempdir() do root
        path = joinpath(root,"test.rho")
        values = reshape(Float64.(1:8),2,2,2)
        write_model_modem(path,[10.,20.],[30.,40.],[5.,15.],values,[100.,200.,0.])
        layer = load_import(path,ImportOptions(format=:modem,source_crs="EPSG:28354"),"EPSG:28354")
        @test layer.data.X[:,1] == [215,250]
        @test layer.data.Y[1,:] == [105,120]
        @test layer.data.z == [-2.5,-12.5]
        @test layer.data.values ≈ permutedims(values,(2,1,3)) rtol=1e-4
        write_model_modem(path,[10.,20.],[30.,40.],[5.,15.],values,[0.,0.,0.];rotation=90)
        rotated = load_import(path,ImportOptions(format=:modem,source_crs="EPSG:28354"),"EPSG:28354")
        @test rotated.data.X[1,:] ≈ [5,20]
        @test rotated.data.Y[:,1] ≈ [-15,-50]
        local_layer = load_import(path,ImportOptions(format=:modem,origin_latlon=(-20.,141.)),"EPSG:32754")
        @test 499900 < local_layer.data.X[1,1] < 500100
        @test 7.7e6 < local_layer.data.Y[1,1] < 7.9e6
        dat = joinpath(root,"test.dat")
        write(dat,"# data header\n> Full_Impedance\n> exp(+iwt)\n> units\n> 0\n> -20 141\n> 1 1\n")
        from_header = load_import(path,ImportOptions(format=:modem,data_path=dat),"EPSG:32754")
        @test from_header.data.X == local_layer.data.X
        write(path,"# log10\n1 1 1 0 LOG10\n10\n20\n30\n2\n0 0 0\n0\n")
        @test load_model_modem(path).A[1] == 100
        write(path,"1 1 2 0 LINEAR\n10\n20\n30\n")
        @test_throws ErrorException load_model_modem(path)
    end
end

@testset "Grid reprojection keeps both horizontal coordinates" begin
    trans = TerraScope._xy_transform("EPSG:4326","EPSG:32754")
    X,Y = TerraScope._project_grid([140.,141.],[-21.,-20.],trans)
    @test X[1,1] != X[1,2]
    @test Y[1,1] != Y[2,1]
    for j in 1:2,i in 1:2
        @test (X[i,j],Y[i,j]) == trans([140.,141.][i],[-21.,-20.][j])
    end
    grid = ImportedGrid(X,Y,[-10.,-20.],reshape(Float64.(1:8),2,2,2))
    for axis in (:xy,:xz,:yz)
        x,y,z,c = TerraScope._grid_slice(grid,axis,0.5)
        @test size(x) == size(y) == size(z) == size(c) == (2,2)
    end
end

@testset "Seismic loader compatibility" begin
    @test TerraScope._segy_scalar_factor(0) == 1
    @test TerraScope._segy_scalar_factor(-100) == 0.01
    header = (RecSourceScalar=-10,SourceX=100,SourceY=200,GroupX=300,GroupY=400)
    @test TerraScope._extract_trace_xy(header) == (10,20)
    @test TerraScope._extract_trace_xy(header;pref=:group) == (30,40)
    wave = repeat(reshape(cos.(2pi .* (0:63) ./ 16),1,:),3,1)
    @test TerraScope.compute_seismic_envelope(wave) ≈ ones(3,64) atol=1e-12
    @test maximum(abs,TerraScope._normalize_amplitude(wave)) <= 1
end

@testset "SEG-Y file import and coordinate conversion" begin
    mktempdir() do root
        path = joinpath(root,"section.sgy")
        block = TerraScope.SegyIO.SeisBlock(reshape(Float32.(1:48),8,6))
        TerraScope.SegyIO.set_header!(block,:SourceX,500000)
        TerraScope.SegyIO.set_header!(block,:SourceY,7700000)
        TerraScope.SegyIO.set_header!(block,:RecSourceScalar,1)
        TerraScope.SegyIO.segy_write(path,block)
        for mode in (:original,:envelope)
            opts = ImportOptions(format=:seismic,source_crs="EPSG:28354",display_mode=mode,
                max_traces=3,max_samples=4,sample_spacing_m=10.,top_z_m=5.)
            layer = load_import(path,opts,"EPSG:32754")
            @test size(layer.data.C) == (3,4)
            @test layer.data.Z[1,1] == -5
            @test layer.data.Z[1,end] == -75 # spacing refers to original sample index
            @test all(isfinite,layer.data.C)
            xy = TerraScope._xy_transform("EPSG:28354","EPSG:32754")(500000,7700000)
            @test layer.data.X[1,1] == xy[1]
            @test layer.data.Y[1,1] == xy[2]
        end
        @test_throws ErrorException TerraScope.load_seismic_curtain_from_segy(path;max_samples=0)
        @test_throws ErrorException TerraScope.load_seismic_curtain_from_segy(path;display_mode=:invalid)
    end
end

@testset "Shapefile point and line reprojection" begin
    mktempdir() do root
        shp = joinpath(root,"station.shp")
        TerraScope.Shapefile.write(shp,TerraScope.Shapefile.Point(141.,-20.))
        layer = load_import(shp,ImportOptions(format=:shapefile,source_crs="EPSG:4326"),"EPSG:32754")
        @test length(layer.data) == 1
        @test isapprox(layer.data[1][1][1],500000;atol=1e-6)
        @test_throws ErrorException load_import(shp,ImportOptions(format=:shapefile),"EPSG:32754")
    end
end

@testset "Raster import honours pixel centres, CRS and NoData" begin
    mktempdir() do root
        path = joinpath(root,"grid.tif")
        ArchGDAL.create(path;driver=ArchGDAL.getdriver("GTiff"),width=2,height=2,
            nbands=1,dtype=Float64) do ds
            ArchGDAL.setgeotransform!(ds,[140.,0.1,0.,-20.,0.,-0.1])
            ArchGDAL.importEPSG(4326) do crs
                ArchGDAL.setproj!(ds,ArchGDAL.toWKT(crs))
            end
            band = ArchGDAL.getband(ds,1)
            ArchGDAL.setnodatavalue!(band,-999.)
            ArchGDAL.write!(band,[1. 2.;3. -999.])
        end
        layer = load_import(path,ImportOptions(format=:raster,kind=:scalar,top_z_m=100.),"EPSG:32754")
        expected = TerraScope._xy_transform("EPSG:4326","EPSG:32754")(140.05,-20.05)
        @test layer.data.X[1,1] ≈ expected[1]
        @test layer.data.Y[1,1] ≈ expected[2]
        @test layer.data.z == [100.]
        @test isnan(layer.data.values[2,2,1])
    end
end

@testset "Import GUI callbacks without a display" begin
    TerraScope.CairoMakie.activate!()
    viewer = launch_viewer(;display_window=false,block=false)
    @test isempty(viewer.session.layers)
    viewer.controls.import_button.clicks[] += 1
    @test isempty(viewer.session.target_crs)
    TerraScope._set_import_text!(viewer.controls.crs_box,"EPSG:28354")
    viewer.controls.set_crs.clicks[] += 1
    @test viewer.session.target_crs == "EPSG:28354"
    mktempdir() do root
        path = joinpath(root,"model.xyz")
        write(path,"500000 7700000 -10 100\n500100 7700100 -20 200\n")
        dialog = TerraScope._open_import_dialog(viewer.session,viewer.add_layer_to_scene!;display_window=false)
        dialog.controls.format_menu.i_selected[] = 2
        TerraScope._set_import_text!(dialog.controls.path_box,path)
        TerraScope._set_import_text!(dialog.controls.source_box,"EPSG:28354")
        dialog.controls.load_button.clicks[] += 1
        @test timedwait(()->!dialog.loading[],120) == :ok
        @test length(viewer.session.layers) == 1
        @test length(viewer.plots) == 1
        @test startswith(dialog.status[],"Imported")
        oldplot = only(viewer.plots[1])
        viewer.controls.visible_button.clicks[] += 1
        @test !oldplot.visible[]
        viewer.controls.visible_button.clicks[] += 1
        @test oldplot.visible[]
        # A failed import must retain the first layer and its plot.
        TerraScope._set_import_text!(dialog.controls.path_box,joinpath(root,"missing.xyz"))
        dialog.controls.load_button.clicks[] += 1
        @test timedwait(()->!dialog.loading[],30) == :ok
        @test length(viewer.session.layers) == 1
        @test only(viewer.plots[1]) === oldplot
        @test startswith(dialog.status[],"Import failed")
        rho = joinpath(root,"grid.rho")
        write_model_modem(rho,fill(100.,2),fill(100.,2),fill(50.,2),reshape(Float64.(1:8),2,2,2),[7700000.,500000.,0.])
        layer = import_layer!(viewer.session,rho,ImportOptions(format=:modem,source_crs="EPSG:28354"))
        viewer.add_layer_to_scene!(layer)
        @test length(viewer.plots) == 2
        viewer.controls.slice_axis.i_selected[] = 2
        viewer.controls.apply_slice.clicks[] += 1
        @test only(viewer.plots[1]) === oldplot # Only active layer redraws.
    end
end

@testset "Malformed CSV does not shift coordinate columns" begin
    mktemp() do path,io
        write(io,"1,,2,3,4\n")
        close(io)
        @test_throws ErrorException read_xyz_points(path)
    end
end
