module ApproxFunBaseTest

Base.Experimental.@optlevel 1

using ApproxFunBase
using ApproxFunBase: plan_transform, plan_itransform, israggedbelow, RaggedMatrix, isbandedbelow, isbanded,
    blockstart, blockstop, resizedata!
using BandedMatrices: BandedMatrices, rowstart, rowstop, colstart, colstop, BandedMatrix, bandwidth
using BlockArrays
using BlockArrays: blockrowstop, blockcolstop
using BlockBandedMatrices
using BlockBandedMatrices: isbandedblockbanded
using DomainSets: dimension
using InfiniteArrays
using LinearAlgebra
using Test

# These routines are for the unit tests

export testspace, testfunctional, testraggedbelowoperator, testbandedblockbandedoperator,
    testbandedoperator, testtransforms, testcalculus, testmultiplication, testinfoperator,
    testblockbandedoperator, testbandedbelowoperator

# assert type in convert
strictconvert(::Type{T}, x) where {T} = convert(T, x)::T

## Spaces Tests


function testtransforms(S::Space;minpoints=1,invertibletransform=true)
    # transform tests
    v = rand(max(minpoints,min(100,dimension(S))))
    plan = plan_transform(S,v)
    @test transform(S,v)  == plan*v

    iplan = plan_itransform(S,v)
    @test itransform(S,v)  == iplan*v

    if invertibletransform
        for k=max(1,minpoints):min(5,dimension(S))
            v = [zeros(k-1);1.0]
            @test transform(S,itransform(S,v)) ≈ v
        end

        @test transform(S,itransform(S,v)) ≈ v
        @test itransform(S,transform(S,v)) ≈ v
    end
end

function testcalculus(S::Space;haslineintegral=true,hasintegral=true)
    @testset for k=1:min(5,dimension(S))
        v = [zeros(k-1);1.0]
        f = Fun(S,v)
        @test abs(DefiniteIntegral()*f-sum(f)) < 100eps()
        if haslineintegral
            @test DefiniteLineIntegral()*f ≈ linesum(f)
        end
        @test norm(Derivative()*f-f') < 100eps()
        if hasintegral
            @test norm(differentiate(integrate(f))-f) < 100eps()
            @test norm(differentiate(cumsum(f))-f) < 200eps()
            @test norm(first(cumsum(f))) < 100eps()
        end
    end
end

function testmultiplication(spa,spb)
    @testset for k=1:10
        a = Fun(spa,[zeros(k-1);1.])
        M = Multiplication(a,spb)
        pts = ApproxFunBase.checkpoints(rangespace(M))
        for j=1:10
            b = Fun(spb,[zeros(j-1);1.])
            @test (M*b).(pts) ≈ a.(pts).*b.(pts)
        end
    end
end

function testspace(S::Space;
                    minpoints=1,invertibletransform=true,haslineintegral=true,hasintegral=true,
                    dualspace=S)
    testtransforms(S;minpoints=minpoints,invertibletransform=invertibletransform)
    testcalculus(S;haslineintegral=haslineintegral,hasintegral=hasintegral)
    if dualspace ≠ nothing
        testmultiplication(dualspace,S)
    end
end





## Operator Tests

function backend_testfunctional(A)
    @test rowstart(A,1) ≥ 1
    @test colstop(A,1) ≤ 1
    @test bandwidth(A,1) ≤ 0
    @test blockbandwidth(A,1) ≤ 0

    B=A[1:10]
    @test eltype(B) == eltype(A)
    for k=1:5
        @test B[k] ≈ A[k]
        @test isa(A[k],eltype(A))
    end
    @test isa(A[1,1:10],Vector)
    @test isa(A[1:1,1:10],AbstractMatrix)
    @test B ≈ A[1,1:10]
    @test transpose(B) ≈ A[1:1,1:10]
    @test B[3:10] ≈ A[3:10]
    @test B ≈ [A[k] for k=1:10]



    co=cache(A)
    @test co[1:10] ≈ A[1:10]
    @test co[1:10] ≈ A[1:10]
    @test co[20:30] ≈ A[1:30][20:30] ≈ A[20:30]
end

# Check that the tests pass after conversion as well
function testfunctional(A::Operator{T}) where T<:Real
    backend_testfunctional(A)
    backend_testfunctional(Operator{Float64}(A))
    backend_testfunctional(Operator{Float32}(A))
    backend_testfunctional(Operator{ComplexF64}(A))
end

function testfunctional(A::Operator{T}) where T<:Complex
    backend_testfunctional(A)
    backend_testfunctional(Operator{ComplexF32}(A))
    backend_testfunctional(Operator{ComplexF64}(A))
end

function backend_testinfoperator(A)
    @test isinf(size(A,1))
    @test isinf(size(A,2))
    B=A[1:5,1:5]
    @test eltype(B) == eltype(A)

    for k=1:5,j=1:5
        @test B[k,j] ≈ A[k,j]
        @test isa(A[k,j],eltype(A))
    end

    A10 = A[1:10,1:10]
    A10m = Matrix(A10)
    A10_510 = A10m[5:10,5:10]
    A30 = A[1:30,1:30]
    A30_2030 = A30[20:30,20:30]
    A30_2030m = Matrix(A30_2030)

    @test Matrix(B[2:5,1:5]) ≈ Matrix(A[2:5,1:5])
    @test Matrix(A[1:5,2:5]) ≈ Matrix(B[:,2:end])
    @test A10_510 ≈ [A[k,j] for k=5:10,j=5:10]
    @test A10_510 ≈ Matrix(A[5:10,5:10])
    @test A30_2030m ≈ Matrix(A[20:30,20:30])

    @test Matrix(A[Block(1):Block(3),Block(1):Block(3)]) ≈ Matrix(A[blockstart(rangespace(A),1):blockstop(rangespace(A),3),blockstart(domainspace(A),1):blockstop(domainspace(A),3)])
    @test Matrix(A[Block(3):Block(4),Block(2):Block(4)]) ≈ Matrix(A[blockstart(rangespace(A),3):blockstop(rangespace(A),4),blockstart(domainspace(A),2):blockstop(domainspace(A),4)])

    for k=1:10
        @test isfinite(colstart(A,k)) && colstart(A,k) > 0
        @test isfinite(rowstart(A,k)) && colstart(A,k) > 0
    end

    co=cache(A)
    @test Matrix(co[1:10,1:10]) ≈ A10m
    @test Matrix(co[20:30,20:30]) ≈ A30_2030m

    let C=cache(A)
        resizedata!(C,5,35)
        resizedata!(C,10,35)
        @test Matrix(C.data[1:10,1:C.datasize[2]]) ≈ Matrix(A[1:10,1:C.datasize[2]])
    end
end

# Check that the tests pass after conversion as well
function testinfoperator(A::Operator{T}) where T<:Real
    backend_testinfoperator(A)
    if T != Float64
        B = strictconvert(Operator{Float64}, A)
        backend_testinfoperator(B)
    end
    if T != Float32
        B = strictconvert(Operator{Float32}, A)
        backend_testinfoperator(B)
    end
    B = strictconvert(Operator{ComplexF64}, A)
    backend_testinfoperator(B)
end

function testinfoperator(A::Operator{T}) where T<:Complex
    backend_testinfoperator(A)
    if T != ComplexF32
        backend_testinfoperator(strictconvert(Operator{ComplexF32}, A))
    end
    if T != ComplexF64
        backend_testinfoperator(strictconvert(Operator{ComplexF64}, A))
    end
end

function testraggedbelowoperator(A)
    @test israggedbelow(A)
    for k=1:20
        @test isfinite(colstop(A,k))
    end

    R = RaggedMatrix(view(A, 1:10, 1:min(10,size(A,2))))
    for j=1:size(R,2)
        @test colstop(R,j) == min(colstop(A,j),10)
    end

    testinfoperator(A)
end

function testbandedbelowoperator(A)
    @test isbandedbelow(A)
    @test isfinite(bandwidth(A,1))
    testraggedbelowoperator(A)

    for k=1:10
        @test colstop(A,k) ≤ max(0,k + bandwidth(A,1))
    end
end


function testalmostbandedoperator(A)
    testbandedbelowoperator(A)
end

function testbandedoperator(A)
    @test isbanded(A)
    @test isfinite(bandwidth(A,2))
    testalmostbandedoperator(A)
    for k=1:10
        @test rowstop(A,k) ≤ k + bandwidth(A,2)
    end

    Am = A[1:10,1:10]
    @test Am isa AbstractMatrix && BandedMatrices.isbanded(Am)
end


function testblockbandedoperator(A)
    @test isblockbanded(A)
    testraggedbelowoperator(A)
    @test isfinite(blockbandwidth(A,2))
    @test isfinite(blockbandwidth(A,1))


    if -blockbandwidth(A,1) ≤ blockbandwidth(A,2)
        for K=1:10
            @test K - blockbandwidth(A,2) ≤ blockcolstop(A,Block(K)).n[1] ≤ K + blockbandwidth(A,1) < ∞
            @test K - blockbandwidth(A,1) ≤ blockrowstop(A,Block(K)).n[1] ≤ K + blockbandwidth(A,2) < ∞
        end
    end
end

function testbandedblockbandedoperator(A)
    @test isbandedblockbanded(A)
    testblockbandedoperator(A)
    @test isfinite(subblockbandwidth(A,1))
    @test isfinite(subblockbandwidth(A,2))

    Am = A[Block.(1:4),Block.(1:4)]
    @test Am isa AbstractMatrix && isbandedblockbanded(Am)
end

end # module
