# import TensorOperations: checked_similar_from_indices, scalar, isblascontractable, add!, contract!, unsafe_contract!

# Add support for TensorOperations.jl
function checked_similar_from_indices(tC, ::Type{T}, p1::IndexTuple{N₁}, p2::IndexTuple{N₂},
        t::AbstractTensorMap{S}) where {T,S<:IndexSpace,N₁,N₂}

    cod = ProductSpace{S,N₁}(space.(Ref(t), p1))
    dom = ProductSpace{S,N₂}(dual.(space.(Ref(t), p2)))
    A = similarstoragetype(t, T)

    if tC !== nothing && (tC isa TensorMap{S,N₁,N₂}) && eltype(tC) == T &&
        codomain(tC) == cod && domain(tC) == dom && storagetype(tC) == A
        G = sectortype(S)
        if G === Trivial
            return tC::TensorMap{S,N₁,N₂,G,A,Nothing,Nothing}
        else
            F₁ = fusiontreetype(G, StaticLength(N₁))
            F₂ = fusiontreetype(G, StaticLength(N₂))
            return tC::TensorMap{S,N₁,N₂,G,SectorDict{G,A},F₁,F₂}
        end
    else
        tC = similar(t, T, cod←dom)
        return tC
    end
end

function checked_similar_from_indices(tC, ::Type{T}, oindA::IndexTuple, oindB::IndexTuple,
    p1::IndexTuple{N₁}, p2::IndexTuple{N₂}, tA::AbstractTensorMap{S},
    tB::AbstractTensorMap{S}) where {T, S<:IndexSpace,N₁,N₂}

    spaces = (space.(Ref(tA), oindA)..., space.(Ref(tB), oindB)...)
    cod = ProductSpace{S,N₁}(getindex.(Ref(spaces), p1))
    dom = ProductSpace{S,N₂}(dual.(getindex.(Ref(spaces), p2)))
    A = similarstoragetype(tA, T)
    @assert A === similarstoragetype(tB, T)

    if tC !== nothing && (tC isa TensorMap{S,N₁,N₂}) && eltype(tC) == T &&
        codomain(tC) == cod && domain(tC) == dom && storagetype(tC) == A
        G = sectortype(S)
        if G === Trivial
            return tC::TensorMap{S,N₁,N₂,G,A,Nothing,Nothing}
        else
            F₁ = fusiontreetype(G, StaticLength(N₁))
            F₂ = fusiontreetype(G, StaticLength(N₂))
            return tC::TensorMap{S,N₁,N₂,G,SectorDict{G,A},F₁,F₂}
        end
    else
        tC = similar(tA, T, cod←dom)
        return tC
    end
end

function has_shared_permuteind(t::AbstractTensorMap{S}, p1::IndexTuple{N₁}, p2::IndexTuple{N₂}) where {S,N₁,N₂}
    if p1 === codomainind(t) && p2 === domainind(t)
        return true
    elseif isa(t, TensorMap) && sectortype(S) === Trivial
        stridet = i->stride(t[], i)
        sizet = i->size(t[], i)
        canfuse1, d1, s1 = TO._canfuse(sizet.(p1), stridet.(p1))
        canfuse2, d2, s2 = TO._canfuse(sizet.(p2), stridet.(p2))
        return canfuse1 && canfuse2 && s1 == 1 && (d2 == 1 || s2 == d1)
    elseif isa(t, AdjointTensorMap)
        p1′ = adjointtensorindices(t, p2)
        p2′ = adjointtensorindices(t, p1)
        return has_shared_permuteind(t', p1′, p2′)
    else
        return false
    end
end

function cached_permuteind(sym::Symbol, t::TensorMap{S},
                            p1::IndexTuple{N₁},  p2::IndexTuple{N₂}=()) where {S,N₁,N₂}
    cod = ProductSpace{S,N₁}(map(n->space(t, n), p1))
    dom = ProductSpace{S,N₂}(map(n->dual(space(t, n)), p2))

    # share data if possible
    if p1 === codomainind(t) && p2 === domainind(t)
        return t
    elseif isa(t, TensorMap) && sectortype(S) === Trivial
        stridet = i->stride(t[], i)
        sizet = i->size(t[], i)
        canfuse1, d1, s1 = TensorOperations._canfuse(sizet.(p1), stridet.(p1))
        canfuse2, d2, s2 = TensorOperations._canfuse(sizet.(p2), stridet.(p2))
        if canfuse1 && canfuse2 && s1 == 1 && (d2 == 1 || s2 == d1)
            return TensorMap(reshape(t.data, dim(cod), dim(dom)), cod, dom)
        end
    end
    # general case
    @inbounds begin
        tp = TO.cached_similar_from_indices(sym, eltype(t), p1, p2, t, :N)
        return permuteind!(tp, t, p1, p2)
    end
end

function cached_permuteind(sym::Symbol, t::AdjointTensorMap{S},
                            p1::IndexTuple{N₁},  p2::IndexTuple{N₂}=()) where {S,N₁,N₂}

    p1′ = adjointtensorindices(t, p2)
    p2′ = adjointtensorindices(t, p1)
    adjoint(cached_permuteind(sym, adjoint(t), p1′, p2′))
end

scalar(t::AbstractTensorMap{S}) where {S<:IndexSpace} =
    dim(codomain(t)) == dim(domain(t)) == 1 ?
        first(blocks(t))[2][1,1] : throw(SpaceMismatch())

function add!(α, tsrc::AbstractTensorMap{S}, β, tdst::AbstractTensorMap{S,N₁,N₂},
     p1::IndexTuple{N₁}, p2::IndexTuple{N₂}) where {S,N₁,N₂}
    # TODO: check Frobenius-Schur indicators!, and add fermions!
    @boundscheck begin
        all(i->space(tsrc, p1[i]) == space(tdst, i), 1:N₁) ||
            throw(SpaceMismatch("tsrc = $(codomain(tsrc))←$(domain(tsrc)),
            tdst = $(codomain(tdst))←$(domain(tdst)), p1 = $(p1), p2 = $(p2)"))
        all(i->space(tsrc, p2[i]) == space(tdst, N₁+i), 1:N₂) ||
            throw(SpaceMismatch("tsrc = $(codomain(tsrc))←$(domain(tsrc)),
            tdst = $(codomain(tdst))←$(domain(tdst)), p1 = $(p1), p2 = $(p2)"))
    end

    G = sectortype(S)
    if G === Trivial
        cod = codomain(tsrc)
        dom = domain(tsrc)
        n = length(cod)
        pdata = (p1..., p2...)
        axpby!(α, permutedims(tsrc[], pdata), β, tdst[])
    elseif FusionStyle(G) isa Abelian
        K = Threads.nthreads()
        if K > 1
            let iterator = fusiontrees(tsrc)
                Threads.@threads for k = 1:K
                    counter = 0
                    for (f1,f2) in iterator
                        counter += 1
                        if mod1(counter, K) == k
                            _addabelianblock!(α, tsrc, β, tdst, p1, p2, f1, f2)
                        end
                    end
                end
            end
        else # debugging is easier this way
            for (f1,f2) in fusiontrees(tsrc)
                _addabelianblock!(α, tsrc, β, tdst, p1, p2, f1, f2)
            end
        end
    else
        cod = codomain(tsrc)
        dom = domain(tsrc)
        n = length(cod)
        pdata = (p1...,p2...)
        if iszero(β)
            fill!(tdst, β)
        elseif β != 1
            mul!(tdst, β, tdst)
        end
        for (f1,f2) in fusiontrees(tsrc)
            for ((f1′,f2′), coeff) in permute(f1, f2, p1, p2)
                @inbounds for i in p2
                    if i <= n && !isdual(cod[i])
                        b = f1.uncoupled[i]
                        coeff *= frobeniusschur(b) #*fermionparity(b)
                    end
                end
                @inbounds for i in p1
                    if i > n && isdual(dom[i-n])
                        b = f2.uncoupled[i-n]
                        coeff /= frobeniusschur(b) #*fermionparity(b)
                    end
                end
                @inbounds axpy!(α*coeff, permutedims(tsrc[f1,f2], pdata), tdst[f1′,f2′])
            end
        end
    end
    return tdst
end

function _addabelianblock!(α, tsrc::AbstractTensorMap{S},
                            β, tdst::AbstractTensorMap{S,N₁,N₂},
                            p1::IndexTuple{N₁}, p2::IndexTuple{N₂},
                            f1::FusionTree, f2::FusionTree) where {S,N₁,N₂}
    cod = codomain(tsrc)
    dom = domain(tsrc)
    n = length(cod)
    (f1′,f2′), coeff = first(permute(f1, f2, p1, p2))
    @inbounds for i in p2
        if i <= n && !isdual(cod[i])
            b = f1.uncoupled[i]
            coeff *= frobeniusschur(b) #*fermionparity(b)
        end
    end
    @inbounds for i in p1
        if i > n && isdual(dom[i-n])
            b = f2.uncoupled[i-n]
            coeff /= frobeniusschur(b) #*fermionparity(b)
        end
    end
    pdata = (p1...,p2...)
    @inbounds axpby!(α*coeff, permutedims(tsrc[f1,f2], pdata), β, tdst[f1′,f2′])
end

function trace!(α, tsrc::AbstractTensorMap{S}, β, tdst::AbstractTensorMap{S,N₁,N₂},
                p1::IndexTuple{N₁}, p2::IndexTuple{N₂},
                q1::IndexTuple{N₃}, q2::IndexTuple{N₃}) where {S,N₁,N₂,N₃}
    # TODO: check Frobenius-Schur indicators!, and  add fermions!
    @boundscheck begin
        all(i->space(tsrc, p1[i]) == space(tdst, i), 1:N₁) ||
            throw(SpaceMismatch("trace: tsrc = $(codomain(tsrc))←$(domain(tsrc)),
                    tdst = $(codomain(tdst))←$(domain(tdst)), p1 = $(p1), p2 = $(p2)"))
        all(i->space(tsrc, p2[i]) == space(tdst, N₁+i), 1:N₂) ||
            throw(SpaceMismatch("trace: tsrc = $(codomain(tsrc))←$(domain(tsrc)),
                    tdst = $(codomain(tdst))←$(domain(tdst)), p1 = $(p1), p2 = $(p2)"))
        all(i->space(tsrc, q1[i]) == dual(space(tsrc, q2[i])), 1:N₃) ||
            throw(SpaceMismatch("trace: tsrc = $(codomain(tsrc))←$(domain(tsrc)),
                    q1 = $(p1), q2 = $(q2)"))
    end

    G = sectortype(S)
    if G === Trivial
        cod = codomain(tsrc)
        dom = domain(tsrc)
        n = length(cod)
        pdata = (p1..., p2...)
        TO._trace!(α, tsrc[], β, tdst[], pdata, q1, q2)
    # elseif FusionStyle(G) isa Abelian
    # TODO: is it worth multithreading Abelian case for traces?
    else
        cod = codomain(tsrc)
        dom = domain(tsrc)
        n = length(cod)
        pdata = (p1...,p2...)
        if iszero(β)
            fill!(tdst, β)
        elseif β != 1
            mul!(tdst, β, tdst)
        end
        r1 = (p1..., q1...)
        r2 = (p2..., q2...)
        for (f1,f2) in fusiontrees(tsrc)
            for ((f1′,f2′), coeff) in permute(f1, f2, r1, r2)
                f1′′, g1 = split(f1′, StaticLength(N₁))
                f2′′, g2 = split(f2′, StaticLength(N₂))
                if g1 == g2
                    @inbounds for i in r2
                        if i <= n && !isdual(cod[i])
                            b = f1.uncoupled[i]
                            coeff *= frobeniusschur(b) #*fermionparity(b)
                        end
                    end
                    @inbounds for i in r1
                        if i > n && isdual(dom[i-n])
                            b = f2.uncoupled[i-n]
                            coeff /= frobeniusschur(b) #*fermionparity(b)
                        end
                    end
                    coeff *= dim(g1.coupled)/dim(g1.uncoupled[1])
                    TO._trace!(α*coeff, tsrc[f1,f2], true, tdst[f1′′,f2′′], pdata, q1, q2)
                end
            end
        end
    end
    return tdst
end

# TODO: contraction with either A or B a rank (1,1) tensor does not require to
# permute the fusion tree and should therefore be special cased. This will speed
# up MPS algorithms
function contract!(α, A::AbstractTensorMap{S}, B::AbstractTensorMap{S},
                    β, C::AbstractTensorMap{S},
                    oindA::IndexTuple{N₁}, cindA::IndexTuple,
                    oindB::IndexTuple{N₂}, cindB::IndexTuple,
                    p1::IndexTuple, p2::IndexTuple,
                    syms::Union{Nothing, NTuple{3,Symbol}} = nothing) where {S,N₁,N₂}
    if syms === nothing
        A′ = permuteind(A, oindA, cindA)
        B′ = permuteind(B, cindB, oindB)
    else
        A′ = cached_permuteind(syms[1], A, oindA, cindA)
        B′ = cached_permuteind(syms[2], B, cindB, oindB)
    end
    ipC = TupleTools.invperm((p1..., p2...))
    oindAinC = TupleTools.getindices(ipC, ntuple(identity, StaticLength(N₁)))
    oindBinC = TupleTools.getindices(ipC, ntuple(n->n+length(oindA), StaticLength(N₂)))
    if has_shared_permuteind(C, oindAinC, oindBinC)
        C′ = permuteind(C, oindAinC, oindBinC)
        mul!(C′, A′, B′, α, β)
    else
        if syms === nothing
            C′ = A′*B′
        else
            p1′ = ntuple(identity, StaticLength(N₁))
            p2′ = N₁ .+ ntuple(identity, StaticLength(N₂))
            TC = eltype(C)
            C′ = TO.cached_similar_from_indices(syms[3], TC, oindA, oindB, p1′, p2′, A, B, :N, :N)
            mul!(C′, A′, B′)
        end
        add!(α, C′, β, C, p1, p2)
    end
    return C
end

# # Compatibility layer for working with the `@tensor` macro from TensorOperations
function TO.checked_similar_from_indices(C, T::Type,
    p1::IndexTuple, p2::IndexTuple, A::AbstractTensorMap, CA::Symbol = :N)
    if CA == :N
        checked_similar_from_indices(C, T, p1, p2, A)
    else
        p1 = adjointtensorindices(A, p1)
        p2 = adjointtensorindices(A, p2)
        checked_similar_from_indices(C, T, p1, p2, adjoint(A))
    end
end

function TO.checked_similar_from_indices(C, T::Type,
    poA::IndexTuple, poB::IndexTuple,
    p1::IndexTuple, p2::IndexTuple,
    A::AbstractTensorMap, B::AbstractTensorMap, CA::Symbol = :N, CB::Symbol = :N)

    if CA == :N && CB == :N
        checked_similar_from_indices(C, T, poA, poB, p1, p2, A, B)
    elseif CA == :C && CB == :N
        poA = adjointtensorindices(A, poA)
        checked_similar_from_indices(C, T, poA, poB, p1, p2, adjoint(A), B)
    elseif CA == :N && CB == :C
        poB = adjointtensorindices(B, poB)
        checked_similar_from_indices(C, T, poA, poB, p1, p2, A, adjoint(B))
    else
        poA = adjointtensorindices(A, poA)
        poB = adjointtensorindices(B, poB)
        checked_similar_from_indices(C, T, poA, poB, p1, p2, adjoint(A), adjoint(B))
    end
end

TO.scalar(t::AbstractTensorMap) = scalar(t)

function TO.add!(α, tsrc::AbstractTensorMap{S}, CA::Symbol, β,
    tdst::AbstractTensorMap{S,N₁,N₂}, p1::IndexTuple, p2::IndexTuple) where {S,N₁,N₂}

    if CA == :N
        p = (p1..., p2...)
        pl = TupleTools.getindices(p, codomainind(tdst))
        pr = TupleTools.getindices(p, domainind(tdst))
        add!(α, tsrc, β, tdst, pl, pr)
    else
        p = adjointtensorindices(tsrc, (p1..., p2...))
        pl = TupleTools.getindices(p, codomainind(tdst))
        pr = TupleTools.getindices(p, domainind(tdst))
        add!(α, adjoint(tsrc), β, tdst, pl, pr)
    end
    return tdst
end

function TO.trace!(α, tsrc::AbstractTensorMap{S}, CA::Symbol, β,
    tdst::AbstractTensorMap{S,N₁,N₂}, p1::IndexTuple, p2::IndexTuple,
    q1::IndexTuple, q2::IndexTuple) where {S,N₁,N₂}

    if CA == :N
        p = (p1..., p2...)
        pl = TupleTools.getindices(p, codomainind(tdst))
        pr = TupleTools.getindices(p, domainind(tdst))
        trace!(α, tsrc, β, tdst, pl, pr, q1, q2)
    else
        p = adjointtensorindices(tsrc, (p1..., p2...))
        pl = TupleTools.getindices(p, codomainind(tdst))
        pr = TupleTools.getindices(p, domainind(tdst))
        q1 = adjointtensorindices(tsrc, q1)
        q2 = adjointtensorindices(tsrc, q2)
        trace!(α, adjoint(tsrc), β, tdst, pl, pr, q1, q2)
    end
    return tdst
end

function TO.contract!(α,
    tA::AbstractTensorMap{S}, CA::Symbol,
    tB::AbstractTensorMap{S}, CB::Symbol,
    β, tC::AbstractTensorMap{S,N₁,N₂},
    oindA::IndexTuple, cindA::IndexTuple,
    oindB::IndexTuple, cindB::IndexTuple,
    p1::IndexTuple, p2::IndexTuple,
    syms::Union{Nothing, NTuple{3,Symbol}} = nothing) where {S,N₁,N₂}

    p = (p1..., p2...)
    pl = ntuple(n->p[n], StaticLength(N₁))
    pr = ntuple(n->p[N₁+n], StaticLength(N₂))
    if CA == :N && CB == :N
        contract!(α, tA, tB, β, tC, oindA, cindA, oindB, cindB, pl, pr, syms)
    elseif CA == :N && CB == :C
        oindB = adjointtensorindices(tB, oindB)
        cindB = adjointtensorindices(tB, cindB)
        contract!(α, tA, tB', β, tC, oindA, cindA, oindB, cindB, pl, pr, syms)
    elseif CA == :C && CB == :N
        oindA = adjointtensorindices(tA, oindA)
        cindA = adjointtensorindices(tA, cindA)
        contract!(α, tA', tB, β, tC, oindA, cindA, oindB, cindB, pl, pr, syms)
    elseif CA == :C && CB == :C
        oindA = adjointtensorindices(tA, oindA)
        cindA = adjointtensorindices(tA, cindA)
        oindB = adjointtensorindices(tB, oindB)
        cindB = adjointtensorindices(tB, cindB)
        contract!(α, tA', tB', β, tC, oindA, cindA, oindB, cindB, pl, pr, syms)
    else
        error("unknown conjugation flags: $CA and $CB")
    end
    return tC
end
