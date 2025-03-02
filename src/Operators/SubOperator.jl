function checkbounds(A::Operator, inds...)
    checkbounds(Bool, A, inds...) || throw(BoundsError(A,inds))
    nothing
end

checkbounds(::Type{Bool}, A::Operator,kr::Colon) = true

checkbounds(::Type{Bool}, A::Operator,kr) =
    !(maximum(kr) > length(A) || minimum(kr) < 1)


checkbounds(::Type{Bool}, A::Operator,kr::Union{Colon,InfRanges},jr::Union{Colon,InfRanges}) = true

checkbounds(::Type{Bool}, A::Operator,kr::Union{Colon,InfRanges},jr) =
    !(maximum(jr) > size(A,2) || minimum(jr) < 1)

checkbounds(::Type{Bool}, A::Operator,kr,jr::Union{Colon,InfRanges}) =
    !(maximum(kr) > size(A,1)  || minimum(kr) < 1 )

function checkbounds(::Type{Bool}, A::Operator,kr,jr)
    (isempty(kr) || isempty(jr)) && return true
    (1 <= minimum(kr) <= maximum(kr) <= size(A,1)) &&
    (1 <= minimum(jr) <= maximum(jr) <= size(A,2))
end

checkbounds(::Type{Bool}, A::Operator,K::Block,J::Block) =
     1 ≤ first(K.n[1]) ≤ length(blocklengths(rangespace(A))) &&
     1 ≤ first(J.n[1]) ≤ length(blocklengths(domainspace(A)))

checkbounds(::Type{Bool}, A::Operator,K::BlockRange{1},J::BlockRange{1}) =
    isempty(K) || isempty(J) ||
        checkbounds(Bool, A, Block(maximum(K.indices[1])), Block(maximum(J.indices[1])))



## SubOperator

struct SubOperator{T,B,I,DI,BI} <: Operator{T}
    parent::B
    indexes::I
    dims::DI
    bandwidths::BI
end



function SubOperator(A,inds,dims,lu)
    checkbounds(A,inds...)
    SubOperator{eltype(A),typeof(A),typeof(inds),
                typeof(dims),typeof(lu)}(A,inds,dims,lu)
end

# work around strange bug with bool size
SubOperator(A,inds,dims::Tuple{Bool,Bool},lu) = SubOperator(A,inds,Int.(dims),lu)

function SubOperator(A,inds::NTuple{2,Block},lu)
    checkbounds(A,inds...)
    _SubOperator(A, inds, lu, domainspace(A), rangespace(A))
end
function _SubOperator(A, inds, lu, dsp, rsp)
    SubOperator(A,inds,(blocklengths(rsp)[inds[1].n[1]],
                        blocklengths(dsp)[inds[2].n[1]]),lu)
end

SubOperator(A, inds::NTuple{2,Block}) = SubOperator(A,inds,subblockbandwidths(A))
function SubOperator(A, inds::Tuple{BlockRange{1,R},BlockRange{1,R}}) where R
    checkbounds(A,inds...)
    _SubOperator(A, inds, domainspace(A), rangespace(A))
end
function _SubOperator(A, inds, dsp, rsp)
    dims = (sum(blocklengths(rsp)[inds[1].indices[1]]),
            sum(blocklengths(dsp)[inds[2].indices[1]]))
    SubOperator(A,inds,dims,(dims[1]-1,dims[2]-1))
end

# cannot infer ranges
SubOperator(A,inds,dims) = SubOperator(A,inds,dims,(dims[1]-1,dims[2]-1))
SubOperator(A,inds) = SubOperator(A,inds,map(length,inds))


convert(::Type{Operator{T}},SO::SubOperator) where {T} =
    SubOperator(Operator{T}(SO.parent),SO.indexes,SO.dims,SO.bandwidths)::Operator{T}

function view(A::Operator,kr::InfRanges,jr::InfRanges)
    @assert isinf(size(A,1)) && isinf(size(A,2))
    st=step(kr)
    if isbanded(A) && st==step(jr)  # Otherwise, its not a banded operator
        kr1=first(kr)
        jr1=first(jr)
        shft = kr1-jr1
        # working on the whole bandwidths tuple instead of
        # the individual bandwidths helps with type-inference,
        # e.g. if the bandwidth is inferred as
        # Union{NTuple{2,InfiniteCardinal{0}}, NTuple{2,Int}}
        bw = map(x -> x ÷ st, map(+, bandwidths(A), (-shft,shft)))
    else
        bw=(ℵ₀,ℵ₀)
    end
    SubOperator(A,(kr,jr),size(A),bw)
end

view(V::SubOperator, kr::AbstractRange, jr::AbstractRange) =
    view(V.parent,reindex(V,parentindices(V),(kr,jr))...)

function view(A::Operator, kr::AbstractRange, jr::AbstractRange)
    st=step(kr)
    if isbanded(A) && st == step(jr)
        kr1=first(kr)
        jr1=first(jr)
        shft = kr1-jr1
        # working on the whole bandwidths tuple instead of
        # the individual bandwidths helps with type-inference,
        # e.g. if the bandwidth is inferred as
        # Union{NTuple{2,InfiniteCardinal{0}}, NTuple{2,Int}}
        bw = map(x -> x ÷ st, map(+, bandwidths(A), (-shft,shft)))
        SubOperator(A,(kr,jr),(length(kr),length(jr)),bw)
    else
        SubOperator(A,(kr,jr))
    end
end


function view(A::Operator,kr::UnitRange,jr::UnitRange)
    if isbanded(A)
        shft=first(kr)-first(jr)
        # working on the whole bandwidths tuple instead of
        # the individual bandwidths helps with type-inference,
        # e.g. if the bandwidth is inferred as
        # Union{NTuple{2,InfiniteCardinal{0}}, NTuple{2,Int}}
        bw = map(+, bandwidths(A), (-shft,shft))
        SubOperator(A,(kr,jr),(length(kr),length(jr)),bw)
    else
        SubOperator(A,(kr,jr))
    end
end

view(A::Operator,::Colon,::Colon) = view(A,1:size(A,1),1:size(A,2))
view(A::Operator,::Colon,jr) = view(A,1:size(A,1),jr)
view(A::Operator,kr,::Colon) = view(A,kr,1:size(A,2))


view(A::Operator,K::Block,J::Block) = SubOperator(A,(K,J))
view(A::Operator,K::Block,j::Colon) = view(A,blockrows(A,K),j)
view(A::Operator,k::Colon,J::Block) = view(A,k,blockcols(A,J))
view(A::Operator, K::Block, j) = view(A,blockrows(A,Int(K)),j)
view(A::Operator, k, J::Block) = view(A,k,blockcols(A,Int(J))) #TODO: fix view
view(A::Operator,KR::BlockRange,JR::BlockRange) = SubOperator(A,(KR,JR))

view(A::Operator,k,j) = SubOperator(A,(k,j))

defaultgetindex(B::Operator,k::InfRanges, j::InfRanges) = view(B, k, j)
defaultgetindex(B::Operator,k::AbstractRange, j::InfRanges) = view(B, k, j)
defaultgetindex(B::Operator,k::InfRanges, j::AbstractRange) = view(B, k, j)

reindex(V, idxs, subidxs) = Base.reindex(idxs, subidxs)

reindex(A::Operator, B::Tuple{Block,Any}, kj::Tuple{Any,Any}) =
    (reindex(rangespace(A),(B[1],), (kj[1],))[1], reindex(domainspace(A),tail(B), tail(kj))[1])
# always reindex left-to-right, so if we have only a single tuple, then
# we must be the domainspace
reindex(A::Operator, B::Tuple{Block{1}}, kj::Tuple{Any}) = reindex(domainspace(A),B,kj)

reindex(A::Operator, B::Tuple{BlockRange1,Any}, kj::Tuple{Any,Any}) =
    (reindex(rangespace(A),(B[1],), (kj[1],))[1], reindex(domainspace(A),tail(B), tail(kj))[1])
# always reindex left-to-right, so if we have only a single tuple, then
# we must be the domainspace
reindex(A::Operator, B::Tuple{BlockRange1}, kj::Tuple{Any}) =
    reindex(domainspace(A),B,kj)
# Blocks are preserved under ranges
for TYP in (:Block,:BlockRange1,:(AbstractVector{Block{1}}))
    @eval begin
        reindex(A::Operator, B::Tuple{AbstractVector{Int},Any}, kj::Tuple{$TYP,Any}) =
            (reindex(rangespace(A), (B[1],), (kj[1],))[1], reindex(domainspace(A),tail(B), tail(kj))[1])
        reindex(A::Operator, B::Tuple{AbstractVector{Int}}, kj::Tuple{$TYP}) =
            reindex(domainspace(A),B,kj)
    end
end



view(V::SubOperator,kr::UnitRange,jr::UnitRange) = view(V.parent,reindex(V,parentindices(V),(kr,jr))...)
view(V::SubOperator,K::Block,J::Block) = view(V.parent,reindex(V,parentindices(V),(K,J))...)
view(V::SubOperator,KR::BlockRange,JR::BlockRange) = view(V.parent, reindex(V,parentindices(V),(KR,JR))...)
function view(V::SubOperator,::Type{FiniteRange},jr::AbstractVector{Int})
    cs = (isbanded(V) || isblockbandedbelow(V)) ? colstop(V,maximum(jr)) : mapreduce(j->colstop(V,j),max,jr)
    view(V,1:cs,jr)
end

view(V::SubOperator, kr, jr) = view(V.parent,reindex(V,parentindices(V),(kr,jr))...)
view(V::SubOperator,kr::InfRanges,jr::InfRanges) = view(V.parent,reindex(V,parentindices(V),(kr,jr))...)

view(A::SubOperator,::Colon,jr) = view(A,1:size(A,1),jr)

bandwidths(S::SubOperator) = S.bandwidths
function colstop(S::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}},j::Integer)
    cs = colstop(parent(S),parentindices(S)[2][j])
    kr = parentindices(S)[1]
    n = size(S,1)
    if cs < first(kr)
        0
    elseif cs ≥ last(kr)
        n
    else
        min(n,findfirst(isequal(cs),kr))
    end
end
function colstart(S::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}},j::Integer)
    cind = colstart(parent(S),parentindices(S)[2][j])
    ind = findfirst(==(cind), parentindices(S)[1])
    max(ind,1)
end
function rowstart(S::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}},j::Integer)
    rind = rowstart(parent(S),parentindices(S)[1][j])
    ind = findfirst(==(rind), parentindices(S)[2])
    max(1,ind)
end
function rowstop(S::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}},j::Integer)
    ind = rowstop(parent(S),parentindices(S)[1][j])
    findfirst(==(ind), parentindices(S)[2])
end


# blocks don't change
blockcolstop(S::SubOperator{<:Any,<:Any,Tuple{AbstractRange{Int},AbstractRange{Int}}},J::Integer) =
    blockcolstop(parent(S),J)

israggedbelow(S::SubOperator) = israggedbelow(parent(S))

# since blocks don't change with indexex, neither do blockbandwidths
blockbandwidths(S::SubOperator{<:Any,<:Any,NTuple{2,AbstractRange{Int}}}) =
    blockbandwidths(parent(S))
function blockbandwidths(S::SubOperator{<:Any,<:Any,NTuple{2,BlockRange1}})
    KR,JR = parentindices(S)
    l,u = blockbandwidths(parent(S))
    sh = first(KR).n[1]-first(JR).n[1]
    l-sh,u+sh
end

isblockbanded(S::SubOperator{<:Any,<:Any,NTuple{2,Block}}) = false
isbanded(S::SubOperator{<:Any,<:Any,NTuple{2,Block}}) = isbandedblockbanded(parent(S))
bandwidths(S::SubOperator{<:Any,<:Any,NTuple{2,Block}}) = subblockbandwidths(parent(S))
blockbandwidths(S::SubOperator{<:Any,<:Any,NTuple{2,Block}}) = 0,0

function BandedBlockBandedMatrix(::Type{Zeros}, S::SubOperator)
    kr,jr=parentindices(S)
    KO=parent(S)
    l,u=blockbandwidths(KO)
    λ,μ=subblockbandwidths(KO)

    rt=rangespace(KO)
    dt=domainspace(KO)
    k1,j1=isempty(kr) || isempty(jr) ? (first(kr),first(jr)) :
                                        reindex(S,parentindices(S),(1,1))

    # each row/column that we differ from the the block start shifts
    # the sub block inds
    J = block(dt,j1)
    K = block(rt,k1)
    jsh=j1-blockstart(dt,J)
    ksh=k1-blockstart(rt,K)

    rows,cols = blocklengths(rangespace(S)), blocklengths(domainspace(S))

    BandedBlockBandedMatrix(Zeros{eltype(KO)}(sum(rows),sum(cols)),
                                rows,cols, (l,u), (λ-jsh,μ+ksh))
end

function _BandedBlockBandedMatrixZeros(::Type{T}, KR, JR, (l,u), (λ,μ), rt, dt) where {T}
    J = first(JR)
    K = first(KR)
    bl_sh = Int(J) - Int(K)

    KBR = blocklengthrange(rt,KR)
    KJR = blocklengthrange(dt,JR)

    BandedBlockBandedMatrix(Zeros{T}(sum(KBR),sum(KJR)),
                                convert(AbstractVector{Int}, KBR),
                                convert(AbstractVector{Int}, KJR),
                                (l+bl_sh,u-bl_sh), (λ,μ))
end
function BandedBlockBandedMatrix(::Type{Zeros}, S::SubOperator{<:Any,<:Any,Tuple{BlockRange1,BlockRange1}})
    KR,JR = parentindices(S)
    KO = parent(S)
    l,u = blockbandwidths(KO)::Tuple{Int,Int}
    λ,μ = subblockbandwidths(KO)::Tuple{Int,Int}
    _BandedBlockBandedMatrixZeros(eltype(KO), KR, JR, (l,u), (λ,μ), rangespace(KO), domainspace(KO))
end


function domainspace(S::SubOperator)
    P =parent(S)
    sp=domainspace(P)
    kr=parentindices(S)[2]

    SubSpace{typeof(sp),typeof(kr),domaintype(sp),rangetype(sp)}(sp,kr)
end
function rangespace(S::SubOperator)
    P =parent(S)
    sp=rangespace(P)
    kr=parentindices(S)[1]

    SubSpace{typeof(sp),typeof(kr),domaintype(sp),rangetype(sp)}(sp,kr)
end

size(V::SubOperator) = V.dims
size(V::SubOperator,k::Int) = V.dims[k]

axes(V::SubOperator) = map(Base.OneTo, size(V))
axes(V::SubOperator, k::Integer) = k <= 2 ? axes(V)[k] : Base.OneTo(1)

unsafe_getindex(V::SubOperator,k::Integer,j::Integer) = V.parent[reindex(V,parentindices(V),(k,j))...]
function getindex(V::SubOperator,k::IntOrVectorIndices,j::IntOrVectorIndices)
    V.parent[reindex(V,parentindices(V),(k,j))...]
end
Base.parent(S::SubOperator) = S.parent
Base.parentindices(S::SubOperator) = S.indexes



for OP in (:isblockbanded,:isblockbandedabove,:isblockbandedbelow,
                :isbandedblockbanded,:isbandedblockbandedabove,
                :isbandedblockbandedbelow)
    @eval $OP(S::SubOperator) = $OP(parent(S))
end

# TODO: These should be removed as the general purpose case will work,
# once the notion of bandedness of finite dimensional operators is made sense of


_colstops(V) = Int[max(0,colstop(V,j)) for j=1:size(V,2)]

for TYP in (:RaggedMatrix, :Matrix)
    def_TYP = Symbol(:default_, TYP)
    @eval begin
        function $TYP(V::SubOperator)
            if isinf(size(V,1)) || isinf(size(V,2))
                error("Cannot convert $V to a $TYP")
            end
            A = parent(V)
            if isbanded(A)
                $TYP(BandedMatrix(V))
            else
                $def_TYP(V)
            end
        end

        function $TYP(V::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}})
            if isinf(size(V,1)) || isinf(size(V,2))
                error("Cannot convert $V to a $TYP")
            end
            A = parent(V)
            if isbanded(A)
                $TYP(BandedMatrix(V))
            elseif isbandedblockbanded(A)
                N = block(rangespace(A), last(parentindices(V)[1]))
                M = block(domainspace(A), last(parentindices(V)[2]))
                B = BandedBlockBandedMatrix(view(A, Block(1):N, Block(1):M))
                RaggedMatrix{eltype(V)}(view(B, parentindices(V)...), _colstops(V))
            else
                $def_TYP(V)
            end
        end
    end
end

# fast converts to banded matrices would be based on indices, not blocks
function BandedMatrix(S::SubOperator{<:Any,<:Any,Tuple{BlockRange1,BlockRange1}})
    A = parent(S)
    ds = domainspace(A)
    rs = rangespace(A)
    KR,JR = parentindices(S)
    BandedMatrix(view(A,
                      blockstart(rs,first(KR)):blockstop(rs,last(KR)),
                      blockstart(ds,first(JR)):blockstop(ds,last(JR))))
end




function mul_coefficients(A::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}}, b)
    if size(A,2) == size(b,1)
        AbstractMatrix(A)*b
    else
        AbstractMatrix(view(A,:,axes(b,1)))*b
    end
end
function mul_coefficients!(A::SubOperator{<:Any,<:Any,NTuple{2,UnitRange{Int}}}, b,
        temp = similar(b, promote_type(eltype(A), eltype(b)), size(A,1)))
    if size(A,2) == size(b,1)
        mul!(temp, AbstractMatrix(A), b)
    else
        mul!(temp, AbstractMatrix(view(A,:,axes(b,1))), b)
    end
    b .= temp
    return b
end
