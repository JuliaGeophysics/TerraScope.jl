function _segy_scalar_factor(s::Integer)
    s == 0 && return 1.0
    s > 0 && return Float64(s)
    return 1.0 / Float64(abs(s))
end

function _extract_trace_xy(header; pref::Symbol = :source)
    scale = _segy_scalar_factor(getproperty(header, :RecSourceScalar))
    sx = Float64(getproperty(header, :SourceX)) * scale
    sy = Float64(getproperty(header, :SourceY)) * scale
    gx = Float64(getproperty(header, :GroupX)) * scale
    gy = Float64(getproperty(header, :GroupY)) * scale
    source_ok = isfinite(sx) && isfinite(sy) && !(sx == 0.0 && sy == 0.0)
    group_ok = isfinite(gx) && isfinite(gy) && !(gx == 0.0 && gy == 0.0)
    if pref == :group
        return group_ok ? (gx, gy) : (sx, sy)
    end
    return source_ok ? (sx, sy) : (gx, gy)
end

function _normalize_amplitude(A::AbstractMatrix{<:Real}; clip_quantile::Real = 0.995)
    vals = abs.(vec(Float64.(A)))
    isempty(vals) && return zeros(Float64, size(A))
    q = quantile(vals, clamp(Float64(clip_quantile), 0.5, 0.9999))
    q = isfinite(q) && q > 0 ? q : maximum(vals)
    q = (isfinite(q) && q > 0) ? q : 1.0
    return clamp.(Float64.(A) ./ q, -1.0, 1.0)
end

function compute_seismic_envelope(seis::AbstractMatrix{<:Real})
    nsamples = size(seis, 2)
    nsamples == 0 && return zeros(Float64, size(seis))
    hilbert_filter = zeros(Float64, nsamples)
    hilbert_filter[1] = 1.0
    if iseven(nsamples)
        hilbert_filter[nsamples ÷ 2 + 1] = 1.0
        hilbert_filter[2:(nsamples ÷ 2)] .= 2.0
    else
        hilbert_filter[2:((nsamples + 1) ÷ 2)] .= 2.0
    end
    analytic_signal = ifft(fft(Float64.(seis), 2) .* reshape(hilbert_filter, 1, :), 2)
    return abs.(analytic_signal)
end

function load_seismic_curtain_from_segy(path::AbstractString; trace_xy::Symbol = :source, display_mode::Symbol = :original, sample_spacing_m::Real = 12.5, top_z_m::Real = 0.0, max_traces::Int = 1400, max_samples::Int = 1200, clip_quantile::Real = 0.995)
    isfile(path) || error("SEG-Y file not found: $path")
    trace_xy in (:source,:group) || error("Trace coordinates must be source or group")
    display_mode in (:original,:envelope) || error("Display mode must be original or envelope")
    isfinite(sample_spacing_m) && sample_spacing_m > 0 || error("Sample spacing must be positive")
    isfinite(top_z_m) || error("Top depth must be finite")
    max_traces >= 2 && max_samples >= 2 || error("Seismic sample limits must be at least 2")
    segy = segy_read(path)
    data = segy.data # Downsample before converting; avoid duplicating the entire survey.
    headers = segy.traceheaders
    n_samples, n_traces = size(data)
    n_samples >= 2 && n_traces >= 2 || error("Seismic curtain requires at least two traces and samples")
    length(headers) == n_traces || error("SEG-Y trace header count mismatch")

    trace_idx = unique(round.(Int, range(1, n_traces; length = min(max_traces, n_traces))))
    sample_idx = unique(round.(Int, range(1, n_samples; length = min(max_samples, n_samples))))
    xs = Vector{Float64}(undef, length(trace_idx))
    ys = similar(xs)
    for (k, i_trace) in enumerate(trace_idx)
        xs[k], ys[k] = _extract_trace_xy(headers[i_trace]; pref = trace_xy)
    end

    nt = length(trace_idx)
    ns = length(sample_idx)
    X = Matrix{Float64}(undef, nt, ns)
    Y = Matrix{Float64}(undef, nt, ns)
    Z = Matrix{Float64}(undef, nt, ns)
    A = Matrix{Float32}(undef, nt, ns)
    for i in 1:nt
        for (k, sample) in enumerate(sample_idx)
            X[i, k] = xs[i]
            Y[i, k] = ys[i]
            Z[i, k] = -(Float64(top_z_m) + (sample - 1) * Float64(sample_spacing_m))
            A[i, k] = data[sample, trace_idx[i]]
        end
    end

    colors = if Symbol(lowercase(String(display_mode))) == :envelope
        _normalize_amplitude(compute_seismic_envelope(A); clip_quantile = clip_quantile)
    else
        _normalize_amplitude(A; clip_quantile = clip_quantile)
    end

    return (
        X = X,
        Y = Y,
        Z = Z,
        C = colors,
        line_x = xs,
        line_y = ys,
        line_z = -Float64(top_z_m),
    )
end