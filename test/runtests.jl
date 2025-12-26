using Litematica
using Test
using LazyArtifacts
# using Aqua

# Aqua.test_all(Litematica)

@testset "Litematica.jl" begin
  # rootdir = artifact"litematics"
  rootdir = "/home/intricate/julia/litematics/"
  for f ∈ readdir(rootdir)
    print(f)
    f = joinpath(rootdir, f)
    starttime = time()

    newfile = tempname()
    litematic = read(f, Litematic)
    write(newfile, litematic)
    litematic2 = read(newfile, Litematic)

    @test all((r1, r2) -> r1.blocks == r2.blocks, zip(litematic.regions, litematic2.regions))
    @test hash(litematic) == hash(litematic2)
    @test litematic == litematic2

    println(" (", round(1000(time()-starttime); digits=2), " ms)")
  end
end
