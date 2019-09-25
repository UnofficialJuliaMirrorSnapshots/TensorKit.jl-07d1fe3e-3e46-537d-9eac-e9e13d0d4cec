# Fusion trees:
#==============================================================================#
struct FusionTree{G<:Sector,N,M,L,T}
    uncoupled::NTuple{N,G}
    coupled::G
    innerlines::NTuple{M,G} # M = N-2
    vertices::NTuple{L,T} # L = N-1
end
FusionTree{G}(uncoupled::NTuple{N,Any},
                coupled,
                innerlines,
                vertices = ntuple(n->nothing, StaticLength(N)-StaticLength(1))
                ) where {G<:Sector,N} =
    fusiontreetype(G, StaticLength(N))(map(s->convert(G,s),uncoupled),
        convert(G,coupled), map(s->convert(G,s), innerlines), vertices)
FusionTree(uncoupled::NTuple{N,G},
            coupled::G,
            innerlines,
            vertices = ntuple(n->nothing, StaticLength(N)-StaticLength(1))
            ) where {G<:Sector,N} =
    fusiontreetype(G, StaticLength(N))(uncoupled, coupled, innerlines, vertices)

function FusionTree{G}(uncoupled::NTuple{N}, coupled = one(G)) where {G<:Sector, N}
    FusionStyle(G) isa Abelian ||
        error("fusion tree requires inner lines if `FusionStyle(G) <: NonAbelian`")
    FusionTree{G}(map(s->convert(G,s), uncoupled), convert(G, coupled),
                    _abelianinner(map(s->convert(G,s),(uncoupled..., dual(coupled)))))
end
function FusionTree(uncoupled::NTuple{N,G}, coupled::G = one(G)) where {G<:Sector, N}
    FusionStyle(G) isa Abelian ||
        error("fusion tree requires inner lines if `FusionStyle(G) <: NonAbelian`")
    FusionTree{G}(uncoupled, coupled, _abelianinner((uncoupled..., dual(coupled))))
end

# Properties
sectortype(::Type{<:FusionTree{G}}) where {G<:Sector} = G
FusionStyle(::Type{<:FusionTree{G}}) where {G<:Sector} = FusionStyle(G)
Base.length(::Type{<:FusionTree{<:Sector,N}}) where {N} = N

sectortype(t::FusionTree) = sectortype(typeof(t))
FusionStyle(t::FusionTree) = FusionStyle(typeof(t))
Base.length(t::FusionTree) = length(typeof(t))

# Hashing, important for using fusion trees as key in a dictionary
function Base.hash(f::FusionTree{G}, h::UInt) where {G}
    if FusionStyle(G) isa Abelian
        hash(f.uncoupled, hash(f.coupled, h))
    elseif FusionStyle(G) isa SimpleNonAbelian
        hash(f.innerlines, hash(f.uncoupled, hash(f.coupled, h)))
    else
        hash(f.vertices, hash(f.innerlines, hash(f.uncoupled, hash(f.coupled, h))))
    end
end
function Base.isequal(f1::FusionTree{G,N}, f2::FusionTree{G,N}) where {G,N}
    f1.coupled == f2.coupled || return false
    @inbounds for i = 1:N
        f1.uncoupled[i] == f2.uncoupled[i] || return false
    end
    if FusionStyle(G) isa SimpleNonAbelian
        @inbounds for i=1:N-2
            f1.innerlines[i] == f2.innerlines[i] || return false
        end
    end
    if FusionStyle(G) isa DegenerateNonAbelian
        @inbounds for i=1:N-1
            f1.vertices[i] == f2.vertices[i] || return false
        end
    end
    return true
end
Base.isequal(f1::FusionTree{G1,N1}, f2::FusionTree{G2,N2}) where {G1,G2,N1,N2} = false

# Facilitate getting correct fusion tree types
Base.@pure fusiontreetype(::Type{G}, ::StaticLength{0}) where {G<:Sector} =
    FusionTree{G, 0, 0, 0, vertex_labeltype(G)}
Base.@pure fusiontreetype(::Type{G}, ::StaticLength{1}) where {G<:Sector} =
    FusionTree{G, 1, 0, 0, vertex_labeltype(G)}
Base.@pure fusiontreetype(::Type{G}, ::StaticLength{2}) where {G<:Sector} =
    FusionTree{G, 2, 0, 1, vertex_labeltype(G)}
Base.@pure fusiontreetype(::Type{G}, ::StaticLength{N}) where {G<:Sector, N} =
    _fusiontreetype(G, StaticLength(N),
        StaticLength(N) - StaticLength(2), StaticLength(N) - StaticLength(1))
Base.@pure _fusiontreetype(::Type{G}, ::StaticLength{N}, ::StaticLength{M},
                            ::StaticLength{L}) where {G<:Sector, N, M, L} =
    FusionTree{G,N,M,L,vertex_labeltype(G)}

# converting to actual array
function Base.convert(::Type{Array}, f::FusionTree{G, 0}) where {G}
    T = eltype(fusiontensor(one(G), one(G), one(G)))
    return fill(one(T), 1)
end
function Base.convert(::Type{Array}, f::FusionTree{G, 1}) where {G}
    T = eltype(fusiontensor(one(G), one(G), one(G)))
    return copyto!(Matrix{T}(undef, dim(f.coupled), dim(f.coupled)), I)
end
Base.convert(::Type{Array}, f::FusionTree{G,2}) where {G} =
    fusiontensor(f.uncoupled[1], f.uncoupled[2], f.coupled, f.vertices[1])

function Base.convert(::Type{Array}, f::FusionTree{G}) where {G}
    tailout = (f.innerlines[1], TupleTools.tail2(f.uncoupled)...)
    ftail = FusionTree(tailout, f.coupled, Base.tail(f.innerlines), Base.tail(f.vertices))
    Ctail = convert(Array, ftail)
    C1 = fusiontensor(f.uncoupled[1], f.uncoupled[2], f.innerlines[1], f.vertices[1])
    dtail = size(Ctail)
    d1 = size(C1)
    C = reshape(C1, d1[1]*d1[2], d1[3]) *
            reshape(Ctail, dtail[1], prod(Base.tail(dtail)))
    return reshape(C, (d1[1], d1[2], Base.tail(dtail)...))
end

# Show methods
function Base.show(io::IO, t::FusionTree{G,N,M,K,Nothing}) where {G<:Sector,N,M,K}
    print(IOContext(io, :typeinfo => G), "FusionTree{", G, "}(",
        t.uncoupled, ", ", t.coupled, ", ", t.innerlines, ")")
end
function Base.show(io::IO, t::FusionTree{G}) where {G<:Sector}
    print(IOContext(io, :typeinfo => G), "FusionTree{", G, "}(",
        t.uncoupled, ", ", t.coupled, ", ", t.innerlines, ", ", t.vertices, ")")
end

# Manipulate fusion trees
include("manipulations.jl")

# Fusion tree iterators
include("iterator.jl")



# auxiliary routines
# _abelianinner: generate the inner indices for given outer indices in the abelian case
_abelianinner(outer::Tuple{}) = ()
_abelianinner(outer::Tuple{G}) where {G<:Sector} =
    outer[1] == one(G) ? () : throw(SectorMismatch())
_abelianinner(outer::Tuple{G,G}) where {G<:Sector} =
    outer[1] == dual(outer[2]) ? () : throw(SectorMismatch())
_abelianinner(outer::Tuple{G,G,G}) where {G<:Sector} =
    first(⊗(outer...)) == one(G) ? () : throw(SectorMismatch())
function _abelianinner(outer::NTuple{N,G}) where {G<:Sector,N}
    c = first(outer[1] ⊗ outer[2])
    return (c, _abelianinner((c, TupleTools.tail2(outer)...))...)
end
