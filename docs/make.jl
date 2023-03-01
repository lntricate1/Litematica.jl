using Litematica
using Documenter

DocMeta.setdocmeta!(Litematica, :DocTestSetup, :(using Litematica); recursive=true)

makedocs(;
    modules=[Litematica],
    authors="Ellie <intricatebread@gmail.com> and contributors",
    repo="https://github.com/lntricate1/Litematica.jl/blob/{commit}{path}#{line}",
    sitename="Litematica.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://lntricate1.github.io/Litematica.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/lntricate1/Litematica.jl",
    devbranch="main",
)
