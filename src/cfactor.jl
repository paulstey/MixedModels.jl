"""
    cfactor!(A)

A slightly modified version of `chol!` from `julia/base/linalg/cholesky.jl`

Uses `inject!` (as opposed to `copy!`), `downdate!` (as opposed to `syrk!` or `gemm!`)
and recursive calls to `cfactor!`

Args:

-`A`: A `Matrix`

Note: The `cfactor!` method for dense matrices calls `LAPACK.potrf!` directly to avoid
errors being thrown when `A` is computationally singular
"""
function cfactor!(A::AbstractMatrix)
    n = Compat.LinAlg.checksquare(A)
    for k = 1:n
        Akk = A[k, k]
        for i in 1:(k - 1)
            downdate!(Akk, A[i, k])  # A[k,k] -= A[i,k]'A[i,k]
        end
        Akk = cfactor!(Akk)          # right Cholesky factor of A[k,k]
        for j in (k + 1):n
            for i in 1:(k - 1)
                downdate!(A[k, j], A[i, k], A[i, j]) # A[k,j] -= A[i,k]'A[i,j]
            end
            Base.LinAlg.Ac_ldiv_B!(Akk, A[k, j])
        end
    end
    UpperTriangular(A)
end

function cfactor!(D::Diagonal)
    map!(sqrt, D.diag)
    D
end

cfactor!(A::Matrix{Float64}) = UpperTriangular(Base.LinAlg.LAPACK.potrf!('U', A)[1])

function cfactor!(A::HBlkDiag)
    Aa = A.arr
    r, s, k = size(Aa)
    for i in 1:k
        Base.LinAlg.chol!(sub(Aa, :, :, i))
    end
    UpperTriangular(A)
end

"""
    downdate!(C, A)
    downdate!(C, A, B)

Subtract, in place, `A'A` or `A'B` from `C`
"""
downdate!{T<:Base.LinAlg.BlasFloat}(C::DenseMatrix{T},A::DenseMatrix{T}) =
    BLAS.syrk!('U', 'T', -one(T), A, one(T), C)

downdate!{T<:Base.LinAlg.BlasFloat}(C::DenseMatrix{T}, A::DenseMatrix{T}, B::DenseMatrix{T}) =
    BLAS.gemm!('T', 'N', -one(T), A, B, one(T), C)

function downdate!{T}(C::Diagonal{T}, A::SparseMatrixCSC{T})
    m, n = size(A)
    dd = C.diag
    if length(dd) ≠ n
        throw(DimensionMismatch("size(C,2) ≠ size(A,2)"))
    end
    nz = nonzeros(A)
    for j in eachindex(dd)
        for k in nzrange(A, j)
            @inbounds dd[j] -= abs2(nz[k])
        end
    end
    C
end

function downdate!{T}(C::Diagonal{T},A::Diagonal{T})
    if size(C) ≠ size(A)
        throw(DimensionMismatch("size(C) ≠ size(A)"))
    end
    c, a = C.diag, A.diag
    for i in eachindex(c)
        c[i] -= abs2(a[i])
    end
    C
end

function downdate!{T}(C::Diagonal{T}, A::Diagonal{T}, B::Diagonal{T})
    if !(size(C) == size(A) == size(B))
        throw(DimensionMismatch("need size(C) == size(A) == size(B)"))
    end
    c, a, b = C.diag, A.diag, B.diag
    for i in eachindex(c)
        c[i] -= a[i] * b[i]
    end
    C
end

function downdate!{T}(C::DenseMatrix{T}, A::Diagonal{T}, B::DenseMatrix{T})
    a = A.diag
    if ((m, n) = size(B)) ≠ size(C)
        throw(DimensionMismatch("size(B) ≠ size(C)"))
    end
    if length(a) ≠ m
        throw(DimensionMismatch("size(A,2) ≠ size(B,1)"))
    end
    for j in 1:n, i in 1:m
        C[i,j] -= a[i] * B[i,j]
    end
    C
end

function downdate!{T}(C::DenseMatrix{T}, A::SparseMatrixCSC{T}, B::DenseMatrix{T})
    m, n = size(A)
    r, s = size(C)
    if r ≠ n || s ≠ size(B,2) || m ≠ size(B,1)
        throw(DimensionMismatch("size(C,1) ≠ size(A,2) or size(C,2) ≠ size(B,2) or size(A,1) ≠ size(B,1)"))
    end
    nz = nonzeros(A)
    rv = rowvals(A)
    for jj in 1:s, j in 1:n, k in nzrange(A,j)
        C[j,jj] -= nz[k] * B[rv[k], jj]
    end
    C
end

function downdate!{T}(C::DenseMatrix{T}, A::SparseMatrixCSC{T}, B::SparseMatrixCSC{T})
    AtB = A'B
    if size(C) ≠ size(AtB)
        throw(DimensionMismatch("size(C) ≠ size(A'B)"))
    end
    atbrv = rowvals(AtB)
    atbnz = nonzeros(AtB)
    for j in 1:size(AtB, 2)
        for k in nzrange(AtB, j)
            C[atbrv[k], j] -= atbnz[k]
        end
    end
    C
end

function downdate!{T}(C::DenseMatrix{T}, A::SparseMatrixCSC{T})
    m, n = size(A)
    if n ≠ Compat.LinAlg.checksquare(C)
        throw(DimensionMismatch("C is not square or size(C,2) ≠ size(A,2)"))
    end
    # FIXME: avoid allocation by caching a transposed matrix and just fill in the new values
    # alternatively, work with the lower Cholesky factor L instead of R
    At = A'
    rv = rowvals(A)
    nz = nonzeros(A)
    rvt = rowvals(At)
    nzt = nonzeros(At)
    cp = A.colptr
    @inbounds for j in 1:n
        for jp in nzrange(A, j)
            nzB = nz[jp]
            k = rv[jp]
            for kp in nzrange(At, k)
                C[rvt[kp], j] -= nzt[kp] * nzB
            end
        end
    end
    C
end

## FIXME: Need a downdate! method for SparseMatrixCSC, SparseMatrixCSC, SparseMatrixCSC (3 or more nested)
