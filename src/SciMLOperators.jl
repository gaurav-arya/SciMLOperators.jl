module SciMLOperators

using DocStringExtensions
using Reexport

using LinearAlgebra
import SparseArrays
import StaticArraysCore
import ArrayInterfaceCore
import Tricks: static_hasmethod
import Lazy: @forward
import Setfield: @set!
@reexport import TensorCore: ⊗

# overload
import Base: zero, one, oneunit
import Base: +, -, *, /, \, ∘, ==, conj, exp, kron
import Base: iszero, inv, adjoint, transpose, size, convert
import LinearAlgebra: mul!, ldiv!, lmul!, rmul!, factorize
import LinearAlgebra: Matrix, Diagonal
import SparseArrays: sparse, issparse

"""
$(TYPEDEF)
"""
abstract type AbstractSciMLOperator{T} end

"""
$(TYPEDEF)
"""
abstract type AbstractSciMLLinearOperator{T} <: AbstractSciMLOperator{T} end

"""
$(TYPEDEF)
"""
abstract type AbstractSciMLScalarOperator{T} <: AbstractSciMLLinearOperator{T} end

include("utils.jl")
include("interface.jl")
include("left.jl")
include("multidim.jl")

include("scalar.jl")
include("matrix.jl")
include("basic.jl")
include("batch.jl")
include("func.jl")
include("tensor.jl")

export ScalarOperator,
       MatrixOperator,
       DiagonalOperator,
       AffineOperator,
       AddVector,
       FunctionOperator,
       TensorProductOperator,
       IdentityOperator

export update_coefficients!,
       update_coefficients,

       cache_operator,

       has_adjoint,
       has_expmv,
       has_expmv!,
       has_exp,
       has_mul,
       has_mul!,
       has_ldiv,
       has_ldiv!

end # module
