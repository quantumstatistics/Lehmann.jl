# using QR
using Lehmann
using StaticArrays, Printf
using CompositeGrids
using LinearAlgebra
using DelimitedFiles

struct MatsuGrid{Float} <: FQR.Grid
    n::Int             # actual location of the grid point   
    coord::Int         # integer coordinate of the grid point on the fine meshes
    vec::Vector{Complex{Float}}
end

Base.show(io::IO, grid::MatsuGrid) = print(io, "n = ($(@sprintf("%d", grid.n[1])))")

struct MatsuFineMesh{Float} <: FQR.FineMesh
    isFermi::Bool                   #Fermion or Bosonic Matsubara Frequency
    symmetry::Int                         # symmetrize (omega1, omega2) <-> (omega2, omega1)
    candidates::Vector{MatsuGrid{Float}}       # vector of grid points
    selected::Vector{Bool}
    residual::Vector{Float}
    L2grids::Vector{MatsuGrid{Float}}  
    residual_L2::Vector{Float}
    Lambda::Float
    simplegrid::Bool
    ## for frequency mesh only ###
    fineGrid::Vector{Int}         # fine grid for each dimension
    function MatsuFineMesh{Float}(Λ, FreqMesh, isFermi; sym=1, degree = 12, ratio = 2.0, simplegrid) where {Float}
        # initialize the residual on fineGrid with <g, g>

        #_finegrid = Float.(fineGrid(Λ, rtol))
        _finegrid = Int.(nGrid(isFermi, Float(Λ), degree, Float(ratio) ))
        #print("ngrid $(_finegrid)\n")
        # separationTest(_finegrid)
        mesh = new(isFermi, sym, [], [], [], [], [], Λ, simplegrid, _finegrid)
        if simplegrid
            #candidate_grid = log_tauGrid(Float(2.0e-04), Float(1.2^2))
            #candidate_grid = log_nGrid(isFermi, FreqMesh)
            candidate_grid = log_nGrid(isFermi, Float(10.0Λ), 8)
            #candidate_grid = Int.(nGrid(isFermi, Float(0.01*Λ), 1, Float(1.2) ))
        else 
            candidate_grid = _finegrid
        end
        for (xi, x) in enumerate(candidate_grid)
            coord = xi
            #if irreducible(coord, sym, Nfine)  # if grid point is in the reducible zone, then skip residual initalization
            if isFermi
                vec = [Spectral.kernelFermiSymΩ(x, ω, Float.(1.0)) for ω in FreqMesh]
            else
                vec = [Spectral.kernelBoseSymΩ(x, ω, Float.(1.0)) for ω in FreqMesh]
            end
            g = MatsuGrid(x, coord, vec)
            push!(mesh.candidates, g)
            push!(mesh.residual, real.(FQR.dot(mesh, g, g)) )
            push!(mesh.selected, false)
            #end
        end
        for (xi, x) in enumerate(_finegrid)
            coord = xi
            #if irreducible(coord, sym, Nfine)  # if grid point is in the reducible zone, then skip residual initalization
            if isFermi
                vec = [Spectral.kernelFermiSymΩ(x, ω, Float.(1.0)) for ω in FreqMesh]
            else
                vec = [Spectral.kernelBoseSymΩ(x, ω, Float.(1.0)) for ω in FreqMesh]
            end
            g = MatsuGrid(x, coord, vec)
            push!(mesh.L2grids, g)
            push!(mesh.residual_L2, real.(FQR.dot(mesh, g, g)) )
            #end
        end
        return mesh
    end
end

function Freq2Index(isFermi, ωnList)
    if isFermi
        # ωn=(2n+1)π
        return [Int(round((ωn / π - 1) / 2)) for ωn in ωnList]
    else
        # ωn=2nπ
        return [Int(round(ωn / π / 2)) for ωn in ωnList]
    end
end

# function log_nGrid(isFermi, freqGrid) 
#     nGrid = zeros(Int, (length(freqGrid) - 1 )÷2)
#     nGrid = Freq2Index(isFermi, freqGrid[(length(freqGrid)+1)÷2+1:end])
    
#     unique!(nGrid)
#     if isFermi
#         return vcat(-nGrid[end:-1:1] .-1, nGrid)
#     else
#         return  vcat(-nGrid[end:-1:2], nGrid)
#     end
# end

function log_nGrid(isFermi, Λ::Float, N::Int) where {Float}
    nGrid = Int[]
    g1 = 0
    step = 1
    NN = N
    i = 1
    while (g1*2 + 1)*π < Λ
        append!(nGrid, g1)
        g1 += step
        if i%NN == 0
            step *= 2
            # if NN > 1
            #     NN = NN ÷ 2
            # else
            #     NN = 1
            # end
        end
        i += 1
    end
    if isFermi
        return vcat(-nGrid[end:-1:1] .-1, nGrid)
    else
        return  vcat(-nGrid[end:-1:2], nGrid)
    end
end



function nGrid(isFermi, Λ::Float, degree, ratio::Float) where {Float}
    # generate n grid from a logarithmic fine grid
    np = Int(round(log(10*10*10 * Λ) / log(ratio)))
    xc = [(i - 1) / degree for i = 1:degree]
    panel = [ratio^(i - 1) - 1 for i = 1:(np+1)]
    nGrid = zeros(Int, np * degree)
    for i = 1:np
        a, b = panel[i], panel[i+1]
        nGrid[(i-1)*degree+1:i*degree] = Freq2Index(isFermi, a .+ (b - a) .* xc)
    end
    unique!(nGrid)
    if isFermi
        return vcat(-nGrid[end:-1:1] .-1, nGrid)
    else
        return  vcat(-nGrid[end:-1:2], nGrid)
    end
end

# """
# composite expoential grid
# """
# function fineGrid(Λ, rtol)
#     ############## use composite grid #############################################
#     # Generating a log densed composite grid with LogDensedGrid()
#     npo = Int(ceil(log(Λ) / log(2.0))) - 2 # subintervals on [0,1/2] in tau space (# subintervals on [0,1] is 2*npt)
#     grid = CompositeGrid.LogDensedGrid(
#         :gauss,# The top layer grid is :gauss, optimized for integration. For interpolation use :cheb
#         [0.0, 1.0],# The grid is defined on [0.0, β]
#         [0.0, 1.0],# and is densed at 0.0 and β, as given by 2nd and 3rd parameter.
#         10,# N of log grid
#         0.00005, # minimum interval length of log grid
#         10 # N of bottom layer
#     )
#     print(grid[1:length(grid)÷2+1])    
#     print(grid+reverse(grid))
#     # println("Composite expoential grid size: $(length(grid))")
#     println("fine grid size: $(length(grid)) within [$(grid[1]), $(grid[end])]")
#     return grid
# end

# function irreducible(coord, symmetry,length)
#     @assert iseven(length) "The fineGrid should have even number of points"
#     if symmetry == 0
#         return true
#     else
#         return coord<length÷2+1
#     end
# end

# function FQR.irreducible(grid::MatsuGrid)
#     return irreducible(grid.coord, mesh.symmetry, length(mesh.fineGrid))
# end

function FQR.mirror(mesh::MatsuFineMesh{Float}, idx) where {Float}
    grid = mesh.candidates[idx]
    meshsize = length(mesh.candidates)
    if mesh.symmetry == 0
        return [],[]
    else
        idxmirror =[]
        newgrids = MatsuGrid{Float}[]
        #coords = unique([(idx), (meshsize - idx)])
        if !mesh.isFermi && grid.n==0 #For boson, n==0 do not have mirror point
            return newgrids,idxmirror
        else
            g = deepcopy(mesh.candidates[meshsize - idx+1])
        end
        #print("\n$(mesh.candidates[meshsize - idx+1].tau+mesh.candidates[idx].tau)\n")
        push!(newgrids, g)
        push!(idxmirror,meshsize - idx+1 )
        return newgrids,idxmirror
    end
    # end
end


"""
basis dot
"""
function FQR.dot(mesh, g1::MatsuGrid, g2::MatsuGrid)
    # println("dot: ", g1, ", ", g2)
    return dot(g1.vec, g2.vec)
        
end




if abspath(PROGRAM_FILE) == @__FILE__

    
    lambda, β, rtol = 100000, 1.0,1e-8
    dlr = DLRGrid(Euv=Float64(lambda), beta=β, rtol=Float64(rtol), isFermi=true, symmetry=:sym, rebuild=false)
    print("rtol $(dlr.rtol)")
    dlrfile = "basis.dat"
    data = readdlm(dlrfile,'\n')
    FreqGrid = Float.(data[:,1])
    #FreqGrid = Float.(dlr.ω)
    #print("$(FreqGrid)\n")
    mesh = MatsuFineMesh(lambda,FreqGrid, true, sym=1)
    size = length(mesh.candidates)
    size2 = length(mesh.candidates[1].vec)
    println("$(mesh.candidates[size÷2].n),$(mesh.candidates[size÷2].vec[size2÷2]),$(mesh.candidates[size÷2+1].vec[size2÷2])")
    # KK = zeros(3, 3)
    # n = (2, 2)
    # o = (mesh.fineGrid[n[1]], mesh.fineGrid[n[2]])
    # for i in 1:3
    #     g1 = FreqGrid{2}(i, o, n)
    #     for j in 1:3
    #         g2 = FreqGrid{2}(j, o, n)
    #         println(g1, ", ", g2)
    #         KK[i, j] = FQR.dot(mesh, g1, g2)
    #     end
    # end
    # display(KK)
    # println()

    basis = FQR.Basis{MatsuGrid,Float, Complex{Double}}(lambda, rtol, mesh)
    FQR.qr!(basis, verbose=1)

    # lambda, rtol = 1000, 1e-8
    # mesh = TauFineMesh{D}(lambda, rtol, sym=0)
    # basis = FQR.Basis{D,TauGrid{D}}(lambda, rtol, mesh)
    # @time FQR.qr!(basis, verbose=1)

    FQR.test(basis)

    mesh = basis.mesh
    grids = basis.grid
    n_grid = []
    for (i, grid) in enumerate(grids)
        push!(n_grid, grid.n)           
    end
    n_grid = sort(Int.(n_grid))
    #print(tau_grid)
    open("basis_n.dat", "w") do io
        for i in 1:length(n_grid)
            println(io, n_grid[i])
        end
    end

    # Nfine = length(mesh.fineGrid)
    # open("finegrid.dat", "w") do io
    #     for i in 1:Nfine
    #         println(io, basis.mesh.fineGrid[i])
    #     end
    # end
    # open("residual.dat", "w") do io
    #     # println(mesh.symmetry)
    #     residual = zeros(Double, Nfine, Nfine)
    #     for i in 1:length(mesh.candidates)
    #         if mesh.candidates[i].sector == 1
    #             x, y = mesh.candidates[i].coord
    #             residual[x, y] = mesh.residual[i]
    #             # println(x, ", ", y, " -> ", length(mirror(mesh, i)))

    #             for grid in FQR.mirror(mesh, i)
    #                 if grid.sector == 1
    #                     xp, yp = grid.coord
    #                     residual[xp, yp] = residual[x, y]
    #                     # println(xp, ", ", yp)
    #                 end
    #             end
    #         end
    #     end

    #     for i in 1:Nfine
    #         for j in 1:Nfine
    #             println(io, residual[i, j])
    #         end
    #     end
    # end
end