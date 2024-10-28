module Litematica

using NBT

export PackedRegion, PackedLitematic, Region, Litematic

struct BlockState
  block::String
  properties::Vector{Pair{String, String}}
end

struct PackedRegion
  name::String
  pos::Tuple{Int32, Int32, Int32}
  palette::Vector{BlockState}
  blocks::Array{Int, 3}
  tile_entities::Array{Union{Tag, Nothing}, 3}
end

struct Region
  name::String
  pos::Tuple{Int32, Int32, Int32}
  blocks::Array{BlockState, 3}
  tile_entities::Array{Union{Tag, Nothing}, 3}
end

struct PackedLitematic
  data_version::Int32
  metadata::Tag
  regions::Vector{PackedRegion}
end

struct Litematic
  data_version::Int32
  metadata::Tag
  regions::Vector{Region}
end

Base.zero(::Type{BlockState}) = BlockState("minecraft:air", Pair{String, String}[])

function Litematic(blocks::Array{BlockState, 3})
  return Litematic(2586, Tag(0xa, "Metadata", Tag[]), Region[Region("region", Int32.((0,0,0)), blocks, reshape(Union{Tag, Nothing}[], 0, 0, 0))])
end

Base.isequal(x::BlockState, y::BlockState) = x.block == y.block && x.properties == y.properties
Base.:(==)(x::BlockState, y::BlockState) = x.block == y.block && x.properties == y.properties
Base.hash(x::BlockState, h::UInt) = hash(x.block, hash(x.properties, hash(:BlockState, h)))

Base.isequal(x::PackedRegion, y::PackedRegion) = x.name == y.name && x.pos == y.pos && x.palette == y.palette && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.:(==)(x::PackedRegion, y::PackedRegion) = x.name == y.name && x.pos == y.pos && x.palette == y.palette && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.hash(r::PackedRegion, h::UInt) = hash(r.name, hash(r.pos, hash(r.palette, hash(r.blocks, hash(r.tile_entities, h)))))

Base.isequal(x::Region, y::Region) = x.name == y.name && x.pos == y.pos && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.:(==)(x::Region, y::Region) = x.name == y.name && x.pos == y.pos && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.hash(r::Region, h::UInt) = hash(r.name, hash(r.pos, hash(r.blocks, hash(r.tile_entities, h))))

Base.isequal(x::PackedLitematic, y::PackedLitematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.:(==)(x::PackedLitematic, y::PackedLitematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.hash(l::PackedLitematic, h::UInt) = hash(l.data_version, hash(l.metadata, hash(l.regions, h)))

Base.isequal(x::Litematic, y::Litematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.:(==)(x::Litematic, y::Litematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.hash(l::Litematic, h::UInt) = hash(l.data_version, hash(l.metadata, hash(l.regions, h)))

Base.read(io::IO, ::Type{Litematic}) = unpack_litematic(read(io, PackedLitematic))

function Base.show(io::IO, ::MIME"text/plain", lr::Region)
  println(io, "LitematicaRegion \"", lr.name, "\" at ", lr.pos, ':')
  show(io, "text/plain", [split(b.block, ':')[end] for b ∈ lr.blocks])
end

function Base.show(io::IO, lr::Region)
  a = lr.pos
  b = lr.pos .+ size(lr.blocks) .- 1
  print(io, '"', lr.name, "\" (", a[1], ' ', a[2], ' ', a[3], " ~ ",
        b[1], ' ', b[2], ' ', b[3], ')')
end

function Base.read(io::IO, ::Type{PackedLitematic})
  root_tag = read(io, Tag)
  regiontags = root_tag["Regions"].data
  regions = Vector{PackedRegion}(undef, length(regiontags))

  for (i, regiontag) ∈ enumerate(regiontags)
    palette = _read_palette(regiontag["BlockStatePalette"])
    blockstate_ids = _64_to_n_bit(regiontag["BlockStates"].data, _palette2nbits(palette))

    pos, size_ = _readtriple.((regiontag["Position"], regiontag["Size"]))
    pos = min.(pos, pos .+ size_ .- sign.(size_)) # Get negativemost corner
    size_ = Int64.(abs.(size_)) # Fix size_ sign

    blockstate_ids = blockstate_ids[1:prod(size_)]
    # Array of size `size_`, but reading blocks in XZY order
    blocks = permutedims(reshape(blockstate_ids, size_[1], size_[3], size_[2]), (1, 3, 2))

    tile_entities::Array{Union{Tag, Nothing}} = fill(nothing, size_...)
    for te ∈ regiontag["TileEntities"].data
      x, y, z = _readtriple(te)
      tile_entities[x+1, y+1, z+1] = te
    end

    regions[i] = PackedRegion(regiontag.name, pos, palette, blocks, tile_entities)
  end

  return PackedLitematic(root_tag["MinecraftDataVersion"].data, root_tag["Metadata"], regions)
end

Base.write(io::IO, l::Litematic) = write(io, pack_litematic(l))

function Base.write(io::IO, litematic::PackedLitematic)
  regiontags = [
    Tag(0xa, region.name, [
      Tag(0xc, "BlockStates", _n_to_64_bit(permutedims(region.blocks, (1, 3, 2)), _palette2nbits(region.palette))),
      Tag(0x9, "PendingBlockTicks", Tag[]),
      _writetriple(region.pos, "Position"),
      _write_palette(region.palette), # BlockStatePalette
      _writetriple(Int32.(size(region.blocks)), "Size"),
      Tag(0x9, "PendingFluidTicks", Tag[]),
      Tag(0x9, "TileEntities", [t for t ∈ region.tile_entities if t !== nothing]),
      Tag(0x9, "Entities", Tag[])
    ])
  for region ∈ litematic.regions]
  file = Tag(0xa, "", [
    Tag(0x3, "MinecraftDataVersion", litematic.data_version),
    Tag(0x3, "Version", Int32(5)),
    litematic.metadata,
    Tag(0xa, "Regions", regiontags)
  ])
  return write(io, file)
end

function unpack_litematic(litematic::PackedLitematic)
  unpacked_regions = [
    Region(r.name, r.pos, getindex(r.palette, r.blocks), r.tile_entities)
  for r ∈ litematic.regions]
  return Litematic(litematic.data_version, litematic.metadata, unpacked_regions)
end

function _blocks2palette(blocks::Array{BlockState, 3})
  palette = [BlockState("minecraft:air", Pair{String, String}[])]
  packed = Array{Int, 3}(undef, size(blocks)...)
  latestindex = 0
  for (i, b) ∈ enumerate(blocks)
    index = findfirst(isequal(b), palette)
    if index === nothing
      push!(palette, b)
      packed[i] = latestindex += 1
    else
      packed[i] = index - 1
    end
  end
  palette, packed
end

function pack_litematic(litematic::Litematic)
  packed_regions = [
    PackedRegion(r.name, r.pos, _blocks2palette(r.blocks)..., r.tile_entities)
  for r ∈ litematic.regions]

  return PackedLitematic(litematic.data_version, litematic.metadata, packed_regions)
end

function _read_palette(root_tag::Tag)::Vector{BlockState}
  blockstatetags = root_tag.data
  palette = Vector{BlockState}(undef, length(blockstatetags))
  for (i, blockstatetag) ∈ enumerate(blockstatetags)
    properties = Pair{String, String}[]

    propertiestag = blockstatetag["Properties"]
    if propertiestag !== nothing
      properties = [prop.name => prop.data for prop ∈ propertiestag.data]
    end

    palette[i] = BlockState(blockstatetag["Name"].data, properties)
  end
  return palette
end

function _write_palette(palette::Vector{BlockState})
  blockstatetags = Array{Tag}(undef, length(palette))
  for (i, blockstate) ∈ enumerate(palette)
    nametag = Tag(0x8, "Name", blockstate.block)
    properties = [Tag(0x8, p.first, p.second) for p ∈ blockstate.properties]

    if length(properties) == 0
      @inbounds blockstatetags[i] = Tag(0xa, "", [nametag])
    else
      propertiestag = Tag(0xa, "Properties", properties)
      @inbounds blockstatetags[i] = Tag(0xa, "", [propertiestag, nametag])
    end
  end
  return Tag(0x9, "BlockStatePalette", blockstatetags)
end

function _ints2bits(ints::Array{Int64}, intsize::Int)
  return vec(Bool[n >>> i & 1 for i ∈ 0:intsize-1, n ∈ ints])
end

@inline function _bits2int(bits::SubArray{Bool})
  int = zero(UInt64)
  for i ∈ length(bits):-1:1 @inbounds int = int * 2 + bits[i] end
  return reinterpret(Int64, int)
end

function _bits2ints(bits::Array{Bool}, intsize::Int)
  s, l = intsize-1, length(bits)
  return [_bits2int(@inbounds view(bits, i:min(i+s, l))) for i ∈ 1:intsize:l]
end

function _64_to_n_bit(array::Vector{Int64}, n::Int)
  bits = _ints2bits(array, 64)
  return _bits2ints(bits, n) .+ 1
end

function _n_to_64_bit(array::Array{Int, 3}, n::Int)
  bits = _ints2bits(array, n)
  return reinterpret(Int64, BitArray(bits).chunks)
end

@inline function _palette2nbits(palette::Vector{BlockState})
  return max(ceil(Int, log2(length(palette))), 2)
end

@inline function _readtriple(tag::Tag{Vector{Tag}})
  return (tag["x"].data, tag["y"].data, tag["z"].data)
end

@inline function _writetriple(t::Tuple{Int32, Int32, Int32}, name::String)
  return Tag(0xa, name, [Tag(0x3, "x", t[1]), Tag(0x3, "y", t[2]), Tag(0x3, "z", t[3])])
end

end
