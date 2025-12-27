using Litematica
using Test
using LazyArtifacts
# using Aqua

# Aqua.test_all(Litematica)

@testset "Litematica.jl" begin
  rootdir = artifact"litematics"
  for f ∈ readdir(rootdir)
    print(f)
    f = joinpath(rootdir, f)
    starttime = time()

    newfile = tempname()
    litematic = read(f, Litematic)
    write(newfile, litematic)
    litematic2 = read(newfile, Litematic)

    @test all(pair -> pair[2].blocks == litematic2.regions[pair[1]].blocks, litematic.regions)
    @test hash(litematic) == hash(litematic2)
    @test litematic == litematic2

    println(" (", round(1000(time()-starttime); digits=2), " ms)")
  end
end
