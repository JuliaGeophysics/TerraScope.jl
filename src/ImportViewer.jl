_set_import_text!(box, text) = CairoMakie.Makie.set!(box, isempty(text) ? " " : String(text))

# The viewer opens on an empty dark canvas: nothing is read from disk until Import is
# pressed. Labels and widget text stay light so the toolbar remains legible on it.
const SCENE_BACKGROUND = RGBf(0.05,0.05,0.06)
const PANEL_COLOR = RGBf(0.09,0.09,0.11)
const GRID_COLOR = RGBf(0.25,0.25,0.28)
const FOREGROUND = RGBf(0.85,0.86,0.88)
const WIDGET_COLOR = RGBf(0.96,0.96,0.96)

# Detected CRSs can be full PROJ strings; keep the status line one line long.
_crs_label(crs) = length(crs) > 46 ? first(crs,43) * "..." : crs

# Makie only splits label/value for two-element tuples; `Pair` options would be shown
# and returned whole, so every menu here uses ("label", value) tuples.
const IMPORT_FORMATS = [("ModEM resistivity (.rho)",:modem),
    ("XYZ / CSV point model (.xyz, .dat, .csv)",:xyz),
    ("UBC3D tensor model + mesh",:ubc), ("TerraScope voxel (.vox)",:voxel),
    ("Shapefile (.shp)",:shapefile), ("Seismic section (SEG-Y)",:seismic),
    ("Raster grid (GeoTIFF / NetCDF)",:raster)]

# A directory is listed only when the user opens/navigates this chooser.
function _choose_import_file!(textbox; start_dir=pwd())
    fig = Figure(size=(850,300))
    Label(fig[1,1:2],"Choose a file or paste its full path in the import window")
    directory = Textbox(fig[2,1],stored_string=abspath(start_dir),width=660)
    refresh = Button(fig[2,2],label="Open folder")
    entries = Menu(fig[3,1:2],options=[("Choose…","")],width=760)
    status = Observable("")
    Label(fig[4,1:2],status,tellwidth=false)
    function list_directory(path)
        try
            folder = abspath(expanduser(path))
            choices = Tuple{String,String}[("Choose…",""), ("../",dirname(folder))]
            for entry in sort(readdir(folder;join=true);by=p->(!isdir(p),lowercase(basename(p))))
                push!(choices,(isdir(entry) ? basename(entry)*"/" : basename(entry), entry))
            end
            _set_import_text!(directory,folder)
            entries.options[] = choices
            entries.i_selected[] = 1
            status[] = "$(length(choices)-2) entries"
        catch err
            status[] = sprint(showerror,err)
        end
    end
    on(refresh.clicks) do _
        list_directory(directory.displayed_string[])
    end
    on(entries.selection) do path
        (isnothing(path) || isempty(path)) && return
        if isdir(path)
            list_directory(path)
        else
            _set_import_text!(textbox,path)
            status[] = "Selected $(basename(path)); return to the import window."
        end
    end
    list_directory(start_dir)
    return _display_figure(fig)
end

function _import_fields(format)
    format == :modem && return [
        (:data,"Optional ModEM data file (origin header)",""),
        (:latitude,"Local origin latitude (blank for absolute CRS)",""),
        (:longitude,"Local origin longitude",""),
        (:padding,"Horizontal padding: keep / trim","trim"),
        (:maxdepth,"Maximum depth (m; blank: all)","50000"),
        (:nodata,"NoData value (optional)","")]
    format == :xyz && return [(:columns,"X,Y,Z,value columns","1,2,3,4"),
        (:skip,"Header rows to skip","0"),(:zdown,"Z convention: elevation / depth","elevation"),
        (:nodata,"NoData value (optional)","")]
    format == :ubc && return [(:mesh,"Mesh file (blank: same-name .msh/.mesh)",""),
        (:nodata,"NoData / inactive value (optional)","")]
    format == :seismic && return [(:trace,"Trace coordinates: source / group","source"),
        (:mode,"Display: original / envelope","envelope"),
        (:spacing,"Depth spacing per original sample (m)","12.5"),
        (:top,"Top depth below datum (m)","0"),(:traces,"Maximum displayed traces","1400"),
        (:samples,"Maximum displayed samples","1200")]
    format == :raster && return [(:top,"Elevation of raster plane (m)","0"),
        (:nodata,"Additional NoData value (optional)","")]
    format == :voxel && return [(:nodata,"NoData value (optional)","")]
    return Tuple{Symbol,String,String}[]
end

function _open_import_dialog(session, on_loaded; start_dir=pwd(), display_window=true)
    fig = Figure(size=(1000,780))
    Label(fig[1,1:3],"Import into $(session.target_crs)",fontsize=20)
    Label(fig[2,1],"Format")
    format_menu = Menu(fig[2,2:3],options=IMPORT_FORMATS)
    Label(fig[3,1],"File")
    path_box = Textbox(fig[3,2],stored_string=" ",width=570)
    browse = Button(fig[3,3],label="Browse…")
    Label(fig[4,1],"Source CRS")
    source_box = Textbox(fig[4,2:3],stored_string=" ",placeholder="EPSG code or PROJ string",width=680)
    Label(fig[5,1:3],"Leave blank to detect it: lon/lat is recognised from the coordinates themselves, and a .prj, raster header or ModEM local origin is read from the file.",fontsize=12)
    Label(fig[6,1],"Property")
    property_menu = Menu(fig[6,2],options=[("Resistivity",:resistivity),("Density / gravity",:density),
        ("Susceptibility",:susceptibility),("Other scalar",:scalar)])
    units_box = Textbox(fig[6,3],stored_string="ohm m",width=130)
    Label(fig[7,1],"Value display")
    scale_menu = Menu(fig[7,2:3],options=[("Linear",false),("log10 (positive values only)",true)])
    fields = [_import_fields(:modem)...]
    labels = [Label(fig[7+i,1],"",halign=:left,fontsize=12) for i in 1:6]
    boxes = [Textbox(fig[7+i,2:3],stored_string=" ",width=680) for i in 1:6]
    function update_fields(format)
        empty!(fields)
        append!(fields,_import_fields(format))
        for i in 1:6
            enabled = i <= length(fields)
            labels[i].blockscene.visible[] = enabled
            boxes[i].blockscene.visible[] = enabled
            rowsize!(fig.layout,7+i,Fixed(enabled ? 36 : 0))
            if enabled
                labels[i].text[] = fields[i][2]
                _set_import_text!(boxes[i],fields[i][3])
            end
        end
    end
    update_fields(:modem)
    on(format_menu.selection) do format
        isnothing(format) || update_fields(format)
    end
    on(property_menu.selection) do kind
        _set_import_text!(units_box,kind == :resistivity ? "ohm m" : kind == :density ? "g/cm³" : kind == :susceptibility ? "SI" : "")
    end
    on(browse.clicks) do _
        _choose_import_file!(path_box;start_dir=start_dir)
    end
    status = Observable("One file per load. Z uses metres in a shared vertical datum; horizontal CRS conversion does not change that datum.")
    Label(fig[14,1:3],status,fontsize=12,tellwidth=false)
    load_button = Button(fig[15,1:3],label="Load layer")
    loading = Ref(false)
    on(load_button.clicks) do _
        loading[] && return
        loading[] = true
        load_button.label[] = "Loading…"
        status[] = "Reading and converting this layer…"
        # One cooperative task keeps GL mutations on the UI thread. No background
        # reloads, speculative reads, or concurrent imports are started.
        @async try
            yield()
            values = Dict(fields[i][1]=>strip(boxes[i].displayed_string[]) for i in eachindex(fields))
            field(key,default="") = get(values,key,default)
            number(key,default) = parse(Float64,field(key,string(default)))
            latlon = if isempty(field(:latitude)) && isempty(field(:longitude))
                nothing
            else
                (number(:latitude,0),number(:longitude,0))
            end
            cols = Tuple(parse.(Int,split(field(:columns,"1,2,3,4"),',')))
            length(cols) == 4 || error("Specify exactly four XYZ column numbers.")
            zmode = lowercase(field(:zdown,"elevation"))
            zmode in ("elevation","depth") || error("Z convention must be elevation or depth.")
            field(:padding,"keep") in ("keep","trim") || error("Padding must be keep or trim.")
            opts = ImportOptions(format=format_menu.selection[],source_crs=strip(source_box.displayed_string[]),
                kind=property_menu.selection[],units=strip(units_box.displayed_string[]),
                log10_values=scale_menu.selection[],mesh_path=expanduser(field(:mesh)),
                data_path=expanduser(field(:data)),origin_latlon=latlon,columns=cols,
                trim_padding=field(:padding,"keep") == "trim",
                max_depth_m=isempty(field(:maxdepth)) ? nothing : number(:maxdepth,0),
                skip_rows=parse(Int,field(:skip,"0")),positive_down=zmode == "depth",
                nodata=isempty(field(:nodata)) ? nothing : number(:nodata,0),
                trace_xy=Symbol(field(:trace,"source")),display_mode=Symbol(field(:mode,"original")),
                sample_spacing_m=number(:spacing,12.5),top_z_m=number(:top,0),
                max_traces=parse(Int,field(:traces,"1400")),max_samples=parse(Int,field(:samples,"1200")))
            path = expanduser(strip(path_box.displayed_string[]))
            layer = import_layer!(session,path,opts)
            try
                on_loaded(layer)
            catch
                pop!(session.layers)
                rethrow()
            end
            status[] = "Imported $(layer.name) from $(_crs_label(layer.source_crs)). Choose another file to add another layer."
        catch err
            status[] = "Import failed: $(sprint(showerror,err))"
        finally
            loading[] = false
            load_button.label[] = "Load layer"
        end
    end
    screen = display_window ? _display_figure(fig) : nothing
    return display_window ? screen : (;figure=fig,controls=(;format_menu,path_box,source_box,property_menu,
        units_box,scale_menu,boxes,load_button),status,loading)
end

# Bound GPU geometry independently of source size. Full-resolution imported values
# stay available in the session; changing slices never rereads or reprojects files.
function _grid_slice(grid::ImportedGrid, axis::Symbol, fraction; max_side=400)
    nx,ny,nz = size(grid.values)
    inds(n) = unique(round.(Int,range(1,n;length=min(n,max_side))))
    ix,iy,iz = inds(nx),inds(ny),inds(nz)
    if axis == :xy
        k = clamp(1+round(Int,fraction*(nz-1)),1,nz)
        return grid.X[ix,iy],grid.Y[ix,iy],fill(grid.z[k],length(ix),length(iy)),grid.values[ix,iy,k]
    elseif axis == :xz
        j = clamp(1+round(Int,fraction*(ny-1)),1,ny)
        return repeat(grid.X[ix,j],1,length(iz)),repeat(grid.Y[ix,j],1,length(iz)),
            repeat(reshape(grid.z[iz],1,:),length(ix),1),grid.values[ix,j,iz]
    else
        i = clamp(1+round(Int,fraction*(nx-1)),1,nx)
        return repeat(grid.X[i,iy],1,length(iz)),repeat(grid.Y[i,iy],1,length(iz)),
            repeat(reshape(grid.z[iz],1,:),length(iy),1),grid.values[i,iy,iz]
    end
end

"""Open an empty project. Choose a metric project CRS, then import layers individually."""
# Thin wrapper: load the backend first, then run the whole viewer body in the new
# world so that `wait(screen)` and `isopen(screen)` see GLMakie's methods.
function launch_import_viewer(; display_window=true, kwargs...)
    display_window && _ensure_glmakie()
    return Base.invokelatest(_launch_import_viewer; display_window, kwargs...)
end

function _launch_import_viewer(; open_fullscreen=false, block=!isinteractive(), data_root=pwd(), display_window=true, default_crs="")
    session = ImportSession()
    fig = Figure(size=(1550,960),backgroundcolor=SCENE_BACKGROUND)
    status = Observable("Choose a project coordinate system before importing any data.")
    # The 3D view owns the window. Import and the project CRS ride in a corner overlay
    # on top of it, so no second viewing panel competes with the scene.
    ax = Axis3(fig[1,1],xlabel="Easting (m)",ylabel="Northing (m)",zlabel="Elevation (m)",aspect=:data,
        backgroundcolor=SCENE_BACKGROUND,xypanelcolor=PANEL_COLOR,xzpanelcolor=PANEL_COLOR,yzpanelcolor=PANEL_COLOR,
        xgridcolor=GRID_COLOR,ygridcolor=GRID_COLOR,zgridcolor=GRID_COLOR,
        xlabelcolor=FOREGROUND,ylabelcolor=FOREGROUND,zlabelcolor=FOREGROUND,
        xticklabelcolor=FOREGROUND,yticklabelcolor=FOREGROUND,zticklabelcolor=FOREGROUND,
        xspinecolor_1=GRID_COLOR,yspinecolor_1=GRID_COLOR,zspinecolor_1=GRID_COLOR,
        xspinecolor_2=GRID_COLOR,yspinecolor_2=GRID_COLOR,zspinecolor_2=GRID_COLOR,
        xspinecolor_3=GRID_COLOR,yspinecolor_3=GRID_COLOR,zspinecolor_3=GRID_COLOR)
    corner = GridLayout(fig[1,1],tellwidth=false,tellheight=false,halign=:right,valign=:top)
    import_button = Button(corner[1,1:2],label="Import…",width=248)
    crs_box = Textbox(corner[2,1],stored_string=" ",placeholder="Project CRS",width=160,
        boxcolor=WIDGET_COLOR,boxcolor_hover=WIDGET_COLOR,boxcolor_focused=:white,bordercolor=GRID_COLOR)
    set_crs = Button(corner[2,2],label="Use CRS",width=84)
    presets = Menu(corner[3,1:2],options=[("Coordinate system…",""),
        ("ETRS89 / TM35FIN (Finland)","EPSG:3067"), ("GDA94 / MGA 54 (Cloncurry)","EPSG:28354"),
        ("GDA2020 / MGA 54","EPSG:7854"), ("WGS84 / UTM 54S","EPSG:32754")],width=248)
    controls = fig[2,1] = GridLayout()
    layer_menu = Menu(controls[1,1],options=[("No layers",0)],width=360)
    visible_button = Button(controls[1,2],label="Hide layer")
    slice_axis = Menu(controls[1,3],options=[("Horizontal slice",:xy),("X section",:xz),("Y section",:yz)])
    slice_slider = Slider(controls[1,4],range=0:0.01:1,startvalue=0.5,width=230)
    apply_slice = Button(controls[1,5],label="Apply slice")
    fit = Button(controls[1,6],label="Fit view")
    Label(fig[3,1],status,tellwidth=false,halign=:left,color=FOREGROUND)
    colorbar = Colorbar(fig[1,2],limits=(0.0,1.0),colormap=:viridis,label="",
        labelcolor=FOREGROUND,ticklabelcolor=FOREGROUND,tickcolor=FOREGROUND,topspinecolor=GRID_COLOR,
        bottomspinecolor=GRID_COLOR,leftspinecolor=GRID_COLOR,rightspinecolor=GRID_COLOR)
    # The scene takes the window; the control strip and status line stay thin.
    rowsize!(fig.layout,1,Relative(0.92))
    rowsize!(fig.layout,2,Fixed(42))
    rowsize!(fig.layout,3,Fixed(24))
    colsize!(fig.layout,1,Relative(0.965))
    colsize!(fig.layout,2,Relative(0.035))
    rowgap!(fig.layout,6)
    plots = Vector{Vector{Any}}()
    visible = Bool[]
    slices = Tuple{Symbol,Float64}[]
    import_screen = Ref{Any}(nothing)
    cmap(layer) = layer.kind == :resistivity ? :Spectral : :viridis
    function draw_layer(layer, axis=:xy, fraction=0.5)
        result = Any[]
        d = layer.data
        try
            if d isa ImportedGrid
                X,Y,Z,C = _grid_slice(d,axis,fraction)
                if min(size(C)...) >= 2
                    push!(result,surface!(ax,X,Y,Z;color=C,colormap=cmap(layer),colorrange=layer.colorrange,shading=NoShading))
                else
                    push!(result,scatter!(ax,vec(X),vec(Y),vec(Z);color=vec(C),colormap=cmap(layer),colorrange=layer.colorrange,markersize=4))
                end
            elseif d isa ImportedPoints
                step = max(1,cld(length(d.values),200_000))
                inds = 1:step:length(d.values)
                push!(result,scatter!(ax,d.x[inds],d.y[inds],d.z[inds];color=d.values[inds],
                    colormap=cmap(layer),colorrange=layer.colorrange,markersize=3))
            elseif layer.format == :shapefile
                x,y = Float64[],Float64[]
                px,py = Float64[],Float64[]
                for segment in d
                    if length(segment) == 1
                        push!(px,segment[1][1]); push!(py,segment[1][2])
                        continue
                    end
                    append!(x,first.(segment)); push!(x,NaN)
                    append!(y,last.(segment)); push!(y,NaN)
                end
                isempty(x) || push!(result,lines!(ax,x,y,zeros(length(x));color=:black,linewidth=1.5))
                isempty(px) || push!(result,scatter!(ax,px,py,zeros(length(px));color=:black,markersize=7))
            elseif layer.format == :seismic
                push!(result,surface!(ax,d.X,d.Y,d.Z;color=d.C,colormap=:grays,
                    colorrange=(-1,1),shading=NoShading))
            end
        catch
            foreach(p->delete!(ax,p),result)
            rethrow()
        end
        return result
    end
    function select_layer(index)
        index == 0 && return
        layer = session.layers[index]
        colorbar.limits[] = Float64.(layer.colorrange)
        colorbar.colormap[] = cmap(layer)
        colorbar.label[] = "$(layer.log10_values ? "log10 " : "")$(layer.kind) ($(layer.units))"
        visible_button.label[] = visible[index] ? "Hide layer" : "Show layer"
        status[] = "$(length(session.layers)) layers | $(layer.name) | Project: $(session.target_crs)"
    end
    function add_layer_to_scene!(layer)
        newplots = draw_layer(layer)
        push!(plots,newplots); push!(visible,true); push!(slices,(:xy,0.5))
        layer_menu.options[] = [("$i: $(l.name)",i) for (i,l) in enumerate(session.layers)]
        layer_menu.i_selected[] = length(session.layers)
        select_layer(length(session.layers))
        autolimits!(ax)
    end
    on(presets.selection) do crs
        isnothing(crs) || _set_import_text!(crs_box,crs)
    end
    if !isempty(strip(default_crs))
        _set_import_text!(crs_box,default_crs)
        try
            set_project_crs!(session,strip(default_crs))
            status[] = "Project: $(session.target_crs). Use Import to add a model or overlay."
        catch err
            status[] = sprint(showerror,err)
        end
    end
    on(set_crs.clicks) do _
        try
            import_screen[] !== nothing && isopen(import_screen[]) && error("Close the import window before changing the project CRS.")
            set_project_crs!(session,crs_box.displayed_string[])
            status[] = "Project: $(session.target_crs). Use Import to add a model or overlay."
        catch err
            status[] = sprint(showerror,err)
        end
    end
    on(import_button.clicks) do _
        if isempty(session.target_crs)
            status[] = "Choose and confirm the project coordinate system first."
            return
        end
        # Reuse the existing dialog rather than creating duplicate import callbacks.
        if import_screen[] !== nothing && isopen(import_screen[])
            status[] = "The import window is already open."
            return
        end
        import_screen[] = _open_import_dialog(session,add_layer_to_scene!;
            start_dir=isdir(data_root) ? data_root : pwd())
    end
    on(layer_menu.selection) do i
        isnothing(i) || select_layer(i)
    end
    on(visible_button.clicks) do _
        i = layer_menu.selection[]
        i == 0 && return
        visible[i] = !visible[i]
        foreach(p->(p.visible[]=visible[i]),plots[i])
        select_layer(i)
    end
    on(apply_slice.clicks) do _
        i = layer_menu.selection[]
        i == 0 && return
        session.layers[i].data isa ImportedGrid || return
        requested = (slice_axis.selection[],Float64(slice_slider.value[]))
        requested == slices[i] && return
        newplots = draw_layer(session.layers[i],requested...)
        foreach(p->(p.visible[]=visible[i]),newplots)
        foreach(p->delete!(ax,p),plots[i])
        plots[i] = newplots
        slices[i] = requested
    end
    on(fit.clicks) do _
        autolimits!(ax)
    end
    screen = display_window ? _display_figure(fig;fullscreen=open_fullscreen) : nothing
    block && !isnothing(screen) && wait(screen)
    return (;figure=fig,screen,session,controls=(;crs_box,set_crs,import_button,layer_menu,visible_button,slice_axis,slice_slider,apply_slice),draw_layer,add_layer_to_scene!,plots,status)
end
