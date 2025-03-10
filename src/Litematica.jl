module Litematica

using NBT, MinecraftDataStructures, PooledArrays

export Region, Litematic

struct Region{T<:AbstractBlockState, I<:Unsigned}
  name::String
  pos::Tuple{Int32, Int32, Int32}
  blocks::PooledArray{T, I, 3, Array{I, 3}}
  tile_entities::Array{Union{TagCompound, Nothing}, 3}
end

Base.isequal(x::Region, y::Region) = x.name == y.name && x.pos == y.pos && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.:(==)(x::Region, y::Region) = x.name == y.name && x.pos == y.pos && x.blocks == y.blocks && x.tile_entities == y.tile_entities
Base.hash(r::Region, h::UInt) = hash(r.name, hash(r.pos, hash(r.blocks, hash(r.tile_entities, h))))

@inline function Region(blocks::Array{<:AbstractBlockState, 3})
  p = PooledArray(zeros(Block, size(blocks)))
  p .= blocks
  return Region(p)
end

@inline function Region(blocks::PooledArray{<:AbstractBlockState, UInt32, 3, Array{UInt32, 3}})
  is_air(blocks.pool[1]) || ArgumentError("Litematica regions must have air as the first palette element.")
  return Region("region", Int32.((0, 0, 0)), blocks, reshape(Union{TagCompound, Nothing}[], 0, 0, 0))
end

struct Litematic
  data_version::Int32
  metadata::TagCompound
  regions::Vector{Region}
end

Base.isequal(x::Litematic, y::Litematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.:(==)(x::Litematic, y::Litematic) = x.data_version == y.data_version && x.metadata == y.metadata && x.regions == y.regions
Base.hash(l::Litematic, h::UInt) = hash(l.data_version, hash(l.metadata, hash(l.regions, h)))

@inline Litematic(blocks::Array{<:AbstractBlockState, 3}) = Litematic(Region(blocks))
@inline Litematic(blocks::PooledArray{<:AbstractBlockState, UInt32, 3, Array{UInt32, 3}}) = Litematic(Region(blocks))
@inline Litematic(region::Region) = Litematic([region])
@inline Litematic(regions::Vector{Region{A, B}}) where {A,B} = Litematic(2586, TagCompound(), regions)

function Base.show(io::IO, M::MIME"text/plain", lr::Region)
  println(io, "Region \"", lr.name, "\" at ", lr.pos, ':')
  show(io, M, lr.blocks)
end

function Base.show(io::IO, lr::Region)
  a = lr.pos
  b = lr.pos .+ size(lr.blocks) .- 1
  print(io, '"', lr.name, "\" (", a[1], ' ', a[2], ' ', a[3], " ~ ",
        b[1], ' ', b[2], ' ', b[3], ')')
end

# function _readtriple2(io::IO, V::Val{0xa})
#   return NBT._read_tag(io, V, dict2)
# end
#
# function _readproperties(io::IO, V::Val{0xa})
#   return NBT._read_tag(io, V, _readproperty, Pair{String, String})
# end
#
# function _readblockstatepalette(io::IO, V::Val{0x9})
#   return NBT._read_tag(io, V, _readAbstractBlockState, AbstractBlockState)
# end
#
# function _readregions(io::IO, V::Val{0xa})
#   return NBT._read_tag(io, V, _readregion, NamedTuple)
# end
#
# "Properties" => (:props => _readproperties)
#
# "Position" => (:position => _readtriple2),
# "Size" => (:size => _readtriple2),
# "BlockStatePalette" => (:palette => _readblockstatepalette),
#
# "Regions" => (:regions => _readregions)

#---------------------------------------------------------------------------------------------------------------------

# _read_tag(N::UInt8, dict::Dict{String, Pair{Symbol, Function}}) = _read_tag(Val(N), dict)
# function _read_tag(::Val{N}, dict::Dict{String, Pair{Symbol, Function}}) where N
#   return (io::IO, V::Val{N}) -> NBT._read_tag(io, V, dict)
# end
#
# _read_tag(N::UInt8, ::Type{T}, f::Function) where T = _read_tag(Val(N), T, f)
# function _read_tag(::Val{N}, ::Type{T}, f::Function) where {N, T}
#   return (io::IO, V::Val{N}) -> NBT._read_tag(io, V, f, T)
# end
#
# function _readregion(io::IO, V::Val{0xa}, name::String)
#   data = NBT._read_tag(io, V, dict1)
#   pos = (data.position.x, data.position.y, data.position.z)
#   size_ = (data.size.x, data.size.y, data.size.z)
#   pos = min.(pos, pos .+ size_ .- sign.(size_)) # Get negativemost corner
#   size_ = Int64.(abs.(size_)) # Fix size_ sign
#
#   # Array of size `size_`, but reading blocks in XZY order
#   compressedBlocks = CompressedPalettedContainer(data.palette, data.bs)
#   blocks = PooledArray(compressedBlocks, 2, (size_[1], size_[3], size_[2]))
#   blocks.refs = permutedims(blocks.refs, (1, 3, 2))
#
#   tile_entities::Array{Union{TagCompound, Nothing}} = fill(nothing, size_...)
#   for te in data.te
#     x, y, z = _readtriple(te)
#     tile_entities[x+1, y+1, z+1] = te
#   end
#
#   return Region(name, pos, blocks, tile_entities)
# end
#
# function _readAbstractBlockState(io::IO, V::Val{0xa})
#   data = NBT._read_tag(io, V, dict3)
#   return haskey(data, :props) ? BlockStateVector(data.name, data.props) : Block(data.name)
# end
#
# function _readproperty(io::IO, V::Val{0x8}, name::String)
#   return name => NBT._read_tag(io, V)
# end
#
# const dict3 = Dict{String, Pair{Symbol, Function}}(
#   "Name" => (:name => NBT._read_tag),
#   "Properties" => (:props => _read_tag(0xa, Pair{String, String}, _readproperty))
# )
# const dict2 = Dict{String, Pair{Symbol, Function}}(
#   "x" => (:x => NBT._read_tag),
#   "y" => (:y => NBT._read_tag),
#   "z" => (:z => NBT._read_tag)
# )
# const dict1 = Dict{String, Pair{Symbol, Function}}(
#   "BlockStates" => (:bs => NBT._read_tag),
#   "TileEntities" => (:te => NBT._read_tag),
#   "Position" => (:position => _read_tag(0xa, dict2)),
#   "Size" => (:size => _read_tag(0xa, dict2)),
#   "BlockStatePalette" => (:palette => _read_tag(0x9, AbstractBlockState, _readAbstractBlockState)),
# )
# const dict = Dict{String, Pair{Symbol, Function}}(
#   "MinecraftDataVersion" => (:dataversion => NBT._read_tag),
#   "Metadata" => (:metadata => NBT._read_tag),
#   "Regions" => (:regions => _read_tag(0xa, NamedTuple, _readregion))
# )

function Base.read(io::IO, ::Type{Litematic})
  root_tag = read(io, TagCompound).second
  regiontags = root_tag["Regions"].data
  regions = Vector{Region}(undef, length(regiontags))

  for (i, pair) in enumerate(regiontags)
    regiontag = pair.second
    pos, size_ = _readtriple.((regiontag["Position"], regiontag["Size"]))
    pos = min.(pos, pos .+ size_ .- sign.(size_)) # Get negativemost corner
    size_ = Int64.(abs.(size_)) # Fix size_ sign

    # Array of size `size_`, but reading blocks in XZY order
    palette = _AbstractBlockState.(regiontag["BlockStatePalette"].data)
    compressedBlocks = CompressedPalettedContainer(palette, regiontag["BlockStates"])
    blocks = PooledArray(compressedBlocks, 2, (size_[1], size_[3], size_[2]))
    blocks.refs = permutedims(blocks.refs, (1, 3, 2))

    tile_entities::Array{Union{TagCompound, Nothing}} = fill(nothing, size_...)
    for te in regiontag["TileEntities"].data
      x, y, z = _readtriple(te)
      tile_entities[x+1, y+1, z+1] = te
    end

    regions[i] = Region(pair.first, pos, blocks, tile_entities)
  end

  return Litematic(root_tag["MinecraftDataVersion"], root_tag["Metadata"], regions)
end

function Base.write(io::IO, litematic::Litematic)
  s, bytes = begin_nbt_file(io)
  bytes += write_tag(s, "MinecraftDataVersion" => litematic.data_version)
  bytes += write_tag(s, "Version" => Int32(5))
  bytes += write_tag(s, "Metadata" => litematic.metadata)
  bytes += begin_compound(s, "Regions")

  for region in litematic.regions
    bytes += begin_compound(s, region.name)
    bytes += write_tag(s, "BlockStates" => CompressedPalettedContainer(_permutedims(region.blocks, (1, 3, 2)), 2).data)
    bytes += write_tag(s, "PendingBlockTicks" => TagList())
    bytes += write_tag(s, "Position" => _writetriple(region.pos))
    bytes += write_tag(s, "BlockStatePalette" => TagList(_Tag.(region.blocks.pool)))
    bytes += write_tag(s, "Size" => _writetriple(Int32.(size(region.blocks))))
    bytes += write_tag(s, "PendingFluidTicks" => TagList())
    bytes += write_tag(s, "TileEntities" => TagList(TagCompound{Any}[t for t in region.tile_entities if t !== nothing]))
    bytes += write_tag(s, "Entities" => TagList())
    bytes += end_compound(s)
  end

  bytes += end_compound(s)
  bytes += end_nbt_file(s)
  return bytes
end

@inline
function _Tag(block::Block)
  return TagCompound(["Name" => block.id])
end

@inline
function _Tag(blockState::BlockStateVector)
  @inbounds begin
  return TagCompound(["Name" => blockState.id, "Properties" => TagCompound(blockState.properties)])
end end

@inline
function _Tag(blockState::BlockStateDict)
  @inbounds begin
  return TagCompound(["Name" => blockState.id, "Properties" => TagCompound(collect(blockState.properties))])
end end

function _AbstractBlockState(tag::TagCompound) :: AbstractBlockState
  props = tag["Properties"]
  props === nothing && return Block(tag["Name"])
  return BlockStateDict(tag["Name"], Dict(props.data))
end

@inline function _permutedims(p::PooledArray{<:AbstractBlockState, <:Unsigned, 3, Array{UInt32, 3}}, perm::Tuple{Int64, Int64, Int64})
  p1 = copy(p)
  p1.refs = permutedims(p1.refs, perm)
  return p1
end

@inline function _readtriple(tag::TagCompound{T}) where T
  return (tag["x"], tag["y"], tag["z"])
end

@inline function _writetriple(t::Tuple{Int32, Int32, Int32})
  return TagCompound(["x" => t[1], "y" => t[2], "z" => t[3]])
end

end
