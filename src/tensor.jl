#
"""
    Lazy Tensor Product Operator

    TensorProductOperator(A, B) = A ⊗ B

    (A ⊗ B)(u) = vec(B * U * transpose(A))

    where U is a lazy representation of the vector u as
    a matrix with the appropriate size.
"""
struct TensorProductOperator{T,O,C} <: AbstractSciMLOperator{T}
    ops::O
    cache::C

    function TensorProductOperator(
            ops::NTuple{2,Union{AbstractMatrix,AbstractSciMLOperator}},
            cache::Union{Tuple,Nothing}
        )

        T = promote_type(eltype.(ops)...)

        new{T,
            typeof(ops),
            typeof(cache)
           }(
             ops, cache,
            )
    end
end

function TensorProductOperator(outer::Union{AbstractMatrix,AbstractSciMLOperator},
                               inner::Union{AbstractMatrix,AbstractSciMLOperator};
                               cache = nothing
                              )
    outer = outer isa AbstractMatrix ? MatrixOperator(outer) : outer
    inner = inner isa AbstractMatrix ? MatrixOperator(inner) : inner

    TensorProductOperator((outer, inner), cache)
end

# constructors
TensorProductOperator(ops...) = reduce(TensorProductOperator, ops)
TensorProductOperator(op::AbstractSciMLOperator) = op
TensorProductOperator(op::AbstractMatrix) = MatrixOperator(op)
TensorProductOperator(ii1::IdentityOperator, ii2::IdentityOperator) = IdentityOperator(ii1.len * ii2.len)

# overload ⊗ (\otimes)
⊗(ops::Union{AbstractMatrix,AbstractSciMLOperator}...) = TensorProductOperator(ops...)

# TODO - overload Base.kron for tensor product operators
#Base.kron(ops::Union{AbstractMatrix,AbstractSciMLOperator}...) = TensorProductOperator(ops...)

# convert to matrix
Base.kron(ops::AbstractSciMLOperator...) = kron(convert.(AbstractMatrix, ops)...)

function Base.convert(::Type{AbstractMatrix}, L::TensorProductOperator)
    kron(convert.(AbstractMatrix, L.ops)...)
end

function SparseArrays.sparse(L::TensorProductOperator)
    kron(sparse.(AbstractMatrix, L.ops)...)
end

#LinearAlgebra.opnorm(L::TensorProductOperator) = prod(opnorm, L.ops)

Base.size(L::TensorProductOperator) = reduce(.*, size.(L.ops))

for op in (
           :adjoint,
           :transpose,
          )
    @eval function Base.$op(L::TensorProductOperator)
        TensorProductOperator(
                              $op.(L.ops)...;
                              cache = issquare(L.ops[2]) ? L.cache : nothing
                             )
    end
end
Base.conj(L::TensorProductOperator) = TensorProductOperator(conj.(L.ops)...; cache=L.cache)

function update_coefficients(L::TensorProductOperator, u, p, t)
    ops = ()
    for op in L.ops
        ops = (ops...,  update_coefficients(op, u, p, t))
    end

    @set! L.ops = ops
end

getops(L::TensorProductOperator) = L.ops
islinear(L::TensorProductOperator) = reduce(&, islinear.(L.ops))
Base.iszero(L::TensorProductOperator) = reduce(|, iszero.(L.ops))
has_adjoint(L::TensorProductOperator) = reduce(&, has_adjoint.(L.ops))
has_mul(L::TensorProductOperator) = reduce(&, has_mul.(L.ops))
has_mul!(L::TensorProductOperator) = reduce(&, has_mul!.(L.ops))
has_ldiv(L::TensorProductOperator) = reduce(&, has_ldiv.(L.ops))
has_ldiv!(L::TensorProductOperator) = reduce(&, has_ldiv!.(L.ops))

factorize(L::TensorProductOperator) = TensorProductOperator(factorize.(L.ops)...)

# operator application
function Base.:*(L::TensorProductOperator, u::AbstractVecOrMat)
    outer, inner = L.ops

    _ , ni = size(inner)
    _ , no = size(outer)
    m , n  = size(L)
    k = size(u, 2)

    U = reshape(u, (ni, no*k))
    C = inner * U

    V = outer_mul(L, u, C)

    u isa AbstractMatrix ? reshape(V, (m, k)) : reshape(V, (m,))
end

function Base.:\(L::TensorProductOperator, u::AbstractVecOrMat)
    outer, inner = L.ops

    mi , _ = size(inner)
    mo , _ = size(outer)
    m , n  = size(L)
    k = size(u, 2)

    U = reshape(u, (mi, mo * k))
    C = inner \ U

    V = outer_div(L, u, C)

    u isa AbstractMatrix ? reshape(V, (n, k)) : reshape(V, (n,))
end

function cache_self(L::TensorProductOperator, u::AbstractVecOrMat)
    outer, inner = L.ops

    mi, ni = size(inner)
    mo, no = size(outer)
    k = size(u, 2)

    # 3 arg mul!
    c1 = lmul!(false, similar(u, (mi, no*k)) ) # c1 = inner * u
    c2 = lmul!(false, similar(u, (no, mi, k))) # permut (2, 1, 3)
    c3 = lmul!(false, similar(u, (mo, mi*k)) ) # c3 = outer * c2

    # 5 arg mul!
    c4 = lmul!(false, similar(u, (mo*mi, k)) ) # cache v in 5 arg mul!

    # 3 arg ldiv!
    if reduce(&, issquare.(L.ops))
        c5, c6, c7 = c1, c2, c3
    else
        c5 = lmul!(false, similar(u, (ni, mo*k)) ) # c5 = inner \ u
        c6 = lmul!(false, similar(u, (mo, ni, k))) # permut (2, 1, 3)
        c7 = lmul!(false, similar(u, (no, ni*k)) ) # c7 = outer \ c6
    end

    @set! L.cache = (c1, c2, c3, c4, c5, c6, c7)
    L
end

function cache_internals(L::TensorProductOperator, u::AbstractVecOrMat)
    if !iscached(L)
        L = cache_self(L, u)
    end

    outer, inner = L.ops

    _ , ni = size(inner)
    _ , no = size(outer)
    k = size(u, 2)

    uinner = reshape(u, (ni, no*k))
    uouter = L.cache[2]

    @set! L.ops[2] = cache_operator(inner, uinner)
    @set! L.ops[1] = cache_operator(outer, uouter)
    L
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat)
    @assert iscached(L) "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    outer, inner = L.ops

    _ , ni = size(inner)
    _ , no = size(outer)
    k = size(u, 2)

    C1, C2, C3 = L.cache[1:3]
    U = reshape(u, (ni, no*k))

    """
        v .= kron(B, A) * u
        V .= A * U * B'
    """

    # C .= A * U
    mul!(C1, inner, U)

    # V .= U * B' <===> V' .= B * C'
    outer_mul!(v, L, u)

    v
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat, α, β)
    @assert iscached(L) "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    outer, inner = L.ops

    mi, ni = size(inner)
    mo, no = size(outer)
    k = size(u, 2)

    C1 = first(L.cache)
    U = reshape(u, (ni, no*k))

    """
        v .= α * kron(B, A) * u + β * v
        V .= α * (A * U * B') + β * v
    """

    # C .= A * U
    mul!(C1, inner, U)

    # V = α(C * B') + β(V)
    c = reshape(C1, (mi * no, k))
    outer_mul!(v, L, c, α, β)

    v
end

function LinearAlgebra.ldiv!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat)
    @assert iscached(L) "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    outer, inner = L.ops

    mi , ni = size(inner)
    mo , no = size(outer)
    k = size(u, 2)

    C5 = L.cache[5]
    U  = reshape(u, (mi, mo * k))

    """
        v .= kron(B, A) ldiv u
        V .= (A ldiv U) / B'
    """

    # C .= A \ U
    ldiv!(C5, inner, U)

    # V .= C / B' <==> V' .= B \ C'
    c = reshape(C5, (ni * mo, k))
    outer_div!(v, L, c)

    v
end

function LinearAlgebra.ldiv!(L::TensorProductOperator, u::AbstractVecOrMat)
    outer, inner = L.ops

    msg = "Two-argument ldiv! is only available for square operators"
    @assert issquare(L) msg
    @assert issquare(inner) msg
    @assert issquare(outer) msg

    @assert iscached(L) "cache needs to be set up for operator of type $(typeof(L)).
    set up cache by calling cache_operator(L::AbstractSciMLOperator, u::AbstractArray)"

    mi = size(inner, 1)
    mo = size(outer, 1)
    k  = size(u, 2)

    U = reshape(u, (mi, mo * k))

    """
        u .= kron(B, A) ldiv u
        U .= (A ldiv U) / B'
    """

    # U .= A \ U
    ldiv!(inner, U)

    # U .= U / B' <==> U' .= B \ U'
    outer_div!(L, u)

    u
end


# helper functions
const PERM = (2, 1, 3)

function outer_mul(L::TensorProductOperator, u::AbstractVecOrMat, C::AbstractVecOrMat)
    outer, inner = L.ops

    if outer isa IdentityOperator
        return C
    elseif outer isa ScaledOperator
        return outer.λ * outer_mul(outer.L, u, C)
    end

    k = size(u, 2)
    if k == 1
        return transpose(outer * transpose(C))
    end

    mi, _  = size(inner)
    mo, no = size(outer)
#   m , n  = size(L)

    C = reshape(C, (mi, no, k))
    C = permutedims(C, PERM)
    C = reshape(C, (no, mi*k))

    V = outer * C
    V = reshape(V, (mo, mi, k))
    V = permutedims(V, PERM)

    V
end

function outer_mul!(v::AbstractVecOrMat, L::TensorProductOperator, u::AbstractVecOrMat)
    outer, inner = L.ops

    C1 = first(L.cache)

    if outer isa IdentityOperator
        copyto!(v, C1)
        return v
    elseif outer isa ScaledOperator
        outer_mul!(v, outer.L, u)
        lmul!(outer.λ, v)
        return v
    end

    mi, _  = size(inner)
    mo, no = size(outer)
#   m , n  = size(L)
    k = size(u, 2)

    if k == 1
        V  = reshape(v, (mi, mo))
        C1 = reshape(C1, (mi, no))
        mul!(transpose(V), outer, transpose(C1))
        return v
    end

    C2, C3 = L.cache[2:3]

    C1 = reshape(C1, (mi, no, k))
    permutedims!(C2, C1, PERM)
    C2 = reshape(C2, (no, mi*k))
    mul!(C3, outer, C2)
    C3 = reshape(C3, (mo, mi, k))
    V  = reshape(v , (mi, mo, k))
    permutedims!(V, C3, PERM)

    v
end

function outer_mul!(v::AbstractVecOrMat, L::TensorProductOperator,
                    c::AbstractVecOrMat, α, β)
    outer, inner = L.ops

    m, _ = size(L)
    k = size(c, 2)

    if outer isa IdentityOperator
        c = reshape(c, (m, k))
        axpby!(α, c, β, v)
        return v
    elseif outer isa ScaledOperator
        a = convert(Number, α * outer.λ)
        outer_mul!(v, outer.L, c, a, β)
        return v
    end

    mi, _  = size(inner)
    mo, no = size(outer)

    if k == 1
        V = reshape(v, (mi, mo))
        C = reshape(c, (mi, no))
        mul!(transpose(V), outer, transpose(C), α, β)
        return v
    end

    C2, C3, c4 = L.cache[2:4]

    C = reshape(c, (mi, no, k))
    permutedims!(C2, C, PERM)
    C2 = reshape(C2, (no, mi*k))
    mul!(C3, outer, C2)
    C3 = reshape(C3, (mo, mi, k))
    V  = reshape(v , (mi, mo, k))
    copy!(c4, v)
    permutedims!(V, C3, PERM)
    axpby!(β, c4, α, v)

    v
end

function outer_div(L::TensorProductOperator, u::AbstractVecOrMat, C::AbstractVecOrMat)
    outer, inner = L.ops

    if outer isa IdentityOperator
        return C
    elseif outer isa ScaledOperator
        return outer.λ \ outer_div(outer.L, u, C)
    end

    k = size(u, 2)
    if k == 1
        return transpose(outer \ transpose(C))
    end

    _ , ni = size(inner)
    mo, no = size(outer)

    C = reshape(C, (ni, mo, k))
    C = permutedims(C, PERM)
    C = reshape(C, (mo, ni * k))

    V = outer \ C
    V = reshape(V, (no, ni, k))
    V = permutedims(V, PERM)

    V
end

function outer_div!(v::AbstractVecOrMat, L::TensorProductOperator, c::AbstractVecOrMat)
    outer, inner = L.ops

    if outer isa IdentityOperator
        copyto!(v, c)
        return v
    elseif outer isa ScaledOperator
        outer_div!(v, outer.L, c)
        ldiv!(outer.λ, v)
        return v
    end

    mi, ni = size(inner)
    mo, no = size(outer)
    k = size(c, 2)

    if k == 1
        V = reshape(v, (ni, no))
        C = reshape(c, (ni, mo))
        ldiv!(transpose(V), outer, transpose(C))
        return v
    end

    C6, C7 = L.cache[6:7]

    C = reshape(c, (ni, mo, k))
    permutedims!(C6, C, PERM)
    C6 = reshape(C6, (mo, ni*k))
    ldiv!(C7, outer, C6)
    C7 = reshape(C7, (no, ni, k))
    V  = reshape(v , (ni, no, k))
    permutedims!(V, C7, PERM)

    v
end

function outer_div!(L::TensorProductOperator, u::AbstractVecOrMat)
    outer, inner = L.ops

    if outer isa IdentityOperator
        return u
    elseif outer isa ScaledOperator
        outer_div!(outer.L, u)
        ldiv!(outer.λ, u)
        return u
    end

    _ , ni = size(inner)
    _ , no = size(outer)
    k = size(u, 2)

    U = reshape(u, (ni, no*k))

    if k == 1
        ldiv!(outer, transpose(U))
        return u
    end

    C = first(L.cache)

    U = reshape(U, (ni, no, k))
    C = reshape(C, (no, ni, k))
    permutedims!(C, U, PERM)
    ldiv!(outer, C)
    permutedims!(U, C, PERM)

    u
end
#
