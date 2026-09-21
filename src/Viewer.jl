function _volume_display_range(volume::ScalarVolume)
    return compute_colorrange(volume.values)
end

function _volume_colormap(volume::ScalarVolume)
    return volume.kind == :density ? :viridis : :Spectral
end

function _colorbar_label(volume::ScalarVolume)
    if volume.kind == :density
        return "Density (kg/m^3)"
    end
    return get(volume.metadata, :value_scale, :linear) == :log10 ? "log10 rho (ohm m)" : "rho (ohm m)"
end

function _physical_to_internal(volume::ScalarVolume, value::Real)
    if get(volume.metadata, :value_scale, :linear) == :log10
        return log10(max(Float64(value), eps(Float64)))
    end
    return Float64(value)
end

function _internal_to_physical(volume::ScalarVolume, value::Real)
    if get(volume.metadata, :value_scale, :linear) == :log10
        return 10.0^Float64(value)
    end
    return Float64(value)
end

function _draw_box!(ax, volume::ScalarVolume)
    xmin, xmax = extrema(volume.x)
    ymin, ymax = extrema(volume.y)
    zmin, zmax = extrema(volume.z)
    lines!(ax, [xmin, xmax, xmax, xmin, xmin], [ymin, ymin, ymax, ymax, ymin], fill(zmax, 5); color = :gray70, linewidth = 1.0)
    lines!(ax, [xmin, xmax, xmax, xmin, xmin], [ymin, ymin, ymax, ymax, ymin], fill(zmin, 5); color = :gray70, linewidth = 1.0)
    for (x0, y0) in ((xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax))
        lines!(ax, [x0, x0], [y0, y0], [zmin, zmax]; color = :gray70, linewidth = 1.0)
    end
end

function _fit_camera!(scene, volume::ScalarVolume)
    xmin, xmax = extrema(volume.x)
    ymin, ymax = extrema(volume.y)
    zmin, zmax = extrema(volume.z)
    center = Vec3f((xmin + xmax) / 2, (ymin + ymax) / 2, (zmin + zmax) / 2)
    span = Float32(max(xmax - xmin, ymax - ymin))
    zspan = Float32(zmax - zmin)
    eye = center + Vec3f(-1.1f0 * span, -0.85f0 * span, max(0.7f0 * span, 1.2f0 * zspan))
    update_cam!(scene, eye, center, Vec3f(0, 0, 1))
end

function _export_sections(volume::ScalarVolume, section_paths::Vector{Vector{Tuple{Float64, Float64}}}, out_dir::AbstractString; max_depth_m::Union{Nothing, Real} = nothing)
    mkpath(out_dir)
    exported = String[]
    zvals = volume.z
    keep = if isnothing(max_depth_m)
        trues(length(zvals))
    else
        (-zvals) .<= Float64(max_depth_m)
    end
    any(keep) || (keep .= true)
    zsub = zvals[keep]
    for (idx, path) in enumerate(section_paths)
        X, _, Z, C, sdist = build_section_surface_polyline(volume.x, volume.y, volume.z, volume.values, path; nsamp = 260)
        fig = CairoMakie.Figure(size = (1100, 500))
        ax = CairoMakie.Axis(fig[1, 1], xlabel = "Distance (m)", ylabel = "Depth (m)", title = "Section $idx")
        heatmap!(ax, sdist, -zsub, permutedims(C[:, keep], (2, 1)); colormap = _volume_colormap(volume), colorrange = _volume_display_range(volume))
        out = joinpath(out_dir, @sprintf("section_%02d.png", idx))
        save(out, fig)
        push!(exported, out)
    end
    return exported
end

const _TERRASCOPE_LOGO = raw"""
▄▄▄▄▄▄▄▄▄                       ▄▄▄▄▄▄▄                         
▀▀▀███▀▀▀                      █████▀▀▀                         
   ███ ▄█▀█▄ ████▄ ████▄  ▀▀█▄  ▀████▄  ▄████ ▄███▄ ████▄ ▄█▀█▄ 
   ███ ██▄█▀ ██ ▀▀ ██ ▀▀ ▄█▀██    ▀████ ██    ██ ██ ██ ██ ██▄█▀ 
   ███ ▀█▄▄▄ ██    ██    ▀█▄██ ███████▀ ▀████ ▀███▀ ████▀ ▀█▄▄▄ 
                                                    ██          
                                                    ▀▀           """

"""Startup banner shared by the launcher and the TerraScope3D viewer."""
function print_banner(; data_root::AbstractString = "")
    println()
    println("  \e[90m┌──────────────────────────────────────────────────────┐\e[0m")
    println("\e[36m$(_TERRASCOPE_LOGO)\e[0m")
    println("  \e[90m└──────────────────────────────────────────────────────┘\e[0m")
    println()
    println("  \e[3m\e[90mLet's look at diverse geophysical models together...\e[0m")
    println("  \e[90mFeedback / Issues → pankaj.mishra@gtk.fi\e[0m")
    isempty(data_root) || println("  \e[90mData directory    → $(data_root)\e[0m")
    println()
    flush(stdout)
    return nothing
end

# File IO and tests do not need an OpenGL context. Load the window backend only when
# a window is requested. Callers must cross the resulting world-age boundary before
# touching any GLMakie method (`Screen`, `isopen`, `wait`, ...).
function _ensure_glmakie()
    isdefined(@__MODULE__, :GLMakie) || (@eval import GLMakie)
    return nothing
end

function _display_figure(fig; fullscreen::Bool = false)
    _ensure_glmakie()
    return Base.invokelatest() do
        GLMakie.activate!()
        screen = fullscreen ? GLMakie.Screen(; fullscreen = true, float = false, focus_on_show = true) : GLMakie.Screen(; focus_on_show = true)
        display(screen, fig)
        screen
    end
end

# Thin wrapper: load the backend first, then run the whole viewer body in the new
# world so that `wait(screen)` and friends see GLMakie's methods.
function launch_viewer(; kwargs...)
    _ensure_glmakie()
    return Base.invokelatest(_launch_viewer; kwargs...)
end

function _launch_viewer(; data_root::AbstractString = default_data_dir(), max_depth::Union{Nothing, Real} = 50_000.0, with_padding::Bool = false, open_fullscreen::Bool = false, block::Bool = !isinteractive(), active_volume::Symbol = :resistivity)
    bundle = load_dataset_bundle(data_root; with_padding = with_padding, max_depth = max_depth)
    bundle.resistivity === nothing && error("Resistivity volume is required")

    volumes = Dict(:resistivity => bundle.resistivity, :density => bundle.density)
    current_kind = Observable(haskey(volumes, active_volume) && volumes[active_volume] !== nothing ? active_volume : :resistivity)
    current_volume() = volumes[current_kind[]]
    current_range() = _volume_display_range(current_volume())

    fig = Figure(size = (1760, 960))
    ax3 = LScene(fig[1, 1], show_axis = false)
    controls = fig[2, 1] = GridLayout()
    selector_grid = fig[3, 1] = GridLayout()
    selector_ax = Axis(selector_grid[1, 1], title = "XY selector: left-click to add points, right-click/Finish to create section", aspect = DataAspect())
    footer = fig[4, 1] = GridLayout()

    rowsize!(fig.layout, 1, Relative(0.60))
    rowsize!(fig.layout, 2, Auto(166))
    rowsize!(fig.layout, 3, Relative(0.30))
    rowsize!(fig.layout, 4, Auto(44))
    colsize!(fig.layout, 1, Relative(0.94))
    colorbar_widget = Colorbar(fig[1, 2], colormap = _volume_colormap(current_volume()), limits = current_range(), label = _colorbar_label(current_volume()), width = 16)
    colsize!(fig.layout, 2, Relative(0.04))

    show_map_slice = Observable(false)
    show_full_layout = Observable(true)
    pending_points = Observable(CairoMakie.Point2f[])
    selector_section_lines = Observable(CairoMakie.Point2f[])
    section_paths = Observable(Vector{Vector{Tuple{Float64, Float64}}}())
    active_section = Observable(0)
    export_status = Observable("No exports yet")
    axis_info = Observable("")
    iso_color_by_depth = Observable(false)

    depth_slider = Slider(controls[1, 3], range = 1:length(current_volume().z), startvalue = round(Int, length(current_volume().z) / 2), width = 250)
    Label(controls[1, 1], "Depth:", halign = :right, fontsize = 12)
    btn_prev_depth = Button(controls[1, 2], label = "Prev", fontsize = 10)
    btn_next_depth = Button(controls[1, 4], label = "Next", fontsize = 10)
    depth_label = Label(controls[1, 5], "Depth: $(round(-current_volume().z[depth_slider.value[]], digits = 0)) m", fontsize = 10, color = :gray35)
    btn_toggle_map = Button(controls[1, 6], label = "Show Map Slice", fontsize = 10)
    btn_reset = Button(controls[1, 7], label = "Reset View", fontsize = 10)
    btn_export_3d = Button(controls[1, 8], label = "Export 3D", fontsize = 10)
    btn_export_2d = Button(controls[1, 9], label = "Export 2D Sections", fontsize = 10)
    btn_export_iso = Button(controls[1, 10], label = "Export Iso DXF", fontsize = 10)
    Label(controls[1, 11], "2D max depth (km):", halign = :right, fontsize = 10)
    default_export_depth_km = round(maximum(-current_volume().z) / 1000.0; digits = 2)
    export_2d_depth_km_tb = Textbox(controls[1, 12], stored_string = string(default_export_depth_km), width = 70)

    btn_finish_section = Button(controls[2, 1], label = "Finish Section", fontsize = 9)
    btn_clear_points = Button(controls[2, 2], label = "Clear Points", fontsize = 9)
    btn_undo = Button(controls[2, 3], label = "Undo Section", fontsize = 9)
    btn_clear_all = Button(controls[2, 4], label = "Clear Sections", fontsize = 9)
    Label(controls[2, 5], "Active:", halign = :right, fontsize = 11)
    btn_prev_sec = Button(controls[2, 6], label = "Prev", fontsize = 9)
    active_sec_label = Label(controls[2, 7], "S0", fontsize = 10, color = :gray35)
    btn_next_sec = Button(controls[2, 8], label = "Next", fontsize = 9)

    range_lo, range_hi = current_range()
    default_iso_lo = round(_internal_to_physical(current_volume(), range_lo + 0.35 * (range_hi - range_lo)); digits = 3)
    default_iso_hi = round(_internal_to_physical(current_volume(), range_lo + 0.65 * (range_hi - range_lo)); digits = 3)
    default_iso_depth_end = round(maximum(-current_volume().z) / 1000.0; digits = 2)
    iso_label_units = current_volume().kind == :density ? "kg/m^3" : "ohm m"
    Label(controls[3, 1], "Iso min ($iso_label_units):", halign = :right, fontsize = 10)
    iso_min_tb = Textbox(controls[3, 2], stored_string = string(default_iso_lo), width = 70)
    Label(controls[3, 3], "Iso max ($iso_label_units):", halign = :right, fontsize = 10)
    iso_max_tb = Textbox(controls[3, 4], stored_string = string(default_iso_hi), width = 70)
    Label(controls[3, 5], "Start depth (km):", halign = :right, fontsize = 10)
    iso_depth_start_tb = Textbox(controls[3, 6], stored_string = "0.0", width = 70)
    Label(controls[3, 7], "End depth (km):", halign = :right, fontsize = 10)
    iso_depth_end_tb = Textbox(controls[3, 8], stored_string = string(default_iso_depth_end), width = 70)
    btn_iso_color_mode = Button(controls[3, 9], label = iso_color_by_depth[] ? "Color: Depth" : (current_volume().kind == :density ? "Color: Density" : "Color: Resistivity"), fontsize = 9, width = 130)
    btn_apply_iso = Button(controls[3, 10], label = "Apply Iso", fontsize = 9, width = 90)
    btn_clear_iso = Button(controls[3, 11], label = "Clear Iso", fontsize = 9, width = 90)

    Label(footer[1, 1], axis_info, fontsize = 11, color = :gray30, halign = :left, tellwidth = false)
    Label(footer[1, 2], "CRS: model/local", fontsize = 11, color = :gray35, halign = :right)
    Label(footer[2, 1:2], export_status, fontsize = 11, color = :gray25, halign = :left, tellwidth = false)

    rowgap!(controls, 2)
    colgap!(controls, 5)

    corner_controls = GridLayout(fig[1, 1], tellwidth = false, tellheight = false, halign = :right, valign = :top)
    btn_toggle_view_mode = Button(corner_controls[1, 1], label = show_full_layout[] ? "Show Only 3D Scene" : "Show Both Panels", fontsize = 11, width = 150)

    selector_slice = Observable(copy(current_volume().values[:, :, depth_slider.value[]]))
    heatmap!(selector_ax, edges_from_centers(current_volume().x), edges_from_centers(current_volume().y), selector_slice; colormap = _volume_colormap(current_volume()), colorrange = current_range())
    lines!(selector_ax, selector_section_lines; color = :black, linewidth = 1.5)
    scatter!(selector_ax, pending_points; color = :red, markersize = 8)
    pending_line = @lift length($pending_points) >= 2 ? $pending_points : CairoMakie.Point2f[]
    lines!(selector_ax, pending_line; color = :red, linewidth = 2, linestyle = :dash)

    for shp in bundle.shapefiles
        plot_shapefile_on_axis!(selector_ax, shp; xlim = extrema(current_volume().x), ylim = extrema(current_volume().y))
    end

    seismic = nothing
    if !isempty(bundle.segy_files)
        try
            seismic = load_seismic_curtain_from_segy(first(bundle.segy_files))
        catch err
            axis_info[] = "Seismic load skipped: $(sprint(showerror, err))"
        end
    end

    dynamic_plots = Any[]
    iso_plots = Any[]
    iso_triangles = Ref(NTuple{3, NTuple{3, Float64}}[])

    function clear_plots!(plots)
        for plot in reverse(plots)
            try
                delete!(ax3.scene, plot)
            catch
                try
                    delete!(ax3, plot)
                catch
                end
            end
        end
        empty!(plots)
    end

    function update_selector_lines!()
        pts = CairoMakie.Point2f[]
        for path in section_paths[]
            append!(pts, CairoMakie.Point2f[(p[1], p[2]) for p in path])
            push!(pts, CairoMakie.Point2f(NaN, NaN))
        end
        selector_section_lines[] = pts
    end

    function update_active_section!(idx::Int)
        n = length(section_paths[])
        if n == 0
            active_section[] = 0
            active_sec_label.text[] = "S0"
            return
        end
        active_section[] = clamp(idx, 1, n)
        active_sec_label.text[] = "S$(active_section[]) / $n"
    end

    function redraw_scene!()
        clear_plots!(dynamic_plots)
        clear_plots!(iso_plots)
        volume = current_volume()
        crange = _volume_display_range(volume)
        colorbar_widget.colormap = _volume_colormap(volume)
        colorbar_widget.limits = crange
        colorbar_widget.label = _colorbar_label(volume)
        idx = clamp(depth_slider.value[], 1, length(volume.z))
        _draw_box!(ax3, volume)
        if show_map_slice[]
            plane = fill(volume.z[idx], length(volume.x), length(volume.y))
            push!(dynamic_plots, surface!(ax3, volume.x, volume.y, plane; color = volume.values[:, :, idx], colormap = _volume_colormap(volume), colorrange = crange, shading = NoShading, transparency = true, alpha = 0.88))
        end
        for path in section_paths[]
            X, Y, Z, C, _ = build_section_surface_polyline(volume.x, volume.y, volume.z, volume.values, path; nsamp = 240)
            push!(dynamic_plots, surface!(ax3, X, Y, Z; color = C, colormap = _volume_colormap(volume), colorrange = crange, transparency = true, alpha = 0.72))
        end
        for shp in bundle.shapefiles
            plot_shapefile_on_3d!(ax3, shp; z_fixed = 0.0, xlim = extrema(volume.x), ylim = extrema(volume.y))
        end
        if seismic !== nothing
            push!(dynamic_plots, surface!(ax3, seismic.X, seismic.Y, seismic.Z; color = seismic.C, colormap = :grays, colorrange = (-1.0, 1.0), transparency = true, alpha = 0.52))
            push!(dynamic_plots, lines!(ax3, seismic.line_x, seismic.line_y, fill(seismic.line_z, length(seismic.line_x)); color = :orange, linewidth = 2.0))
        end
        selector_slice[] = copy(volume.values[:, :, idx])
        depth_label.text[] = "Depth: $(round(-volume.z[idx], digits = 0)) m"
        axis_info[] = "Showing $(volume.name) | sections=$(length(section_paths[])) | shapefiles=$(length(bundle.shapefiles))"
    end

    function update_layout_mode!()
        if show_full_layout[]
            rowsize!(fig.layout, 1, Relative(0.60))
            rowsize!(fig.layout, 2, Auto(166))
            rowsize!(fig.layout, 3, Relative(0.30))
            rowsize!(fig.layout, 4, Auto(44))
            colsize!(fig.layout, 2, Relative(0.04))
        else
            rowsize!(fig.layout, 1, Relative(1.0))
            rowsize!(fig.layout, 2, Fixed(0))
            rowsize!(fig.layout, 3, Fixed(0))
            rowsize!(fig.layout, 4, Fixed(0))
            colsize!(fig.layout, 2, Fixed(0))
        end
        colorbar_widget.blockscene.visible[] = show_full_layout[]
        selector_ax.blockscene.visible[] = show_full_layout[]
        btn_toggle_view_mode.label[] = show_full_layout[] ? "Show Only 3D Scene" : "Show Both Panels"
    end

    function add_section_from_pending!()
        length(pending_points[]) < 2 && return false
        paths = copy(section_paths[])
        push!(paths, [(Float64(p[1]), Float64(p[2])) for p in pending_points[]])
        section_paths[] = paths
        pending_points[] = CairoMakie.Point2f[]
        update_active_section!(length(paths))
        update_selector_lines!()
        return true
    end

    function parse_iso_controls()
        lo = parse(Float64, strip(iso_min_tb.stored_string[]))
        hi = parse(Float64, strip(iso_max_tb.stored_string[]))
        d0 = 1000.0 * parse(Float64, strip(iso_depth_start_tb.stored_string[]))
        d1 = 1000.0 * parse(Float64, strip(iso_depth_end_tb.stored_string[]))
        return lo, hi, d0, d1
    end

    redraw_scene!()
    _fit_camera!(ax3.scene, current_volume())

    deregister_interaction!(selector_ax, :rectanglezoom)
    on(events(selector_ax).mousebutton) do event
        if event.button == Mouse.left && event.action == Mouse.press
            pos = mouseposition(selector_ax)
            x_click, y_click = Float64(pos[1]), Float64(pos[2])
            volume = current_volume()
            if x_click < minimum(volume.x) || x_click > maximum(volume.x) || y_click < minimum(volume.y) || y_click > maximum(volume.y)
                return
            end
            pts = copy(pending_points[])
            push!(pts, CairoMakie.Point2f(x_click, y_click))
            pending_points[] = pts
        elseif event.button == Mouse.right && event.action == Mouse.press
            if add_section_from_pending!()
                redraw_scene!()
            end
        end
    end

    on(depth_slider.value) do value
        depth_slider.value[] = clamp(round(Int, value), 1, length(current_volume().z))
        redraw_scene!()
    end
    on(btn_prev_depth.clicks) do _
        depth_slider.value[] = max(1, depth_slider.value[] - 1)
    end
    on(btn_next_depth.clicks) do _
        depth_slider.value[] = min(length(current_volume().z), depth_slider.value[] + 1)
    end
    on(btn_toggle_map.clicks) do _
        show_map_slice[] = !show_map_slice[]
        btn_toggle_map.label[] = show_map_slice[] ? "Hide Map Slice" : "Show Map Slice"
        redraw_scene!()
    end
    on(btn_reset.clicks) do _
        _fit_camera!(ax3.scene, current_volume())
    end
    on(btn_finish_section.clicks) do _
        if add_section_from_pending!()
            redraw_scene!()
        end
    end
    on(btn_clear_points.clicks) do _
        pending_points[] = CairoMakie.Point2f[]
    end
    on(btn_undo.clicks) do _
        paths = copy(section_paths[])
        isempty(paths) || pop!(paths)
        section_paths[] = paths
        update_active_section!(length(paths))
        update_selector_lines!()
        redraw_scene!()
    end
    on(btn_clear_all.clicks) do _
        section_paths[] = Vector{Vector{Tuple{Float64, Float64}}}()
        update_active_section!(0)
        update_selector_lines!()
        redraw_scene!()
    end
    on(btn_prev_sec.clicks) do _
        update_active_section!(active_section[] - 1)
    end
    on(btn_next_sec.clicks) do _
        update_active_section!(active_section[] + 1)
    end
    on(btn_iso_color_mode.clicks) do _
        iso_color_by_depth[] = !iso_color_by_depth[]
        btn_iso_color_mode.label[] = iso_color_by_depth[] ? "Color: Depth" : (current_volume().kind == :density ? "Color: Density" : "Color: Resistivity")
    end
    on(btn_apply_iso.clicks) do _
        try
            clear_plots!(iso_plots)
            volume = current_volume()
            lo, hi, d0, d1 = parse_iso_controls()
            triangles, selected = build_range_volume_triangles(volume.x, volume.y, volume.z, volume.values, _physical_to_internal(volume, lo), _physical_to_internal(volume, hi), d0, d1)
            iso_triangles[] = triangles
            if !isempty(triangles)
                vertices, faces = triangles_to_vertices_faces(triangles)
                mesh = CairoMakie.GeometryBasics.Mesh(vertices, faces)
                colors = iso_color_by_depth[] ? [-point[3] for point in vertices] : fill(0.5 * (_physical_to_internal(volume, lo) + _physical_to_internal(volume, hi)), length(vertices))
                push!(iso_plots, mesh!(ax3, mesh; color = colors, colormap = iso_color_by_depth[] ? :plasma : _volume_colormap(volume), transparency = true, alpha = 0.55))
                export_status[] = "Isovolume created from $selected selected cells"
            else
                export_status[] = "No cells found inside the requested iso range"
            end
        catch err
            export_status[] = "Iso failed: $(sprint(showerror, err))"
        end
    end
    on(btn_clear_iso.clicks) do _
        clear_plots!(iso_plots)
        iso_triangles[] = NTuple{3, NTuple{3, Float64}}[]
        export_status[] = "Iso cleared"
    end
    on(btn_export_iso.clicks) do _
        if isempty(iso_triangles[])
            export_status[] = "No iso mesh available to export"
            return
        end
        out_dir = joinpath(dirname(@__DIR__), "exports")
        mkpath(out_dir)
        out_path = joinpath(out_dir, "terrascope_iso_$(Dates.format(now(), "yyyymmdd_HHMMSS")).dxf")
        write_dxf_triangles(out_path, iso_triangles[])
        export_status[] = "Iso DXF exported to $out_path"
    end
    on(btn_export_3d.clicks) do _
        out_dir = joinpath(dirname(@__DIR__), "exports")
        mkpath(out_dir)
        out_path = joinpath(out_dir, "terrascope_view_$(Dates.format(now(), "yyyymmdd_HHMMSS")).png")
        save(out_path, fig)
        export_status[] = "3D view exported to $out_path"
    end
    on(btn_export_2d.clicks) do _
        if isempty(section_paths[])
            export_status[] = "No sections available to export"
            return
        end
        max_depth_km = something(tryparse(Float64, strip(export_2d_depth_km_tb.stored_string[])), maximum(-current_volume().z) / 1000.0)
        out_dir = joinpath(dirname(@__DIR__), "exports", "sections_$(Dates.format(now(), "yyyymmdd_HHMMSS"))")
        exported = _export_sections(current_volume(), section_paths[], out_dir; max_depth_m = 1000.0 * max_depth_km)
        export_status[] = "Exported $(length(exported)) section image(s) to $out_dir"
    end
    on(btn_toggle_view_mode.clicks) do _
        show_full_layout[] = !show_full_layout[]
        update_layout_mode!()
    end

    update_layout_mode!()
    screen = _display_figure(fig; fullscreen = open_fullscreen)
    if block
        wait(screen)
    end
    return fig, screen
end