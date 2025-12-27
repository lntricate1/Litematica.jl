module Litematica

using NBT, MinecraftDataStructures, PooledArrays
using OrderedCollections
using BufferedStreams, CodecZlib

export Region, Litematic

struct Region{T<:AbstractBlockState, I<:Unsigned}
  position::Tuple{Int32, Int32, Int32}
  blocks::PooledArray{T, I, 3, Array{I, 3}}
  tileEntities::Array{Union{LittleDict{String}, Nothing}, 3}
end

Base.isequal(x::Region, y::Region) = x.position == y.position && x.blocks == y.blocks && x.tileEntities == y.tileEntities
Base.:(==)(x::Region, y::Region) = x.position == y.position && x.blocks == y.blocks && x.tileEntities == y.tileEntities
Base.hash(r::Region, h::UInt) = hash(r.position, hash(r.blocks, hash(r.tileEntities, h)))

@inline function Region(blocks::Array{<:AbstractBlockState, 3})
  p = PooledArray(zeros(Block, size(blocks)))
  p .= blocks
  return Region(p)
end

@inline function Region(blocks::PooledArray{<:AbstractBlockState, UInt32, 3, Array{UInt32, 3}})
  is_air(blocks.pool[1]) || ArgumentError("Litematica regions must have air as the first palette element.")
  return Region(Int32.((0, 0, 0)), blocks, reshape(Union{LittleDict{String}, Nothing}[], 0, 0, 0))
end

struct Litematic
  minecraftDataVersion::Int32
  version::Int32
  metadata::LittleDict{String}
  regions::LittleDict{String, Region}
end

Base.isequal(x::Litematic, y::Litematic) = x.minecraftDataVersion == y.minecraftDataVersion && x.version == y.version && x.metadata == y.metadata && x.regions == y.regions
Base.:(==)(x::Litematic, y::Litematic) = x.minecraftDataVersion == y.minecraftDataVersion && x.version == y.version && x.metadata == y.metadata && x.regions == y.regions
Base.hash(l::Litematic, h::UInt) = hash(l.minecraftDataVersion, hash(l.version, hash(l.metadata, hash(l.regions, h))))

@inline Litematic(blocks::Array{<:AbstractBlockState, 3}) = Litematic(Region(blocks))
@inline Litematic(blocks::PooledArray{<:AbstractBlockState, UInt32, 3, Array{UInt32, 3}}) = Litematic(Region(blocks))
@inline Litematic(region::Region) = Litematic([region])
@inline Litematic(regions::Vector{Region{A, B}}) where {A,B} = Litematic(2586, 1, LittleDict{String}(), regions)

function Base.show(io::IO, M::MIME"text/plain", lr::Region)
  println(io, "Region at ", lr.position, ':')
  show(io, M, lr.blocks)
end

function Base.show(io::IO, lr::Region)
  a = lr.position
  b = lr.position .+ size(lr.blocks) .- 1
  print(io, "Region(", a[1], ' ', a[2], ' ', a[3], " ~ ",
        b[1], ' ', b[2], ' ', b[3], ')')
end

function bitunpack(compressed::Vector{Int64}, palette::Vector{T}, min_bits::Int64, size::NTuple{3, Int32}) where T<:AbstractBlockState
  wordsize = max(min_bits, ceil(Int, log2(length(palette))))
  data = ones(UInt32, size)
  shift = 0
  j = 1
  mask = 2^wordsize - 1
  for i in 1:prod(size)
    data[i] += (compressed[j] >>> shift) & mask
    if shift + wordsize > 64
      data[i] += (compressed[j += 1] >>> (shift - 64)) & mask
      shift = shift + wordsize - 64
    elseif shift + wordsize == 64
      j += 1
      shift = 0
    else
      shift += wordsize
    end
  end
  return PooledArray(PooledArrays.RefArray(data), Dict{T, UInt32}(b => UInt32(i) for (i, b) in enumerate(palette)), palette, Threads.Atomic{Int64}(1))
end

# TODO: this is hella slow
function bitpack(uncompressed::PooledArray{<:AbstractBlockState}, min_bits::Int)
  wordsize = max(min_bits, ceil(Int, log2(length(uncompressed.pool))))
  reinterpret.(Int64, BitArray((n - 1) >>> i & 1 == 1 for n in uncompressed.refs for i in 0:wordsize - 1).chunks)
end

function Base.read(io::IO, ::Type{Litematic})
  stream = BufferedInputStream(GzipDecompressorStream(io))
  skip(stream, 1) # Skip 0x0a
  skip(stream, ntoh(read(stream, UInt16))) # Skip name
  local minecraftDataVersion::Int32, version::Int32, metadata::LittleDict{String}, regions::LittleDict{String, Region}
  while (contentsid = read(stream, UInt8)) !== 0x0
    name = NBT._read_name(stream)
    if contentsid == 0x3 && name == "MinecraftDataVersion"
      minecraftDataVersion = NBT._read_tag3(stream)
    elseif contentsid == 0x3 && name == "Version"
      version = NBT._read_tag3(stream)
    elseif contentsid == 0xa && name == "Metadata"
      metadata = NBT._read_taga(stream)
    elseif contentsid == 0xa && name == "Regions"
      names = String[]
      data = Region[]
      while (contentsid = read(stream, UInt8)) !== 0x0
        push!(names, NBT._read_name(stream))
        push!(data, read_region(stream))
      end
      regions = LittleDict(names, data)
    else
      NBT._lut_skip[contentsid](io)
    end
  end
  return Litematic(minecraftDataVersion, version, metadata, regions)
end

function read_region(io::IO)
  local position::NTuple{3, Int32}
  local size_::NTuple{3, Int32}
  local tileEntities::Vector{LittleDict{String, Any}}
  local palette::Vector{AbstractBlockState}
  local blockStates::Vector{Int64}
  while (contentsid = read(io, UInt8)) !== 0x0
    name = NBT._read_name(io)
    if contentsid == 0xc && name == "BlockStates"
      blockStates = NBT._read_tagc(io)
    elseif contentsid == 0xa && name == "Position"
      position = read_coords(io)
    elseif contentsid == 0x9 && name == "BlockStatePalette"
      palette = read_blockstate_palette(io)
    elseif contentsid == 0xa && name == "Size"
      size_ = read_coords(io)
    elseif contentsid == 0x9 && name == "TileEntities"
      tileEntities = NBT._read_tag9(io)
    else
      NBT._lut_skip[contentsid](io)
    end
  end
  position = min.(position, position .+ size_ .- sign.(size_)) # get negativemost corner
  size_ = abs.(size_)
  blocks = permutedims(bitunpack(blockStates, palette, 2, (size_[1], size_[3], size_[2])), (1,3,2))
  tile_entities::Array{Union{LittleDict{String}, Nothing}, 3} = fill(nothing, size_...)
  for te in tileEntities
    x, y, z = _readtriple(te)
    tile_entities[x+1, y+1, z+1] = te
  end
  return Region(position, blocks, tile_entities)
end

function read_coords(io::IO)
  local x::Int32, y::Int32, z::Int32
  while (contentsid = read(io, UInt8)) !== 0x0
    name = NBT._read_name(io)
    if contentsid == 0x3 && name == "x"
      x = NBT._read_tag3(io)
    elseif contentsid == 0x3 && name == "y"
      y = NBT._read_tag3(io)
    elseif contentsid == 0x3 && name == "z"
      z = NBT._read_tag3(io)
    else
      NBT._lut_skip[contentsid](io)
    end
  end
  return (x, y, z)
end

function read_blockstate_palette(io::IO)
  contentsid = Base.read(io, UInt8)
  size = ntoh(Base.read(io, Int32))
  contentsid != 0xa && return AbstractBlockState[]
  palette = Vector{AbstractBlockState}(undef, size)
  for i in 1:size
    palette[i] = read_blockstate(io)
  end
  return palette
end

function read_blockstate(io::IO)
  local id::String, properties::LittleDict{String, String}
  has_props = false
  while (contentsid = Base.read(io, UInt8)) != 0x0
    name = NBT._read_name(io)
    if contentsid == 0x8 && name == "Name"
      id = NBT._read_tag8(io)
    elseif contentsid == 0xa && name == "Properties"
      keys = String[]
      values = String[]
      while (contentsid1 = Base.read(io, UInt8)) != 0x0
        if contentsid1 != 0x8
          NBT._skip_name(io)
          NBT._lut_skip[contentsid1](io)
          continue
        end
        push!(keys, NBT._read_name(io))
        push!(values, NBT._read_tag8(io))
      end
      properties = LittleDict(keys, values)
      has_props = true
    else
      NBT._lut_skip[contentsid](io)
    end
  end

  has_props && return BlockState(id, properties)
  return Block(id)
end

function Base.write(io::IO, litematic::Litematic)
  s, bytes = NBT.begin_nbt_file(io)
  bytes += NBT.write_tag(s, "MinecraftDataVersion" => litematic.minecraftDataVersion)
  bytes += NBT.write_tag(s, "Version" => litematic.version)
  bytes += NBT.write_tag(s, "Metadata" => litematic.metadata)
  bytes += NBT.begin_compound(s, "Regions")

  for (name, region) in litematic.regions
    bytes += NBT.begin_compound(s, name)
    bytes += NBT.write_tag(s, "BlockStates" => bitpack(_permutedims(region.blocks, (1, 3, 2)), 2))
    bytes += NBT.write_tag(s, "PendingBlockTicks" => LittleDict{String}[])
    bytes += NBT.write_tag(s, "Position" => _writetriple(region.position))
    bytes += NBT.write_tag(s, "BlockStatePalette" => _Tag.(region.blocks.pool))
    bytes += NBT.write_tag(s, "Size" => _writetriple(Int32.(size(region.blocks))))
    bytes += NBT.write_tag(s, "PendingFluidTicks" => LittleDict{String}[])
    bytes += NBT.write_tag(s, "TileEntities" => LittleDict{String}[t for t in region.tileEntities if t !== nothing])
    bytes += NBT.write_tag(s, "Entities" => LittleDict{String}[])
    bytes += NBT.end_compound(s)
  end

  bytes += NBT.end_compound(s)
  bytes += NBT.end_nbt_file(s)
  return bytes
end

@inline function _Tag(block::Block)
  return LittleDict("Name" => block.id)
end

@inline function _Tag(blockState::BlockState)
  @inbounds begin
  return LittleDict("Name" => blockState.id, "Properties" => blockState.properties)
end end

function _AbstractBlockState(tag::LittleDict{String}) :: AbstractBlockState
  haskey(tag, "Properties") || return Block(tag["Name"])
  return BlockState(tag["Name"], tag["Properties"])
end

@inline function _permutedims(p::PooledArray{<:AbstractBlockState, <:Unsigned, 3, Array{UInt32, 3}}, perm::Tuple{Int64, Int64, Int64})
  p1 = copy(p)
  p1.refs = permutedims(p1.refs, perm)
  return p1
end

@inline function _readtriple(tag::LittleDict{String})
  return (tag["x"], tag["y"], tag["z"])
end

@inline function _writetriple(t::Tuple{Int32, Int32, Int32})
  return LittleDict("x" => t[1], "y" => t[2], "z" => t[3])
end

end
