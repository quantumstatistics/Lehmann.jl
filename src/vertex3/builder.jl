using LinearAlgebra, Printf
using StaticArrays
# using GenericLinearAlgebra
using Lehmann

const Float = Float64

### faster, a couple of less digits
using DoubleFloats
# const Float = Double64
const Double = Double64

# similar speed as DoubleFloats
# using MultiFloats
# const Float = Float64x2
# const Double = Float64x2

### a couple of more digits, but slower
# using Quadmath
# const Float = Float128

### 64 digits by default, but a lot more slower
# const Float = BigFloat

abstract type Grid end
abstract type FineMesh end

include("./frequency.jl")

mutable struct Basis{D,Grid,Mesh}
    ############    fundamental parameters  ##################
    Λ::Float  # UV energy cutoff * inverse temperature
    rtol::Float # error tolerance

    ###############     DLR grids    ###############################
    N::Int # number of basis
    grid::Vector{Grid} # grid for the basis
    error::Vector{Float}  # the relative error achieved by adding the current grid point 

    ###############  linear coefficients for orthognalization #######
    Q::Matrix{Double} # , Q = R^{-1}, Q*R'= I
    R::Matrix{Double}

    ############ fine mesh #################
    mesh::Mesh

    function Basis{d,Grid,Mesh}(Λ, rtol; sym = 1) where {d,Grid,Mesh}
        _Q = Matrix{Float}(undef, (0, 0))
        _R = similar(_Q)
        mesh = Mesh(Λ, rtol, sym)
        return new{d,Grid,Mesh}(Λ, rtol, 0, [], [], _Q, _R, mesh)
    end
end

function addBasis!(basis::Basis{D,G,M}, grid, verbose) where {D,G,M}
    basis.N += 1
    push!(basis.grid, grid)

    basis.Q, basis.R = GramSchmidt(basis)

    # update the residual on the fine mesh
    updateResidual!(basis)

    # the new rtol achieved by adding the new grid point
    push!(basis.error, sqrt(maximum(basis.mesh.residual)))

    (verbose > 0) && @printf("%3i %s -> error=%16.8g, Rmin=%16.8g\n", basis.N, "$(grid)", basis.error[end], basis.R[end, end])
end

function addBasisBlock!(basis::Basis{D,G,M}, idx, verbose) where {D,G,M}
    addBasis!(basis, basis.mesh.candidates[idx], verbose)

    ## before set the residual of the selected grid point to be zero, do some check
    # residual = sqrt(basis.mesh.residual[idx])
    # _norm = basis.R[end, end]
    # @assert abs(_norm - residual) < basis.rtol * 100 "inconsistent norm on the grid $(basis.grid[end]) $_norm - $residual = $(_norm-residual)"
    # if abs(_norm - residual) > basis.rtol * 10
    #     @warn("inconsistent norm on the grid $(basis.grid[end]) $_norm - $residual = $(_norm-residual)")
    # end

    ## set the residual of the selected grid point to be zero
    basis.mesh.selected[idx] = true
    basis.mesh.residual[idx] = 0 # the selected mesh grid has zero residual

    for grid in mirror(basis.mesh, idx)
        addBasis!(basis, grid, verbose)
    end
end

function updateResidual!(basis::Basis{D}) where {D}
    mesh = basis.mesh

    # q = Float.(basis.Q[end, :])
    q = Double.(basis.Q[:, end])

    Threads.@threads for idx in 1:length(mesh.candidates)
        if mesh.selected[idx] == false
            candidate = mesh.candidates[idx]
            pp = sum(q[j] * dot(mesh, basis.grid[j], candidate) for j in 1:basis.N)
            _residual = mesh.residual[idx] - pp * pp
            # println("working on $candidate : $_residual")
            if _residual < 0
                if _residual < -basis.rtol
                    @warn("warning: residual smaller than 0 at $candidate got $(mesh.residual[idx]) - $(pp)^2 = $_residual")
                end
                mesh.residual[idx] = 0
            else
                mesh.residual[idx] = _residual
            end
        end
    end
end

"""
Gram-Schmidt process to the last grid point in basis.grid
"""
function GramSchmidt(basis::Basis{D,G,M}) where {D,G,M}
    _Q = zeros(Double, (basis.N, basis.N))
    _Q[1:end-1, 1:end-1] = basis.Q

    _R = zeros(Double, (basis.N, basis.N))
    _R[1:end-1, 1:end-1] = basis.R
    _Q[end, end] = 1

    newgrid = basis.grid[end]

    overlap = [dot(basis.mesh, basis.grid[j], newgrid) for j in 1:basis.N]

    for qi in 1:basis.N-1
        _R[qi, end] = _Q[:, qi]' * overlap
        _Q[:, end] -= _R[qi, end] * _Q[:, qi]  # <q, qnew> q
    end

    _norm = dot(basis.mesh, newgrid, newgrid) - _R[:, end]' * _R[:, end]
    _norm = sqrt(abs(_norm))
    _R[end, end] = _norm
    _Q[:, end] /= _norm

    return _Q, _R
end

function testOrthgonal(basis::Basis{D}) where {D}
    println("testing orthognalization...")
    KK = zeros(Double, (basis.N, basis.N))
    Threads.@threads for i in 1:basis.N
        g1 = basis.grid[i]
        for (j, g2) in enumerate(basis.grid)
            KK[i, j] = dot(basis.mesh, g1, g2)
        end
    end
    maxerr = maximum(abs.(KK - basis.R' * basis.R))
    println("Max overlap matrix R'*R Error: ", maxerr)

    maxerr = maximum(abs.(basis.R * basis.Q - I))
    println("Max R*R^{-1} Error: ", maxerr)

    II = basis.Q' * KK * basis.Q
    maxerr = maximum(abs.(II - I))
    println("Max Orthognalization Error: ", maxerr)

end

# function testResidual(basis, proj)
#     # residual = [Residual(basis, proj, basis.grid[i, :]) for i in 1:basis.N]
#     # println("Max deviation from zero residual: ", maximum(abs.(residual)))
#     println("Max deviation from zero residual on the DLR grids: ", maximum(abs.(basis.residualFineGrid[basis.gridIdx])))
# end

function QR!(basis::Basis{dim,G,M}; idx0 = [1,], N = 10000, verbose = 0) where {dim,G,M}
    #### add the grid in the idx vector first
    # println(basis.mesh.candidates[1:4])
    # println(basis.mesh.residual[1:4])

    for i in idx0
        addBasisBlock!(basis, i, verbose)
        # println(basis.R)
        # println(basis.mesh.residual[1:4])
    end

    ####### add grids that has the maximum residual

    maxResidual, idx = findmax(basis.mesh.residual)
    while sqrt(maxResidual) > basis.rtol && basis.N < N

        addBasisBlock!(basis, idx, verbose)

        # plotResidual(basis)
        # testOrthgonal(basis)
        maxResidual, idx = findmax(basis.mesh.residual)

        # println(basis.R)
        # println(basis.mesh.residual[1:4])
        # exit(0)
    end
    @printf("rtol = %.16e\n", sqrt(maxResidual))
    # plotResidual(basis)
    # plotResidual(basis, proj, Float(0), Float(100), candidate, residual)
    return basis
end

if abspath(PROGRAM_FILE) == @__FILE__

    D = 2
    basis = Basis{D,FreqGrid{D},FreqFineMesh{D}}(10, 1e-4, sym = 1)
    QR!(basis, verbose = 1)

    basis = Basis{D,FreqGrid{D},FreqFineMesh{D}}(640, 1e-8, sym = 1)
    @time QR!(basis, verbose = 1)

    testOrthgonal(basis)
end

# function plotResidual(basis)
#     z = Float64.(basis.residualFineGrid)
#     z = reshape(z, (basis.Nfine, basis.Nfine))
#     # contourf(z)
#     # println(basis.fineGrid)
#     # println(basis.grid)
#     # p = heatmap(Float64.(basis.fineGrid), Float64.(basis.fineGrid), z, xaxis = :log, yaxis = :log)
#     p = heatmap(Float64.(basis.fineGrid), Float64.(basis.fineGrid), z)
#     # p = heatmap(z)
#     x = [basis.grid[i][1] for i in 1:basis.N]
#     y = [basis.grid[i][2] for i in 1:basis.N]
#     scatter!(p, x, y)

#     display(p)
#     readline()
# end