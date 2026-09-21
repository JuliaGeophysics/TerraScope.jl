# GDAL handles GeoTIFF and single-variable NetCDF rasters, including pixel rotation.
function _load_raster_import(path, opts, target)
    ArchGDAL.read(path) do dataset
        ArchGDAL.nraster(dataset) == 1 || error("Select a single-band raster (export the desired NetCDF variable/band first).")
        source = isempty(strip(opts.source_crs)) ? ArchGDAL.getproj(dataset) : opts.source_crs
        transform = _xy_transform(source,target)
        band = ArchGDAL.getband(dataset,1)
        values = Float64.(ArchGDAL.read(band))
        nodata = ArchGDAL.getnodatavalue(band)
        if !isnothing(nodata)
            replace!(values,nodata=>NaN)
        end
        gt = ArchGDAL.getgeotransform(dataset)
        X = similar(values)
        Y = similar(values)
        for j in axes(values,2), i in axes(values,1)
            x = gt[1] + (i-0.5)*gt[2] + (j-0.5)*gt[3]
            y = gt[4] + (i-0.5)*gt[5] + (j-0.5)*gt[6]
            X[i,j],Y[i,j] = transform(x,y)
        end
        return ImportedGrid(X,Y,[opts.top_z_m],reshape(values,size(values)...,1)), source
    end
end
