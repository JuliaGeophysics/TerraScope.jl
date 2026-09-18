using Pkg
Pkg.activate(normpath(joinpath(@__DIR__, "..")))
using TerraScope

# Compile import paths without requiring a user's dataset or seismic files.
mktempdir() do root
    session = ImportSession()
    set_project_crs!(session,"EPSG:28354")
    xyz = joinpath(root,"example.xyz")
    write(xyz,"500000 7700000 -10 100\n500100 7700100 -20 200\n")
    import_layer!(session,xyz,ImportOptions(source_crs="EPSG:28354"))
    rho = joinpath(root,"example.rho")
    write_model_modem(rho,fill(100.,2),fill(100.,2),fill(50.,2),fill(100.,2,2,2),[0.,0.,0.])
    import_layer!(session,rho,ImportOptions(format=:modem,origin_latlon=(-20.,141.)))
    write(joinpath(root,"example.msh"),"2 2 2\n500000 7700000 0\n2*100\n2*100\n2*50\n")
    ubc = joinpath(root,"example.den")
    write(ubc,join(1:8,"\n"))
    import_layer!(session,ubc,ImportOptions(format=:ubc,source_crs="EPSG:28354",kind=:density))
end
println("TerraScope import precompile workload completed.")
