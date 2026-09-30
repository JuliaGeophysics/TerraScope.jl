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
