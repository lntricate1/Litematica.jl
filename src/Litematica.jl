module Litematica

using NBT, MinecraftDataStructures, PooledArrays

export Region, Litematic

struct Region
  name::String
  pos::Tuple{Int32, Int32, Int32}
  blocks::PooledArray{BlockState, UInt32, 3, Array{UInt32, 3}}
  tile_entities::Array{Union{Tag, Nothing}, 3}
end

Base.isequal(x::Region, y::Region) = x.name == y.name && x.pos == y.pos && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.:(==)(x::Region, y::Region) = x.name == y.name && x.pos == y.pos && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.hash(r::Region, h::UInt) = hash(r.name, hash(r.pos, hash(r.blocks, hash(r.tile_entities, h))))

@inline function Region(blocks::Array{BlockState, 3})
  p = PooledArray(zeros(BlockState, size(blocks)))
  p .= blocks
  return Region(p)
end
@inline function Region(blocks::PooledArray{BlockState, UInt32, 3, Array{UInt32, 3}})
  blocks.pool[1] != zero(BlockState) && ArgumentError("Litematica regions must have air as the first palette element.")
  return Region("region", Int32.((0, 0, 0)), blocks, reshape(Union{Tag, Nothing}[], 0, 0, 0))
end

struct Litematic
  data_version::Int32
  metadata::Tag
  regions::Vector{Region}
end

Base.isequal(x::Litematic, y::Litematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.:(==)(x::Litematic, y::Litematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.hash(l::Litematic, h::UInt) = hash(l.data_version, hash(l.metadata, hash(l.regions, h)))

@inline Litematic(blocks::Array{BlockState, 3}) = Litematic(Region(blocks))
@inline Litematic(blocks::PooledArray{BlockState, UInt32, 3, Array{UInt32, 3}}) = Litematic(Region(blocks))
@inline Litematic(region::Region) = Litematic([region])
@inline Litematic(regions::Vector{Region}) = Litematic(2586, Tag(0xa, "Metadata", Tag[]), regions)

function Base.show(io::IO, ::MIME"text/plain", lr::Region)
  println(io, "LitematicaRegion \"", lr.name, "\" at ", lr.pos, ':')
  # show(io, "text/plain", [split(b.id, ':')[end] for b in lr.blocks])
  show(io, MIME"text/plain", lr.blocks)
end

function Base.show(io::IO, lr::Region)
  a = lr.pos
  b = lr.pos .+ size(lr.blocks) .- 1
  print(io, '"', lr.name, "\" (", a[1], ' ', a[2], ' ', a[3], " ~ ",
        b[1], ' ', b[2], ' ', b[3], ')')
end

function Base.read(io::IO, ::Type{Litematic})
  root_tag = read(io, Tag)
  regiontags = root_tag["Regions"].data
  regions = Vector{Region}(undef, length(regiontags))

  for (i, regiontag) in enumerate(regiontags)
    pos, size_ = _readtriple.((regiontag["Position"], regiontag["Size"]))
    pos = min.(pos, pos .+ size_ .- sign.(size_)) # Get negativemost corner
    size_ = Int64.(abs.(size_)) # Fix size_ sign

    # Array of size `size_`, but reading blocks in XZY order
    palette = _read_palette(regiontag["BlockStatePalette"])
    compressedBlocks = CompressedPalettedContainer(palette, regiontag["BlockStates"].data)
    blockstate_ids = PooledArray(compressedBlocks, 2, prod(size_))
    blocks = _permutedims(reshape(blockstate_ids, size_[1], size_[3], size_[2]), (1, 3, 2))

    tile_entities::Array{Union{Tag, Nothing}} = fill(nothing, size_...)
    for te in regiontag["TileEntities"].data
      x, y, z = _readtriple(te)
      tile_entities[x+1, y+1, z+1] = te
    end

    regions[i] = Region(regiontag.name, pos, blocks, tile_entities)
  end

  return Litematic(root_tag["MinecraftDataVersion"].data, root_tag["Metadata"], regions)
end

function Base.write(io::IO, litematic::Litematic)
  regiontags = [
    Tag(0xa, region.name, [
      Tag(0xc, "BlockStates", CompressedPalettedContainer(_permutedims(region.blocks, (1, 3, 2)), 2).data),
      Tag(0x9, "PendingBlockTicks", Tag[]),
      _writetriple(region.pos, "Position"),
      _write_palette(region.blocks.pool), # BlockStatePalette
      _writetriple(Int32.(size(region.blocks)), "Size"),
      Tag(0x9, "PendingFluidTicks", Tag[]),
      Tag(0x9, "TileEntities", [t for t in region.tile_entities if t !== nothing]),
      Tag(0x9, "Entities", Tag[])
    ])
  for region in litematic.regions]
  file = Tag(0xa, "", [
    Tag(0x3, "MinecraftDataVersion", litematic.data_version),
    Tag(0x3, "Version", Int32(5)),
    litematic.metadata,
    Tag(0xa, "Regions", regiontags)
  ])
  return write(io, file)
end

@inline function _permutedims(p::PooledArray{BlockState, UInt32, 3, Array{UInt32, 3}}, perm)
  p1 = copy(p)
  p1.refs = permutedims(p1.refs, perm)
  return p1
end
@inline function _permutedims(p::Base.ReshapedArray{MinecraftDataStructures.BlockState, 3, PooledArrays.PooledVector{MinecraftDataStructures.BlockState, UInt32, Vector{UInt32}}, Tuple{}}, perm)
  p1 = copy(p)
  p1.refs = permutedims(p1.refs, perm)
  return p1
end
@inline function _permutedims(p::PooledArray{BlockState, UInt64, 3, Array{UInt64, 3}}, perm)
  p1 = copy(p)
  p1.refs = permutedims(p1.refs, perm)
  return p1
end
@inline function _permutedims(p::Base.ReshapedArray{MinecraftDataStructures.BlockState, 3, PooledArrays.PooledVector{MinecraftDataStructures.BlockState, UInt64, Vector{UInt64}}, Tuple{}}, perm)
  p1 = copy(p)
  p1.refs = permutedims(p1.refs, perm)
  return p1
end

function _read_palette(root_tag::Tag)::Vector{BlockState}
  blockstatetags = root_tag.data
  palette = Vector{BlockState}(undef, length(blockstatetags))
  for (i, blockstatetag) in enumerate(blockstatetags)
    propertiestag = blockstatetag["Properties"]
    if propertiestag === nothing
      palette[i] = BlockState(blockstatetag["Name"].data, Pair{String, String}[])
    else
      properties = [prop.name => prop.data for prop in propertiestag.data]
      palette[i] = BlockState(blockstatetag["Name"].data, properties)
    end
  end
  return palette
end

function _write_palette(palette::Vector{BlockState})
  blockstatetags = Array{Tag}(undef, length(palette))
  for (i, blockstate) in enumerate(palette)
    nametag = Tag(0x8, "Name", blockstate.id)

    if length(blockstate.properties) == 0
      @inbounds blockstatetags[i] = Tag(0xa, "", [nametag])
    else
      propertiestag = Tag(0xa, "Properties", [Tag(0x8, p.first, p.second) for p in blockstate.properties])
      @inbounds blockstatetags[i] = Tag(0xa, "", [propertiestag, nametag])
    end
  end
  return Tag(0x9, "BlockStatePalette", blockstatetags)
end

@inline function _readtriple(tag::Tag{Vector{Tag}})
  return (tag["x"].data, tag["y"].data, tag["z"].data)
end

@inline function _writetriple(t::Tuple{Int32, Int32, Int32}, name::String)
  return Tag(0xa, name, [Tag(0x3, "x", t[1]), Tag(0x3, "y", t[2]), Tag(0x3, "z", t[3])])
end

end
