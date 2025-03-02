export Fun, evaluate, values, points, extrapolate, setdomain
export coefficients, ncoefficients, coefficient
export integrate, differentiate, domain, space, linesum, linenorm

include("Domain.jl")
include("Space.jl")

##  Constructors


struct Fun{S,T,VT} <: Function
    space::S
    coefficients::VT
    function Fun{S,T,VT}(sp::S,coeff::VT) where {S,T,VT}
        nc = length(coeff)
        dimsp = dimension(sp)
        nc ≤ dimsp ||
                throw(ArgumentError("length(coeff) = $(length(coeff)) exceeds dimension(space) = $(dimension(sp))"))
        new{S,T,VT}(sp,coeff)
    end
end

const VFun{S,T} = Fun{S,T,Vector{T}}

"""
    Fun(s::Space, coefficients::AbstractVector)

Return a `Fun` with the specified `coefficients` in the space `s`

# Examples
```jldoctest
julia> f = Fun(Fourier(), [1,1]);

julia> f(0.1) == 1 + sin(0.1)
true

julia> f = Fun(Chebyshev(), [1,1]);

julia> f(0.1) == 1 + 0.1
true
```
"""
Fun(sp::Space,coeff::AbstractVector) = Fun{typeof(sp),eltype(coeff),typeof(coeff)}(sp,coeff)

"""
    Fun()

Return `Fun(identity, Chebyshev())`, which represents the identity function in `-1..1`.

# Examples
```jldoctest
julia> f = Fun(Chebyshev())
Fun(Chebyshev(), [0.0, 1.0])

julia> f(0.1)
0.1
```
"""
Fun() = Fun(identity, ChebyshevInterval())
Fun(d::Domain) = Fun(identity,d)

"""
    Fun(s::Space)

Return `Fun(identity, s)`

# Examples
```jldoctest
julia> x = Fun(Chebyshev())
Fun(Chebyshev(), [0.0, 1.0])

julia> x(0.1)
0.1
```
"""
Fun(d::Space) = Fun(identity,d)


function Fun(sp::Space,v::AbstractVector{Any})
    if isempty(v)
        Fun(sp,Float64[])
    elseif all(x->isa(x,Number),v)
        Fun(sp,Vector{mapreduce(typeof,promote_type,v)}(v))
    else
        error("Cannot construct Fun with coefficients $v and space $sp")
    end
end

Fun(f::Fun) = f # Fun of Fun should be like a conversion

hasnumargs(f::Fun,k) = k == 1 || domaindimension(f) == k  # all funs take a single argument as a SVector

##Coefficient routines
#TODO: domainscompatible?

"""
    coefficients(f::Fun, s::Space) -> Vector

Return the coefficients of `f` in the space `s`, which
may not be the same as `space(f)`.

# Examples
```jldoctest
julia> f = Fun(x->(3x^2-1)/2);

julia> coefficients(f, Legendre()) ≈ [0, 0, 1]
true
```
"""
function coefficients(f::Fun,msp::Space)
    #zero can always be converted
    fc = f.coefficients
    if ncoefficients(f) == 0 || (ncoefficients(f) == 1 && fc[1] == 0)
        convert(Vector, fc)
    else
        coefficients(fc, space(f), msp)
    end
end
coefficients(f::Fun,::Type{T}) where {T<:Space} = coefficients(f,T(domain(f)))

"""
    coefficients(f::Fun) -> Vector

Return the coefficients of `f`, corresponding to the space `space(f)`.

# Examples
```jldoctest
julia> f = Fun(x->x^2)
Fun(Chebyshev(), [0.5, 0.0, 0.5])

julia> coefficients(f)
3-element Vector{Float64}:
 0.5
 0.0
 0.5
```
"""
coefficients(f::Fun) = f.coefficients
coefficients(c::Number,sp::Space) = Fun(c,sp).coefficients

function coefficient(f::Fun,k::Integer)
    if k > dimension(space(f)) || k < 1
        throw(BoundsError())
    elseif k > ncoefficients(f)
        zero(cfstype(f))
    else
        f.coefficients[k]
    end
end

function coefficient(f::Fun,kr::AbstractRange)
    b = maximum(kr)
    f.coefficients[first(kr):min(b, end)]
end

coefficient(f::Fun,K::Block) = coefficient(f,blockrange(space(f),K.n[1]))
coefficient(f::Fun,::Colon) = coefficient(f,1:dimension(space(f)))

# convert to vector while computing coefficients
_maybeconvert(inplace::Val{false}, f::Fun, v) = strictconvert(Vector{cfstype(f)}, v)

##Convert routines


convert(::Type{Fun{S,T,VT}},f::Fun{S}) where {T,S,VT} =
    Fun{S,T,VT}(f.space, strictconvert(VT,f.coefficients))
function convert(::Type{Fun{S,T,VT}},f::Fun) where {T,S,VT}
    g = Fun(Fun(f.space, strictconvert(VT,f.coefficients)), strictconvert(S,space(f)))
    Fun{S,T,VT}(g.space, g.coefficients)
end

function convert(::Type{Fun{S,T}},f::Fun{S}) where {T,S}
    coeff = strictconvert(AbstractVector{T},f.coefficients)
    Fun{S, T, typeof(coeff)}(f.space, coeff)
end


convert(::Type{VFun{S,T}},x::Number) where {T,S} =
    (x==0 ? zeros(T,S(AnyDomain())) : x*ones(T,S(AnyDomain())))::VFun{S,T}
convert(::Type{Fun{S}},x::Number) where {S} =
    (x==0 ? zeros(S(AnyDomain())) : x*ones(S(AnyDomain())))::Fun{S}
convert(::Type{IF},x::Number) where {IF<:Fun} = strictconvert(IF,Fun(x))

Fun{S,T,VT}(f::Fun) where {S,T,VT} = strictconvert(Fun{S,T,VT}, f)
Fun{S,T}(f::Fun) where {S,T} = strictconvert(Fun{S,T}, f)
Fun{S}(f::Fun) where {S} = strictconvert(Fun{S}, f)

# if we are promoting, we need to change to a VFun
Base.promote_rule(::Type{Fun{S,T,VT1}},::Type{Fun{S,V,VT2}}) where {T,V,S,VT1,VT2} =
    VFun{S,promote_type(T,V)}


# TODO: Never assume!
Base.promote_op(::typeof(*),::Type{F1},::Type{F2}) where {F1<:Fun,F2<:Fun} =
    promote_type(F1,F2) # assume multiplication is defined between same types

# we know multiplication by numbers preserves types
Base.promote_op(::typeof(*),::Type{N},::Type{Fun{S,T,VT}}) where {N<:Number,S,T,VT} =
    VFun{S,promote_type(T,N)}
Base.promote_op(::typeof(*),::Type{Fun{S,T,VT}},::Type{N}) where {N<:Number,S,T,VT} =
    VFun{S,promote_type(T,N)}

Base.promote_op(::typeof(LinearAlgebra.matprod),::Type{Fun{S1,T1,VT1}},::Type{Fun{S2,T2,VT2}}) where {S1,T1,VT1,S2,T2,VT2} =
            VFun{promote_type(S1,S2),promote_type(T1,T2)}
# Fun's are always vector spaces, so we know matprod will preserve the space
Base.promote_op(::typeof(LinearAlgebra.matprod),::Type{Fun{S,T,VT}},::Type{NN}) where {S,T,VT,NN<:Number} =
            VFun{S,promote_type(T,NN)}
Base.promote_op(::typeof(LinearAlgebra.matprod),::Type{NN},::Type{Fun{S,T,VT}}) where {S,T,VT,NN<:Number} =
            VFun{S,promote_type(T,NN)}



zero(::Type{Fun}) = Fun(0.)
zero(::Type{Fun{S,T,VT}}) where {T,S<:Space,VT} = zeros(T,S(AnyDomain()))
one(::Type{Fun{S,T,VT}}) where {T,S<:Space,VT} = ones(T,S(AnyDomain()))
zero(f::Fun) = zeros(cfstype(f), space(f))
one(f::Fun) = ones(cfstype(f), space(f))

cfstype(f::Fun) = cfstype(typeof(f))
cfstype(::Type{<:Fun{<:Any,T}}) where {T} = T

# Number and Array conform to the Fun interface
cfstype(::Type{T}) where T<: Number = T
cfstype(::T) where T<: Number = T
cfstype(::Type{<:AbstractArray{T}}) where T = T
cfstype(::AbstractArray{T}) where T = T

coefficients(f::Number) = [f]
coefficients(f::AbstractArray) = f


#supports broadcasting and scalar iterator
const ScalarFun = Fun{S} where S<:Space{D,R} where {D,R<:Number}
const ArrayFun = Fun{S} where {S<:Space{D,R}} where {D,R<:AbstractArray}
const MatrixFun = Fun{S} where {S<:Space{D,R}} where {D,R<:AbstractMatrix}
const VectorFun = Fun{S} where {S<:Space{D,R}} where {D,R<:AbstractVector}

size(f::Fun,k...) = size(space(f),k...)
length(f::Fun) = length(space(f))


getindex(f::ScalarFun, ::CartesianIndex{0}) = f
getindex(f::ScalarFun, k::Integer) = k == 1 ? f : throw(BoundsError())

iterate(x::ScalarFun) = (x, nothing)
iterate(x::ScalarFun, ::Any) = nothing
isempty(x::ScalarFun) = false

@inline function iterate(A::ArrayFun, i=1)
    (i % UInt) - 1 < length(A) ? (@inbounds A[i], i + 1) : nothing
end

in(x::ScalarFun, y::ScalarFun) = x == y

setspace(v::AbstractVector,s::Space) = Fun(s,v)
setspace(f::Fun,s::Space) = Fun(s,f.coefficients)


## domain


## General routines

"""
    domain(f::Fun)

Return the domain that `f` is defined on.

# Examples
```jldoctest
julia> f = Fun(x->x^2);

julia> domain(f) == ChebyshevInterval()
true

julia> f = Fun(x->x^2, 0..1);

julia> domain(f) == 0..1
true
```
"""
domain(f::Fun) = domain(f.space)
domain(v::AbstractMatrix{T}) where {T<:Fun} = map(domain,v)
domaindimension(f::Fun) = domaindimension(f.space)

"""
    setdomain(f::Fun, d::Domain)

Return `f` projected onto `domain`.

!!! note
    The new function may differ from the original one, as the coefficients are left unchanged.

# Examples
```jldoctest
julia> f = Fun(x->x^2);

julia> domain(f) == ChebyshevInterval()
true

julia> g = setdomain(f, 0..1);

julia> domain(g) == 0..1
true

julia> coefficients(f) == coefficients(g)
true
```
"""
setdomain(f::Fun, d::Domain) = Fun(setdomain(space(f), d), f.coefficients)

for op in (:tocanonical,:tocanonicalD,:fromcanonical,:fromcanonicalD,:invfromcanonicalD)
    @eval $op(f::Fun,x...) = $op(space(f),x...)
end

for op in (:tocanonical,:tocanonicalD)
    @eval $op(d::Domain) = $op(d,Fun(identity,d))
end
for op in (:fromcanonical,:fromcanonicalD,:invfromcanonicalD)
    @eval $op(d::Domain) = $op(d,Fun(identity,canonicaldomain(d)))
end


"""
    space(f::Fun)

Return the space of `f`.

# Examples
```jldoctest
julia> f = Fun(x->x^2)
Fun(Chebyshev(), [0.5, 0.0, 0.5])

julia> space(f)
Chebyshev()
```
"""
space(f::Fun) = f.space
spacescompatible(f::Fun,g::Fun) = spacescompatible(space(f),space(g))
pointscompatible(f::Fun,g::Fun) = pointscompatible(space(f),space(g))
canonicalspace(f::Fun) = canonicalspace(space(f))
canonicaldomain(f::Fun) = canonicaldomain(space(f))


##Evaluation

"""
    evaluate(coefficients::AbstractVector, sp::Space, x)

Evaluate the expansion at a point `x` that lies in `domain(sp)`.
If `x` is not in the domain, the returned value will depend on the space,
and should not be relied upon. See [`extrapolate`](@ref) to evaluate a function
at a value outside the domain.
"""
function evaluate(f::AbstractVector,S::Space,x...)
    csp=canonicalspace(S)
    if spacescompatible(csp,S)
        error("Override evaluate for " * string(typeof(csp)))
    else
        evaluate(coefficients(f,S,csp),csp,x...)
    end
end

evaluate(f::Fun,x) = evaluate(f.coefficients,f.space,x)
evaluate(f::Fun,x,y,z...) = evaluate(f.coefficients,f.space,SVector(x,y,z...))


(f::Fun)(x...) = evaluate(f,x...)

dynamic(f::Fun) = f # Fun's are already dynamic in that they compile by type

for (op,dop) in ((:first,:leftendpoint),(:last,:rightendpoint))
    @eval $op(f::Fun) = f($dop(domain(f)))
end



## Extrapolation


# Default extrapolation is evaluation. Override this function for extrapolation enabled spaces.
extrapolate(f::AbstractVector,S::Space,x...) = evaluate(f,S,x...)

# Do not override these
"""
    extrapolate(f::Fun,x)

Return an extrapolation of `f` from its domain to `x`.

# Examples
```jldoctest
julia> f = Fun(x->x^2)
Fun(Chebyshev(), [0.5, 0.0, 0.5])

julia> extrapolate(f, 2) # 2 lies outside the domain -1..1
4.0
```
"""
extrapolate(f::Fun,x) = extrapolate(f.coefficients,f.space,x)
extrapolate(f::Fun,x,y,z...) = extrapolate(f.coefficients,f.space,SVector(x,y,z...))


##Data routines

"""
    values(f::Fun)

Return `f` evaluated at `points(f)`.

# Examples
```jldoctest
julia> f = Fun(x->x^2)
Fun(Chebyshev(), [0.5, 0.0, 0.5])

julia> values(f)
3-element Vector{Float64}:
 0.75
 0.0
 0.75

julia> map(x->x^2, points(f)) ≈ values(f)
true
```
"""
values(f::Fun,dat...) = _values(f.space, f.coefficients, dat...)
_values(sp, v, dat...) = itransform(sp, v, dat...)
_values(sp::UnivariateSpace, v::Vector{T}, dat...) where {T<:Number} =
    itransform(sp, v, dat...)::Vector{float(T)}

"""
    points(f::Fun)

Return a grid of points that `f` can be transformed into values
and back.

# Examples
```jldoctest
julia> f = Fun(x->x^2);

julia> chebypts(n) = [cos((2i+1)pi/2n) for i in 0:n-1];

julia> points(f) ≈ chebypts(ncoefficients(f))
true
```
"""
points(f::Fun) = points(f.space,ncoefficients(f))

"""
    ncoefficients(f::Fun) -> Integer

Return the number of coefficients of a fun

# Examples
```jldoctest
julia> f = Fun(x->x^2)
Fun(Chebyshev(), [0.5, 0.0, 0.5])

julia> ncoefficients(f)
3
```
"""
ncoefficients(f::Fun)::Int = length(f.coefficients)

blocksize(f::Fun) = (block(space(f),ncoefficients(f)).n[1],)

"""
    stride(f::Fun)

Return the stride of the coefficients, checked numerically
"""
function stride(f::Fun)
    # Check only for stride 2 at the moment
    # as higher stride is very rare anyways
    M=maximum(abs,f.coefficients)
    for k=2:2:ncoefficients(f)
        if abs(f.coefficients[k])>40*M*eps()
            return 1
        end
    end

    2
end



## Manipulate length

pad!(f::Fun,n::Integer) = (pad!(f.coefficients,n);f)
pad(f::Fun,n::Integer) = Fun(f.space,pad(f.coefficients,n))


function chop!(sp::UnivariateSpace,cfs,tol::Real)
    n=standardchoplength(cfs,tol)
    resize!(cfs,n)
    cfs
end

chop!(sp::Space,cfs,tol::Real) = chop!(cfs,maximum(abs,cfs)*tol)
chop!(sp::Space,cfs) = chop!(sp,cfs,10eps())

function chop!(f::Fun,tol...)
    chop!(space(f),f.coefficients,tol...)
    f
end

"""
    chop(f::Fun[, tol = 10eps()]) -> Fun

Reduce the number of coefficients by dropping the tail that is below the specified tolerance.

# Examples
```jldoctest
julia> f = Fun(Chebyshev(), [1,2,3,0,0,0])
Fun(Chebyshev(), [1, 2, 3, 0, 0, 0])

julia> chop(f)
Fun(Chebyshev(), [1, 2, 3])
```
"""
chop(f::Fun,tol...) = chop!(Fun(f.space,Vector(f.coefficients)),tol...)

copy(f::Fun) = Fun(space(f),copy(f.coefficients))

## Addition and multiplication

for op in (:+,:-)
    @eval begin
        function $op(f::Fun,g::Fun)
            if spacescompatible(f,g)
                n = max(ncoefficients(f),ncoefficients(g))
                f2 = pad(f,n);
                g2 = pad(g,n);

                Fun(isambiguous(domain(f)) ? g.space : f.space, ($op)(f2.coefficients,g2.coefficients))
            else
                m=union(f.space,g.space)
                if isa(m,NoSpace)
                    error("Cannot "*string($op)*" because no space is the union of "*string(typeof(f.space))*" and "*string(typeof(g.space)))
                end
                $op(Fun(f,m),Fun(g,m)) # convert to same space
            end
        end
        $op(f::Fun{S,T},c::T) where {S,T<:Number} = c==0 ? f : $op(f,Fun(c))
        function $op(f::Fun, c::Number)
            T = promote_type(typeof(c), cfstype(f))
            g = cfstype(f) == T ? f : Fun(space(f), T.(coefficients(f)))
            d = convert(T, c)
            $op(g,Fun(d))
        end
        $op(f::Fun,c::UniformScaling) = $op(f,c.λ)
        $op(c::UniformScaling,f::Fun) = $op(c.λ,f)
    end
end


# equivalent to Y+=a*X
axpy!(a,X::Fun,Y::Fun)=axpy!(a,coefficients(X,space(Y)),Y)
function axpy!(a,xcfs::AbstractVector,Y::Fun)
    if a!=0
        n=ncoefficients(Y); m=length(xcfs)

        if n≤m
            resize!(Y.coefficients,m)
            for k=1:n
                @inbounds Y.coefficients[k]+=a*xcfs[k]
            end
            for k=n+1:m
                @inbounds Y.coefficients[k]=a*xcfs[k]
            end
        else #X is smaller
            for k=1:m
                @inbounds Y.coefficients[k]+=a*xcfs[k]
            end
        end
    end

    Y
end


+(a::Fun) = copy(a)
-(f::Fun) = Fun(f.space,-f.coefficients)
-(c::Number,f::Fun) = -(f-c)


for op = (:*,:/)
    @eval $op(f::Fun, c::Number) = Fun(f.space,$op(f.coefficients,c))
end


for op = (:*,:+)
    @eval $op(c::Number, f::Fun) = $op(f,c)
end

\(c::Number, f::Fun) = Fun(f.space, c \ f.coefficients)

# eliminate the type-unstable 1/t branch by using an unsigned integer exponent
isnegative(x) = x < zero(x)
isnegative(::Unsigned) = false

Base.@constprop :aggressive function intpow(f, k)
    if k == 0
        ones(cfstype(f), space(f))
    elseif k==1
        f
    elseif k==2
        f * f
    elseif k==3
        f * f * f
    elseif k==4
        f * f * f * f
    else
        t = foldl(*, fill(f, abs(k)-1), init=f)
        if isnegative(k)
            return 1/t
        else
            return t
        end
    end
end

^(f::Fun, k::Integer) = intpow(f,k)
# Ideally, constant propagation in intpow would handle literal exponentiation,
# but currently inference doesn't succeed for f * f for arbitrary domains.
# We specialize literal exponentiation here,
# letting downstream users specialize f * f for custom domains
# With f * f type-inferred, the type of f^2 would also be inferred.
# This is a stopgap measure that might not be necessary in the future.
Base.literal_pow(::typeof(^), f::Fun, ::Val{0}) = ones(cfstype(f), space(f))
Base.literal_pow(::typeof(^), f::Fun, ::Val{1}) = f
Base.literal_pow(::typeof(^), f::Fun, ::Val{2}) = f * f
Base.literal_pow(::typeof(^), f::Fun, ::Val{3}) = f * f * f
Base.literal_pow(::typeof(^), f::Fun, ::Val{4}) = f * f * f * f

inv(f::Fun) = 1/f

# Integrals over two Funs, which are fast with the orthogonal weight.

export bilinearform, linebilinearform, innerproduct, lineinnerproduct

# Having fallbacks allow for the fast implementations.

defaultbilinearform(f::Fun,g::Fun)=sum(f*g)
defaultlinebilinearform(f::Fun,g::Fun)=linesum(f*g)

bilinearform(f::Fun,g::Fun)=defaultbilinearform(f,g)
bilinearform(c::Number,g::Fun)=sum(c*g)
bilinearform(g::Fun,c::Number)=sum(g*c)

linebilinearform(f::Fun,g::Fun)=defaultbilinearform(f,g)
linebilinearform(c::Number,g::Fun)=linesum(c*g)
linebilinearform(g::Fun,c::Number)=linesum(g*c)



# Conjugations

innerproduct(f::Fun,g::Fun)=bilinearform(conj(f),g)
innerproduct(c::Number,g::Fun)=bilinearform(conj(c),g)
innerproduct(g::Fun,c::Number)=bilinearform(conj(g),c)

lineinnerproduct(f::Fun,g::Fun)=linebilinearform(conj(f),g)
lineinnerproduct(c::Number,g::Fun)=linebilinearform(conj(c),g)
lineinnerproduct(g::Fun,c::Number)=linebilinearform(conj(g),c)

## Norm

for (OP,SUM) in ((:(norm),:(sum)),(:linenorm,:linesum))
    @eval begin
        $OP(f::Fun) = $OP(f,2)

        # Specializing norm(::ScalarFun) helps with inference
        $OP(f::ScalarFun) = sqrt(abs($SUM(abs2(f))))

        function $OP(f::ScalarFun, p::Real)
            if p < 1
                return error("p should be 1 ≤ p ≤ ∞")
            elseif 1 ≤ p < Inf
                return abs($SUM(abs2(f)^(p/2)))^(1/p)
            else
                return maximum(abs,f)
            end
        end

        function $OP(f::ScalarFun, p::Int)
            if 1 ≤ p < Inf
                p == 2 && return $OP(f)
                return iseven(p) ? abs($SUM(abs2(f)^(p÷2)))^(1/p) : abs($SUM(abs2(f)^(p/2)))^(1/p)
            else
                error("p should be 1 ≤ p ≤ ∞")
            end
        end
    end
end


## Mapped functions

transpose(f::Fun) = f  # default no-op

for op = (:real, :imag, :conj)
    @eval Base.$op(f::Fun{<:RealSpace}) = Fun(f.space, ($op)(f.coefficients))
end

conj(f::Fun) = error("Override conj for $(typeof(f))")

abs2(f::Fun{<:RealSpace,<:Real}) = f^2
abs2(f::Fun{<:RealSpace,<:Complex}) = real(f)^2+imag(f)^2
abs2(f::Fun)=f*conj(f)

##  integration

function cumsum(f::Fun)
    cf = integrate(f)
    cf - first(cf)
end

cumsum(f::Fun,d::Domain)=cumsum(Fun(f,d))
cumsum(f::Fun,d)=cumsum(f,Domain(d))



function differentiate(f::Fun,k::Integer)
    @assert k >= 0
    (k==0) ? f : differentiate(differentiate(f),k-1)
end

# use conj(transpose(f)) for ArraySpace
adjoint(f::Fun) = differentiate(f)



==(f::Fun,g::Fun) =  (f.coefficients == g.coefficients && f.space == g.space)

coefficientnorm(f::Fun,p::Real=2) = norm(f.coefficients,p)


Base.rtoldefault(::Type{F}) where {F<:Fun} = Base.rtoldefault(cfstype(F))
Base.rtoldefault(x::Union{T,Type{T}}, y::Union{S,Type{S}}, atol) where {T<:Fun,S<:Fun} =
    Base.rtoldefault(cfstype(x),cfstype(y), atol)

Base.rtoldefault(x::Union{T,Type{T}}, y::Union{S,Type{S}}, atol) where {T<:Number,S<:Fun} =
    Base.rtoldefault(cfstype(x),cfstype(y), atol)
Base.rtoldefault(x::Union{T,Type{T}}, y::Union{S,Type{S}}, atol) where {T<:Fun,S<:Number} =
    Base.rtoldefault(cfstype(x),cfstype(y), atol)


function isapprox(f::Fun,g::Fun;
        rtol::Real=Base.rtoldefault(cfstype(f),cfstype(g),0), atol::Real=0, norm::Function=coefficientnorm)
    if spacescompatible(f,g)
        d = norm(f - g)
        if isfinite(d)
            return d <= atol + rtol*max(norm(f), norm(g))
        else
            # Fall back to a component-wise approximate comparison
            return false
        end
    else
        sp=union(f.space,g.space)
        if isa(sp,NoSpace)
            false
        else
            isapprox(Fun(f,sp),Fun(g,sp);rtol=rtol,atol=atol,norm=norm)
        end
    end
end

isapprox(f::Fun, g::Number; kw...) = isapprox(f, g*ones(space(f)); kw...)
isapprox(g::Number, f::Fun; kw...) = isapprox(g*ones(space(f)), f; kw...)


isreal(f::Fun{<:RealSpace,<:Real}) = true
isreal(f::Fun) = false

iszero(f::Fun)    = all(iszero,f.coefficients)



# sum, integrate, and idfferentiate are in CalculusOperator

"""
    reverseorientation(f::Fun)

Return `f` on a reversed orientated contour.
"""
function reverseorientation(f::Fun)
    csp=canonicalspace(f)
    if spacescompatible(csp,space(f))
        error("Implement reverseorientation for $(typeof(f))")
    else
        reverseorientation(Fun(f,csp))
    end
end


## non-vector notation

for op in (:+,:-,:*,:/,:^)
    @eval begin
        broadcast(::typeof($op), a::Fun, b::Fun) = $op(a,b)
        broadcast(::typeof($op), a::Fun, b::Number) = $op(a,b)
        broadcast(::typeof($op), a::Number, b::Fun) = $op(a,b)
    end
end

## broadcasting
# for broadcasting, we support broadcasting over `Fun`s, e.g.
#
#       exp.(f) is equivalent to Fun(x->exp(f(x)),domain(f)),
#       exp.(f .+ g) is equivalent to Fun(x->exp(f(x)+g(x)),domain(f) ∪ domain(g)),
#       exp.(f .+ 2) is equivalent to Fun(x->exp(f(x)+2),domain(f)),
#
# When we are broadcasting over arrays and scalar Fun's together,
# it broadcasts over the Array and treats the scalar Fun's as constants, so will not
# necessarily call the constructor:
#
#       exp.( x .+ [1,2,3]) is equivalent to [exp(x + 1),exp(x+2),exp(x+3)]
#
# When broadcasting over Fun's with array values, it treats them like Fun's:
#
#   exp.( [x;x]) throws an error as it is equivalent to Fun(x->exp([x;x](x)),domain(f))
#
# This is consistent with the deprecation thrown by exp.([[1,2],[3,4]). Note that
#
#   exp.( [x,x]) is equivalent to [exp(x),exp(x)]
#
# does not throw the same error. When array values are mixed with arrays, the Array
# takes presidence:
#
#   exp.([x;x] .+ [x,x]) is equivalent to exp.(Array([x;x]) .+ [x,x])
#
# This presidence is picked by the `promote_containertype` overrides.

struct FunStyle <: BroadcastStyle end

BroadcastStyle(::Type{<:Fun}) = FunStyle()

BroadcastStyle(::FunStyle, ::FunStyle) = FunStyle()
BroadcastStyle(::AbstractArrayStyle{0}, ::FunStyle) = FunStyle()
BroadcastStyle(::FunStyle, ::AbstractArrayStyle{0}) = FunStyle()
BroadcastStyle(A::AbstractArrayStyle, ::FunStyle) = A
BroadcastStyle(::FunStyle, A::AbstractArrayStyle) = A


# Treat Array Fun's like Arrays when broadcasting with an Array
# note this only gets called when containertype returns Array,
# so will not be used when no argument is an Array
Base.broadcast_axes(::Type{Fun}, A) = axes(A)
Base.broadcastable(x::Fun) = x

broadcastdomain(b) = AnyDomain()
broadcastdomain(b::Fun) = domain(b)
broadcastdomain(b::Broadcasted) = mapreduce(broadcastdomain, ∪, b.args)

broadcasteval(f::Function, x) = f(x)
broadcasteval(c, x) = c
broadcasteval(c::Ref, x) = c.x
broadcasteval(b::Broadcasted, x) = b.f(broadcasteval.(b.args, Ref(x))...)

# TODO: use generated function to improve the following
function copy(bc::Broadcasted{FunStyle})
    d = broadcastdomain(bc)
    Fun(x -> broadcasteval(bc, x), d)
end

function copyto!(dest::Fun, bc::Broadcasted{FunStyle})
    if broadcastdomain(bc) ≠ domain(dest)
        throw(ArgumentError("Domain of right-hand side incompatible with destination"))
    end
    ret = copy(bc)
    cfs = coefficients(ret,space(dest))
    resize!(dest.coefficients, length(cfs))
    dest.coefficients[:] = cfs
    dest
end

include("constructors.jl")
