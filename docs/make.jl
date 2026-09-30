using Documenter, DocumenterVitepress
using TerraScope

makedocs(;
    sitename = "TerraScope.jl",
    authors  = "JuliaGeophysics community, Pankaj K Mishra, and contributors",
    modules  = [TerraScope],
    # most of the API is still undocumented; don't fail the build over it
    checkdocs = :none,
    format   = DocumenterVitepress.MarkdownVitepress(;
        repo       = "github.com/JuliaGeophysics/TerraScope.jl",
        devbranch  = "main",
        devurl     = "dev",
        # full URL with https://, otherwise the host is taken as part of the base path
        deploy_url = "https://juliageophysics.com/TerraScope.jl",
        description = "A Makie-based 3D viewer for MT, gravity, magnetic, shapefile and seismic datasets",
        # dev is the only published version, so let search engines index it
        noindex_non_stable = false,
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Guide" => [
            "Inputs"          => "inputs.md",
            "Launcher settings" => "settings.md",
            "Demo data"       => "demo_data.md",
            "Faster startup"  => "startup.md",
        ],
        "API" => "api.md",
    ],
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/JuliaGeophysics/TerraScope.jl.git",
    devbranch = "main",
    push_preview = true,
)
