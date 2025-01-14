#
###
# AbstractSciMLScalarOperator interface
###

SCALINGNUMBERTYPES = (
                      :AbstractSciMLScalarOperator,
                      :Number,
                      :UniformScaling,
                     )

#=
The identity operator must be listed here
so that rules for combination with scalar
operators take precedence over rules for
combining with the identity operator when
the two are combined together.
=#
SCALINGCOMBINETYPES = (
    :AbstractSciMLOperator,
    :IdentityOperator
)

Base.length(::AbstractSciMLScalarOperator) = 1
Base.size(α::AbstractSciMLScalarOperator) = ()
Base.adjoint(α::AbstractSciMLScalarOperator) = conj(α)
Base.transpose(α::AbstractSciMLScalarOperator) = α

has_mul!(::AbstractSciMLScalarOperator) = true
islinear(::AbstractSciMLScalarOperator) = true
has_adjoint(::AbstractSciMLScalarOperator) = true

Base.:*(α::AbstractSciMLScalarOperator, u::AbstractVecOrMat) = convert(Number, α) * u
Base.:\(α::AbstractSciMLScalarOperator, u::AbstractVecOrMat) = convert(Number, α) \ u

LinearAlgebra.rmul!(u::AbstractVecOrMat, α::AbstractSciMLScalarOperator) = rmul!(u, convert(Number, α))
LinearAlgebra.lmul!(α::AbstractSciMLScalarOperator, u::AbstractVecOrMat) = lmul!(convert(Number, α), u)
LinearAlgebra.ldiv!(α::AbstractSciMLScalarOperator, u::AbstractVecOrMat) = ldiv!(convert(Number, α), u)
function LinearAlgebra.ldiv!(v::AbstractVecOrMat, α::AbstractSciMLScalarOperator, u::AbstractVecOrMat)
    ldiv!(v, convert(Number, α), u)
end

function LinearAlgebra.mul!(v::AbstractVecOrMat, α::AbstractSciMLScalarOperator, u::AbstractVecOrMat)
    x = convert(Number, α)
    mul!(v, x, u)
end

function LinearAlgebra.mul!(v::AbstractVecOrMat,
                            α::AbstractSciMLScalarOperator,
                            u::AbstractVecOrMat,
                            a::Union{Number,AbstractSciMLScalarOperator},
                            b::Union{Number,AbstractSciMLScalarOperator})
    α = convert(Number, α)
    a = convert(Number, a)
    b = convert(Number, b)
    mul!(v, α, u, a, b)
end

function LinearAlgebra.axpy!(α::AbstractSciMLScalarOperator,
                             x::AbstractVecOrMat,
                             y::AbstractVecOrMat)
    α = convert(Number, α)
    axpy!(α, x, y)
end

function LinearAlgebra.axpby!(α::AbstractSciMLScalarOperator,
                              x::AbstractVecOrMat,
                              β::Number,
                              y::AbstractVecOrMat)
    α = convert(Number, α)
    axpby!(α, x, β, y)
end

function LinearAlgebra.axpby!(α::Number,
                              x::AbstractVecOrMat,
                              β::AbstractSciMLScalarOperator,
                              y::AbstractVecOrMat)
    β = convert(Number, β)
    axpby!(α, x, β, y)
end

function LinearAlgebra.axpby!(α::AbstractSciMLScalarOperator,
                              x::AbstractVecOrMat,
                              β::AbstractSciMLScalarOperator,
                              y::AbstractVecOrMat)
    α = convert(Number, α)
    β = convert(Number, β)
    axpby!(α, x, β, y)
end

Base.:+(α::AbstractSciMLScalarOperator) = α

"""
    ScalarOperator(val[; update_func])

    (α::ScalarOperator)(a::Number) = α * a

Represents a time-dependent scalar/scaling operator. The update function
is called by `update_coefficients`/ `update_coefficients!` and is assumed
to have the following signature:

    update_func(oldval,u,p,t) -> newval
"""
mutable struct ScalarOperator{T<:Number,F} <: AbstractSciMLScalarOperator{T}
    val::T
    update_func::F
end

function ScalarOperator(val::T; update_func=DEFAULT_UPDATE_FUNC) where{T}
    ScalarOperator(val, update_func)
end

# constructors
Base.convert(T::Type{<:Number}, α::ScalarOperator) = convert(T, α.val)
Base.convert(::Type{ScalarOperator}, α::Number) = ScalarOperator(α)

ScalarOperator(α::AbstractSciMLScalarOperator) = α
ScalarOperator(λ::UniformScaling) = ScalarOperator(λ.λ)

# traits
function Base.conj(α::ScalarOperator) # TODO - test
    val = conj(α.val)
    update_func = (oldval,u,p,t) -> α.update_func(oldval |> conj,u,p,t) |> conj
    ScalarOperator(val; update_func=update_func)
end

Base.one(::AbstractSciMLScalarOperator{T}) where{T} = ScalarOperator(one(T))
Base.zero(::AbstractSciMLScalarOperator{T}) where{T} = ScalarOperator(zero(T))

Base.one(::Type{<:AbstractSciMLScalarOperator}) = ScalarOperator(true)
Base.zero(::Type{<:AbstractSciMLScalarOperator}) = ScalarOperator(false)
Base.abs(α::ScalarOperator) = abs(α.val)

Base.iszero(α::ScalarOperator) = iszero(α.val)

getops(α::ScalarOperator) = (α.val,)
isconstant(α::ScalarOperator) = α.update_func == DEFAULT_UPDATE_FUNC
has_ldiv(α::ScalarOperator) = !iszero(α.val)
has_ldiv!(α::ScalarOperator) = has_ldiv(α)

update_coefficients(L::ScalarOperator, u, p, t) = @set! L.val = L.update_func(L.val, u, p, t)
update_coefficients!(L::ScalarOperator, u, p, t) = (L.val = L.update_func(L.val,u,p,t); L)

"""
Lazy addition of Scalar Operators
"""
struct AddedScalarOperator{T,O} <: AbstractSciMLScalarOperator{T}
    ops::O

    function AddedScalarOperator(ops::NTuple{N,AbstractSciMLScalarOperator}) where{N}
        @assert !isempty(ops)
        T = promote_type(eltype.(ops)...)
        new{T,typeof(ops)}(ops)
    end
end

# constructors
function AddedScalarOperator(ops::AbstractSciMLScalarOperator...)
    AddedScalarOperator(ops)
end

Base.:+(ops::AbstractSciMLScalarOperator...) = AddedScalarOperator(ops...)
Base.:+(A::AddedScalarOperator, B::AddedScalarOperator) = AddedScalarOperator(A.ops..., B.ops...)
Base.:+(A::AbstractSciMLScalarOperator, B::AddedScalarOperator) = AddedScalarOperator(A, B.ops...)
Base.:+(A::AddedScalarOperator, B::AbstractSciMLScalarOperator) = AddedScalarOperator(A.ops..., B)
Base.:-(A::AbstractSciMLScalarOperator, B::AbstractSciMLScalarOperator) = AddedScalarOperator(A, -B)

for op in (
           :-, :+,
          )
    for T in SCALINGNUMBERTYPES[2:end]
        @eval Base.$op(α::AbstractSciMLScalarOperator, x::$T) = AddedScalarOperator(α, ScalarOperator($op(x)))
        @eval Base.$op(x::$T, α::AbstractSciMLScalarOperator) = AddedScalarOperator(ScalarOperator(x), $op(α))
    end
end

function Base.convert(T::Type{<:Number}, α::AddedScalarOperator)
    sum(convert.(T, α.ops))
end

Base.conj(L::AddedScalarOperator) = AddedScalarOperator(conj.(L.ops))

function update_coefficients(L::AddedScalarOperator, u, p, t)
    ops = ()
    for op in L.ops
        ops = (ops...,  update_coefficients(op, u, p, t))
    end

    @set! L.ops = ops
end

getops(α::AddedScalarOperator) = α.ops
has_ldiv(α::AddedScalarOperator) = !iszero(convert(Number, α))
has_ldiv!(α::AddedScalarOperator) = has_ldiv(α)

"""
Lazy composition of Scalar Operators
"""
struct ComposedScalarOperator{T,O} <: AbstractSciMLScalarOperator{T}
    ops::O

    function ComposedScalarOperator(ops::NTuple{N,AbstractSciMLScalarOperator}) where{N}
        @assert !isempty(ops)
        T = promote_type(eltype.(ops)...)
        new{T,typeof(ops)}(ops)
    end
end

# constructor
function ComposedScalarOperator(ops::AbstractSciMLScalarOperator...)
    ComposedScalarOperator(ops)
end

for op in (
           :*, :∘,
          )
    @eval Base.$op(ops::AbstractSciMLScalarOperator...) = reduce($op, ops)
    @eval Base.$op(A::AbstractSciMLScalarOperator, B::AbstractSciMLScalarOperator) = ComposedScalarOperator(A, B)
    @eval Base.$op(A::ComposedScalarOperator, B::AbstractSciMLScalarOperator) = ComposedScalarOperator(A.ops..., B)
    @eval Base.$op(A::AbstractSciMLScalarOperator, B::ComposedScalarOperator) = ComposedScalarOperator(A, B.ops...)
    @eval Base.$op(A::ComposedScalarOperator, B::ComposedScalarOperator) = ComposedScalarOperator(A.ops..., B.ops...)

    for T in SCALINGNUMBERTYPES[2:end]
        @eval Base.$op(α::AbstractSciMLScalarOperator, x::$T) = ComposedScalarOperator(α, ScalarOperator(x))
        @eval Base.$op(x::$T, α::AbstractSciMLScalarOperator) = ComposedScalarOperator(ScalarOperator(x), α)
    end
end

function Base.convert(T::Type{<:Number}, α::ComposedScalarOperator)
    iszero(α) && return zero(T)
    prod(convert.(T, α.ops))
end

Base.conj(L::ComposedScalarOperator) = ComposedScalarOperator(conj.(L.ops))
Base.:-(α::AbstractSciMLScalarOperator{T}) where{T} = (-one(T)) * α

function update_coefficients(L::ComposedScalarOperator, u, p, t)
    ops = ()
    for op in L.ops
        ops = (ops...,  update_coefficients(op, u, p, t))
    end

    @set! L.ops = ops
end

getops(α::ComposedScalarOperator) = α.ops
has_ldiv(α::ComposedScalarOperator) = all(has_ldiv, α.ops)
has_ldiv!(α::ComposedScalarOperator) = all(has_ldiv!, α.ops)

"""
Lazy inversion of Scalar Operators
"""
#=
Keeping with the style, we avoid use of the generic InvertedOperator and instead
have a specialized type for this purpose that subtypes AbstractSciMLScalarOperator.
=#
struct InvertedScalarOperator{T,λType} <: AbstractSciMLScalarOperator{T}
    λ::λType

    function InvertedScalarOperator(λ::AbstractSciMLScalarOperator{T}) where {T}
        new{T,typeof(λ)}(λ)
    end
end
Base.inv(L::AbstractSciMLScalarOperator) = InvertedScalarOperator(L)

for op in (
           :/,
          )
    for T in SCALINGNUMBERTYPES[2:end]
        @eval Base.$op(α::AbstractSciMLScalarOperator, x::$T) = α * inv(ScalarOperator(x))
        @eval Base.$op(x::$T, α::AbstractSciMLScalarOperator) = ScalarOperator(x) * inv(α)
    end

    @eval Base.$op(α::AbstractSciMLScalarOperator, β::AbstractSciMLScalarOperator) = α * inv(β)
end

for op in (
           :\,
          )
    for T in SCALINGNUMBERTYPES[2:end]
        @eval Base.$op(α::AbstractSciMLScalarOperator, x::$T) = inv(α) * ScalarOperator(x)
        @eval Base.$op(x::$T, α::AbstractSciMLScalarOperator) = inv(ScalarOperator(x)) * α
    end

    @eval Base.$op(α::AbstractSciMLScalarOperator, β::AbstractSciMLScalarOperator) = inv(α) * β
end

function Base.convert(T::Type{<:Number}, α::InvertedScalarOperator)
    inv(convert(Number, α.λ))
end

Base.conj(L::InvertedScalarOperator) = InvertedScalarOperator(conj(L.λ))

function update_coefficients(L::InvertedScalarOperator, u, p, t)
    @set! L.λ = update_coefficients(L.λ, u, p, t)
    L
end

getops(α::InvertedScalarOperator) = (α.λ,)
has_ldiv(α::InvertedScalarOperator) = has_mul(α.λ)
has_ldiv!(α::InvertedScalarOperator) = has_ldiv(α)
#
