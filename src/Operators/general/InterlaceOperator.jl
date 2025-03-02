##interlace block operators
function isboundaryrow(A,k)
    for j=1:size(A,2)
        if isafunctional(A[k,j])
            return true
        end
    end

    return false
end



domainscompatible(A::AbstractMatrix{T}) where {T<:Operator} = domainscompatible(map(domainspace,A))

function spacescompatible(A::AbstractMatrix{T}) where T<:Operator
    for k=1:size(A,1)
        if !spacescompatible(map(rangespace, @view A[k,:]))
            return false
        end
    end
    for k=1:size(A,2)
        if !spacescompatible(map(domainspace, @view A[:,k]))
            return false
        end
    end
    true
end

spacescompatible(A::VectorOrTupleOfOp) = spacescompatible(map(domainspace,A))

function domainspace(A::AbstractMatrix{T}) where T<:Operator
    if !spacescompatible(A)
        error("Cannot construct domainspace for $A as spaces are not compatible")
    end

    spl=map(domainspace, @view A[1,:])
    Space(spl)
end

function rangespace(A::VectorOrTupleOfOp)
    if !spacescompatible(A)
        error("Cannot construct rangespace for $A as domain spaces are not compatible")
    end
    spl=map(rangespace, A)
    ArraySpace(convert_vector_or_svector_promotetypes(spl), first(spl))
end

promotespaces(A::AbstractMatrix{<:Operator}) = promotespaces(Matrix(A))

function promotespaces(A::Matrix{<:Operator})
    isempty(A) && return A
    ret = similar(A) #TODO: promote might have different Array type
    for j=1:size(A,2)
        ret[:,j] = promotedomainspace(@view A[:,j])
    end
    for k=1:size(A,1)
        ret[k,:] = promoterangespace(@view ret[k,:])
    end

    # do a second loop as spaces might have been inferred
    # during range space
    for j=1:size(A,2)
        ret[:,j] = promotedomainspace(@view ret[:,j])
    end
    ret
end


## Interlace operator

struct InterlaceOperator{T,p,DS,RS,DI,RI,BI,BBW,A<:AbstractArray{<:Operator{T},p}} <: Operator{T}
    ops::A
    domainspace::DS
    rangespace::RS
    domaininterlacer::DI
    rangeinterlacer::RI
    bandwidths::BI
    blockbandwidths::BBW
    israggedbelow::Bool

    function InterlaceOperator(ops::A, ds::DS, rs::RS, dsi::DI, rsi::RI, bw::BI,
        blockbandwidths::BBW = bandwidthsmax(ops, blockbandwidths),
        israggedbelow::Bool = all(israggedbelow, ops)
        ) where {T,p,DS,RS,DI,RI,BI,BBW,A<:AbstractArray{<:Operator{T},p}}

        new{T,p,DS,RS,DI,RI,BI,BBW,A}(ops, ds, rs, dsi, rsi, bw, blockbandwidths, israggedbelow)
    end
end

const VectorInterlaceOperator = InterlaceOperator{T,1,DS,RS} where {T,DS,RS<:Space{D,R}} where {D,R<:AbstractVector}
const MatrixInterlaceOperator = InterlaceOperator{T,2,DS,RS} where {T,DS,RS<:Space{D,R}} where {D,R<:AbstractVector}

__interlace_ops_bandwidths(ops::AbstractMatrix) = bandwidths.(ops)
__interlace_ops_bandwidths(ops::Diagonal) = bandwidths.(parent(ops))
function __interlace_bandwidths_square(ops::AbstractMatrix, bw = __interlace_ops_bandwidths(ops))
    p=size(ops,1)
    l,u = 0,0
    for k=axes(ops,1), j=axes(ops,2)
        opbw = bw[k,j]
        l = max(l, p*opbw[1]+k-j)
        u = max(u, p*opbw[2]+j-k)
    end
    l,u
end
function __interlace_bandwidths_square(ops::Diagonal, bw = __interlace_ops_bandwidths(ops))
    p=size(ops,1)
    l,u = 0,0
    for k=axes(ops,1)
        opbw = bw[k]
        l = max(l, p*opbw[1])
        u = max(u, p*opbw[2])
    end
    l,u
end

# this is a hack to get constant-propagation in the indexing operation
_first(A) = A[1]
_second(A) = A[2]

_first(A::Diagonal) = parent(A)[1]
_second(A::Diagonal) = zero(eltype(A))

issquare(A) = size(A,1) == size(A,2)
issquare(A::Diagonal) = true

Base.@constprop :aggressive function interlace_bandwidths(ops::AbstractMatrix{<:Operator},
        ds, rs,
        allbanded = all(isbanded, ops),
        bw = allbanded ? __interlace_ops_bandwidths(ops) : nothing)

    dsi = interlacer(ds)
    rsi = interlacer(rs)

    if issquare(ops) && allbanded && # only support blocksize (1,) for now
            all(i->isa(i,AbstractFill) && getindex_value(i) == 1, dsi.blocks) &&
            all(i->isa(i,AbstractFill) && getindex_value(i) == 1, rsi.blocks)

        l,u = __interlace_bandwidths_square(ops, bw)
    elseif size(ops,1) == 1 && size(ops,2) == 2 && size(_first(ops),2) == 1
        # special case for example
        l,u = max(bandwidth(_first(ops),1),bandwidth(_second(ops),1)-1),bandwidth(_second(ops),2)+1
    else
        l,u = (dimension(rs)-1,dimension(ds)-1)  # not banded
    end

    l,u
end

function InterlaceOperator(ops::AbstractMatrix{<:Operator},ds::Space,rs::Space;
        # calculate bandwidths TODO: generalize
        bandwidths = interlace_bandwidths(ops, ds, rs),
        blockbandwidths = bandwidthsmax(ops, blockbandwidths),
        israggedbelow = all(israggedbelow, ops))

    dsi = interlacer(ds)
    rsi = interlacer(rs)

    T = promote_eltypeof(ops)
    opsm = ops isa AbstractMatrix{<:Operator{T}} ? ops :
                map(x -> strictconvert(Operator{T}, x), ops)
    InterlaceOperator(opsm,ds,rs,
                        cache(dsi),
                        cache(rsi),
                        bandwidths,
                        blockbandwidths,
                        israggedbelow)
end

Base.@constprop :aggressive function interlace_bandwidths(ops::VectorOrTupleOfOp, ds, rs, allbanded = all(isbanded, ops))
    p=size(ops,1)
    ax1 = first(axes(ops))
    if allbanded
        l,u = 0,0
        #TODO: this code assumes an interlace strategy that might not be right
        for k in ax1
            opbw = bandwidths(ops[k])
            l = max(l, p*opbw[1]+k-1)
            u = max(u, p*opbw[2]+1-k)
        end
    else
        l,u = (dimension(rs)-1,dimension(ds)-1)  # not banded
    end
    l,u
end

function InterlaceOperator(ops::VectorOrTupleOfOp, ds::Space, rs::Space;
        # calculate bandwidths
        bandwidths = interlace_bandwidths(ops, ds, rs),
        blockbandwidths = bandwidthsmax(ops, blockbandwidths),
        israggedbelow = all(israggedbelow, ops))

    T = promote_eltypeof(ops)
    opsabsv = convert_vector_or_svector(ops)
    opsv = opsabsv isa AbstractVector{<:Operator{T}} ? opsabsv :
            map(x -> convert(Operator{T}, x), opsabsv)
    InterlaceOperator(opsv,ds,rs,
                        cache(BlockInterlacer(tuple(blocklengths(ds)))),
                        cache(interlacer(rs)),
                        bandwidths,
                        blockbandwidths,
                        israggedbelow)
end

interlace_domainspace(ops::AbstractMatrix, ::Type{NoSpace}) = domainspace(ops)
interlace_domainspace(ops::AbstractMatrix, ::Type{DS}) where {DS} = DS(components(domainspace(ops)))
interlace_rangespace(ops::AbstractMatrix, ::Type{NoSpace}) = rangespace(@view ops[:,1])
interlace_rangespace(ops::RowVector, ::Type{NoSpace}) = rangespace(ops[1])
interlace_rangespace(ops::AbstractMatrix, ::Type{RS}) where {RS} = RS(rangespace(@view ops[:,1]).spaces)
interlace_rangespace(ops::RowVector, ::Type{RS}) where {RS} = RS(rangespace(ops[1]))

function InterlaceOperator(opsin::AbstractMatrix{<:Operator},
        ds::Type{DS}=NoSpace,rs::Type{RS}=ds) where {DS<:Space,RS<:Space}
    isempty(opsin) && throw(ArgumentError("Cannot create InterlaceOperator from an empty matrix"))
    ops=promotespaces(opsin)
    InterlaceOperator(ops, interlace_domainspace(ops, DS), interlace_rangespace(ops, RS))
end

function InterlaceOperator(opsin::AbstractVector{<:Operator})
    ops = convert_vector(promotedomainspace(opsin))
    InterlaceOperator(ops, domainspace(first(ops)), rangespace(ops))
end
Base.@constprop :aggressive function InterlaceOperator(opsin, promotedomain = true)
    ops = promotedomain ? promotedomainspace(opsin) : opsin
    InterlaceOperator(ops, domainspace(first(ops)), rangespace(ops))
end

InterlaceOperator(ops::AbstractArray, ds=NoSpace, rs=ds) =
    InterlaceOperator(Array{Operator{promote_eltypeof(ops)}, ndims(ops)}(ops), ds, rs)


function convert(::Type{Operator{T}},S::InterlaceOperator) where T
    if T == eltype(S)
        S
    else
        ops = map(x -> convert(Operator{T},x), S.ops)
        InterlaceOperator(ops,domainspace(S),rangespace(S),
                            S.domaininterlacer,S.rangeinterlacer,S.bandwidths,
                            S.blockbandwidths, S.israggedbelow)
    end
end



#TODO: More efficient to save bandwidth
bandwidths(M::InterlaceOperator) = M.bandwidths

blockbandwidths(M::InterlaceOperator) = M.blockbandwidths

function blockcolstop(M::InterlaceOperator,J::Integer)
    if isblockbandedbelow(M)
        Block(J + blockbandwidth(M,1))
    else
        mapreduce(op->blockcolstop(op,J),max,M.ops)
    end
end



function colstop(M::InterlaceOperator, j::Integer)
#    b=bandwidth(M,1)
    if isbandedbelow(M)
        min(j+bandwidth(M,1)::Int,size(M,1))::Int
    elseif isblockbandedbelow(M)
        J=block(domainspace(M), j)::Block{1}
        blockstop(rangespace(M), blockcolstop(M,J)::Block{1})::Int
    else #assume is raggedbelow
        K = 0
        (J,jj) = M.domaininterlacer[j]
        for N = 1:size(M.ops,1)
            cs = colstop(M.ops[N,J],jj)::Int
            if cs > 0
                K = max(K,findfirst((N,cs), M.rangeinterlacer)::Int)
            end
        end
        K
    end
end

israggedbelow(M::InterlaceOperator) = M.israggedbelow

getindex(op::InterlaceOperator,k::Integer,j::Integer) =
    error("Higher tensor InterlaceOperators not supported")

function getindex(op::InterlaceOperator{T,2},k::Integer,j::Integer) where {T}
    M,J = op.domaininterlacer[j]
    N,K = op.rangeinterlacer[k]
    op.ops[N,M][K,J]::T
end

# the domain is not interlaced
function getindex(op::InterlaceOperator{T,1},k::Integer,j::Integer) where T
    N,K = op.rangeinterlacer[k]
    op.ops[N][K,j]::T
end

function getindex(op::InterlaceOperator, k::Integer)
    if size(op,1) == 1
        op[1,k]
    elseif size(op,2) == 1
        op[k,1]
    else
        error("Only implemented for row/column operators.")
    end
end


findsub(cr,ν) = findall(x->x[1]==ν,cr)

function getindex(L::InterlaceOperator{T},kr::UnitRange) where T
    ret=zeros(T,length(kr))

    if size(L,1) == 1
        ds=domainspace(L)
        cr=cache(interlacer(ds))[kr]
    elseif size(L,2) == 1
        rs=rangespace(L)
        cr=cache(interlacer(rs))[kr]
    else
        error("Only implemented for row/column operators.")
    end

    for ν=1:length(L.ops)
        # indices of ret
        ret_kr=findsub(cr,ν)

        # block indices
        if !isempty(ret_kr)
            sub_kr=cr[ret_kr[1]][2]:cr[ret_kr[end]][2]

            axpy!(1.0,L.ops[ν][sub_kr],view(ret,ret_kr))
        end
    end
    ret
end

# overwritten for functions
# this won't work in 0.4 as expected, though the user
# should call vec anyways for 0.5 compatibility
function getindex(L::InterlaceOperator,k::Integer,j)
    if k==1 && size(L,1) == 1
        L[j]
    else
        defaultgetindex(L,k,j)
    end
end

function getindex(L::InterlaceOperator,k,j::Integer)
    if j==1 && size(L,2) == 1
        L[k]
    else
        defaultgetindex(L,k,j)
    end
end

#####
# optimized copy routine for when there is a single domainspace
# and no interlacing of the columns is necessary
# this is especially important for \
######
for TYP in (:BandedMatrix, :BlockBandedMatrix, :BandedBlockBandedMatrix, :RaggedMatrix,
                :Matrix)
    @eval begin
        function $TYP(S::SubOperator{T,<:InterlaceOperator{T,1},NTuple{2,UnitRange{Int}}}) where {T}
            kr,jr=parentindices(S)
            L=parent(S)

            ret=$TYP(Zeros, S)

            ds=domainspace(L)
            rs=rangespace(L)
            cr=cache(interlacer(rs))[kr]
            for ν=1:length(L.ops)
                # indices of ret
                ret_kr=findsub(cr,ν)

                # block indices
                if !isempty(ret_kr)
                    sub_kr=cr[ret_kr[1]][2]:cr[ret_kr[end]][2]

                    axpy!(1.0,view(L.ops[ν],sub_kr,jr),view(ret,ret_kr,:))
                end
            end
            ret
        end

        function $TYP(S::SubOperator{T,<:InterlaceOperator{T,2},NTuple{2,UnitRange{Int}}}) where {T}
            kr,jr=parentindices(S)
            L=parent(S)

            ret=$TYP(Zeros, S)

            if isempty(kr) || isempty(jr)
                return ret
            end

            ds=domainspace(L)
            rs=rangespace(L)
            cr=L.rangeinterlacer[kr]
            cd=L.domaininterlacer[jr]
            for ν=1:size(L.ops,1),μ=1:size(L.ops,2)
                # indices of ret
                ret_kr=findsub(cr,ν)
                ret_jr=findsub(cd,μ)

                # block indices
                if !isempty(ret_kr) && !isempty(ret_jr)
                    sub_kr=cr[ret_kr[1]][2]:cr[ret_kr[end]][2]
                    sub_jr=cd[ret_jr[1]][2]:cd[ret_jr[end]][2]

                    axpy!(1.0,view(L.ops[ν,μ],sub_kr,sub_jr),
                                   view(ret,ret_kr,ret_jr))
                end
            end
            ret
        end
    end
end


## Build block-by-block
function blockbanded_interlace_convert!(S,ret)
    T = eltype(S)
    KR,JR = parentindices(S)
    l,u=blockbandwidths(S)::Tuple{Int,Int}

    M = map(op -> begin
                KR_size = Block.(Int(first(KR)):min(Int(last(KR)),blocksize(op,1)))
                JR_size = Block.(Int(first(JR)):min(Int(last(JR)),blocksize(op,2)))
                BlockBandedMatrix(view(op, KR_size, JR_size))
            end, parent(S).ops)

    for J=blockaxes(ret,2),K=blockcolrange(ret,J)
        Bs=view(ret,K,J)
        j = 0
        for ξ=1:size(M,2)
            k = 0
            m = 0
            for κ=1:size(M,1)
                if K.n[1] ≤ blocksize(M[κ,ξ],1) && J.n[1] ≤ blocksize(M[κ,ξ],2)
                    MKJ = M[κ,ξ][K,J]::Matrix{T}
                    n,m = size(MKJ)
                    Bs[k+1:k+n,j+1:j+m] = MKJ
                    k += n
                end
            end
            j += m
        end
    end
    ret
end

for d in (:1,:2)
    @eval BlockBandedMatrix(S::SubOperator{T,<:InterlaceOperator{T,$d},
                          Tuple{BlockRange1,BlockRange1}}) where {T} =
    blockbanded_interlace_convert!(S, BlockBandedMatrix(Zeros, S))
end





domainspace(IO::InterlaceOperator) = IO.domainspace
rangespace(IO::InterlaceOperator) = IO.rangespace

#tests whether an operator can be made into a column
iscolop(op) = isconstop(op)
iscolop(::Multiplication) = true

promotedomainspace(A::InterlaceOperator{T,1},sp::Space) where {T} =
    InterlaceOperator(map(op->promotedomainspace(op,sp),A.ops))


interlace(A::AbstractArray{<:Operator}) = InterlaceOperator(A)
interlace(A::Tuple{Operator,Vararg{Operator}}) = InterlaceOperator(A)

const OperatorTypes = Union{Operator,Fun,Number,UniformScaling}



operators(A::InterlaceOperator) = A.ops
operators(A::Matrix{<:Operator}) = A
operators(A::Operator) = [A]

Base.vcat(A::MatrixInterlaceOperator...) =
    InterlaceOperator(vcat(map(operators,A)...))

__vcat(a::VectorInterlaceOperator, b::OperatorTypes...) = (a.ops..., __vcat(b...)...)
__vcat(a::OperatorTypes, b::OperatorTypes...) = (a, __vcat(b...)...)
__vcat() = ()
function _vcat(A::OperatorTypes...)
    Av = __vcat(A...)
    InterlaceOperator(map(x -> convert(Operator, x), Av))
end



Base.hcat(A::Union{VectorInterlaceOperator,MatrixInterlaceOperator}...) =
    InterlaceOperator(hcat(map(A->A.ops,A)...))
_hcat(A::OperatorTypes...) = InterlaceOperator(hnocat(A...))
function _hvcat(rows::Tuple{Vararg{Int}},as::OperatorTypes...)
    # Based on Base
    nbr = length(rows)  # number of block rows
    rs = Array{Any,1}(undef, nbr)
    a = 1
    for i = 1:nbr
        rs[i] = hcat(map(op -> strictconvert(Operator,op),as[a:a-1+rows[i]])...)
        a += rows[i]
    end
    vcat(rs...)
end

Base.vcat(A::Operator, B::OperatorTypes...) = _vcat(A, B...)
Base.hcat(A::Operator, B::OperatorTypes...) = _hcat(A, B...)
Base.hvcat(rows::Tuple{Vararg{Int}}, A::Operator, B::OperatorTypes...) =
    _hvcat(rows, A, B...)

Base.vcat(C::Union{Fun,Number,UniformScaling}, A::Operator, B::OperatorTypes...) = _vcat(C, A, B...)
Base.hcat(C::Union{Fun,Number,UniformScaling}, A::Operator, B::OperatorTypes...) = _hcat(C, A, B...)
Base.hvcat(rows::Tuple{Vararg{Int}}, C::Union{Fun,Number,UniformScaling}, A::Operator, B::OperatorTypes...) =
    _hvcat(rows, C, A, B...)

Base.vcat(D::Union{Fun,Number,UniformScaling}, C::Union{Fun,Number,UniformScaling}, A::Operator, B::OperatorTypes...) = _vcat(D, C, A, B...)
Base.hcat(D::Union{Fun,Number,UniformScaling}, C::Union{Fun,Number,UniformScaling}, A::Operator, B::OperatorTypes...) = _hcat(D, C, A, B...)
Base.hvcat(rows::Tuple{Vararg{Int}}, D::Union{Fun,Number,UniformScaling}, C::Union{Fun,Number,UniformScaling}, A::Operator, B::OperatorTypes...) =
    _hvcat(rows, D, C, A, B...)


## Convert Matrix operator to operators

Operator(M::AbstractArray{<:Operator}) = InterlaceOperator(M)




function interlace_choosedomainspace(ops,sp::UnsetSpace)
    # this ensures correct dispatch for unino
    sps = Vector{Space}(
        filter(x->!isambiguous(x),map(choosedomainspace,ops)))
    if isempty(sps)
        UnsetSpace()
    else
        union(sps...)
    end
end


function interlace_choosedomainspace(ops,rs::Space)
    # this ensures correct dispatch for unino
    sps = Vector{Space}(
        filter(x->!isambiguous(x),map((op)->choosedomainspace(op,rs),ops)))
    if isempty(sps)
        UnsetSpace()
    else
        union(sps...)
    end
end


choosedomainspace(A::InterlaceOperator{T,1},rs::Space) where {T} =
    interlace_choosedomainspace(A.ops,rs)


choosedomainspace(A::InterlaceOperator{T,2},rs::Space) where {T} =
    Space([interlace_choosedomainspace(A.ops[:,k],rs) for k=1:size(A.ops,2)])
