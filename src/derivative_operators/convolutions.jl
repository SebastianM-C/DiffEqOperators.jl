# mul! done by convolutions
function LinearAlgebra.mul!(x_temp::AbstractVector{T}, A::DerivativeOperator, x::AbstractVector{T}) where T<:Real
    convolve_BC_left!(x_temp, x, A)
    convolve_interior!(x_temp, x, A)
    convolve_BC_right!(x_temp, x, A)
end

################################################

# Against a standard vector, assume already padded and just apply the stencil
function convolve_interior!(x_temp::AbstractVector{T}, x::AbstractVector{T}, A::DerivativeOperator) where {T<:Real}
    @assert length(x_temp)+2 == length(x)
    stencil = A.stencil_coefs
    coeff   = A.coefficients

    # Upwind operators have a non-centred stencil
    if use_winding(A)
        mid = 1 + A.stencil_length%2
    else
        mid = div(A.stencil_length,2)
    end

    for i in (1+A.boundary_point_count) : (length(x_temp)-A.boundary_point_count)
        xtempi = zero(T)
        cur_stencil = eltype(stencil) <: AbstractVector ? stencil[i-A.boundary_point_count] : stencil
        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i] : coeff isa Number ? coeff : true
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
        for idx in 1:A.stencil_length
            x_idx = use_winding(A) && cur_coeff < 0 ? x[i + mid - idx] : x[i - mid + idx]
            xtempi += cur_coeff * cur_stencil[idx] * x_idx
        end
        x_temp[i] = xtempi
    end
end

function convolve_BC_left!(x_temp::AbstractVector{T}, x::AbstractVector{T}, A::DerivativeOperator) where {T<:Real}
    stencil = A.low_boundary_coefs
    coeff   = A.coefficients

    _bpc = A.boundary_point_count
    flag = false
    if isempty(stencil)
        _bpc = A.boundary_point_count + 1
        flag = true
    end

    for i in 1 : _bpc
        if flag == true
            cur_stencil = A.stencil_coefs
            slen = length(A.stencil_coefs)
        else
            cur_stencil = stencil[i]
            slen = length(cur_stencil)
        end

        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i] : coeff isa Number ? coeff : true
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
        xtempi = cur_coeff*cur_stencil[1]*x[1]
        for idx in 2:slen
            xtempi += cur_coeff * cur_stencil[idx] * x[idx]
        end
        x_temp[i] = xtempi
    end
end

function convolve_BC_right!(x_temp::AbstractVector{T}, x::AbstractVector{T}, A::DerivativeOperator) where {T<:Real}
    stencil = A.high_boundary_coefs
    coeff   = A.coefficients
    N       = length(x)
    L       = A.boundary_stencil_length

    _bpc = A.boundary_point_count
    flag = false

    if isempty(stencil)
        _bpc = 1
        flag = true
    end

    for i in 1 : _bpc
        if flag == true
            cur_stencil = A.stencil_coefs
            slen = length(A.stencil_coefs)
            L = A.stencil_length
        else
            cur_stencil = stencil[i]
            slen = length(cur_stencil)
        end

        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i] : coeff isa Number ? coeff : true
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
        xtempi = zero(T)
        for idx in 1:slen
            xtempi += cur_coeff * cur_stencil[idx] * x[N-L+idx]
        end
        x_temp[end-_bpc+i] = xtempi
    end
end

###########################################

# Against A BC-padded vector, specialize the computation to explicitly use the left, right, and middle parts
function convolve_interior!(x_temp::AbstractVector{T}, _x::BoundaryPaddedVector, A::DerivativeOperator{T,N,true}) where {T<:Real,N}
    @assert length(x_temp) == length(_x.u)
    stencil = A.stencil_coefs
    coeff   = A.coefficients
    len = length(x_temp) + 2
    # Upwind operators have a non-centred stencil
    mid = 1 + A.stencil_length%2
    x = _x.u
    # Just do the middle parts
    for i in (1+A.boundary_point_count) : (length(x_temp)-A.boundary_point_count)
        xtempi = zero(T)
        cur_stencil = eltype(stencil) <: AbstractVector ? stencil[i-A.boundary_point_count] : stencil
        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i-A.boundary_point_count] : coeff isa Number ? coeff : true
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
        @inbounds for idx in 1:A.stencil_length
            # @show i, idx, cur_stencil[idx], i-mid+idx, x[i-mid+idx]
            if i-mid+idx == 1 || i+mid-idx == 1
                x_idx = _x.l
            elseif i-mid+idx == N || i+mid-idx == N
                x_idx = _x.r
            else
                x_idx = use_winding(A) && cur_coeff < 0 ? x[i + mid - idx - 1] : x[i - mid + idx - 1]
            end
            xtempi += cur_coeff * cur_stencil[idx] * x_idx
        end
        x_temp[i] = xtempi
    end
end

function convolve_interior!(x_temp::AbstractVector{T}, _x::BoundaryPaddedVector, A::DerivativeOperator{T,N,false}) where {T<:Real,N}
    @assert length(x_temp) == length(_x.u)
    stencil = A.stencil_coefs
    coeff   = A.coefficients
    len = length(x_temp) + 2

    mid = div(A.stencil_length,2)
    x = _x.u
    i = 1 + A.boundary_point_count
    idx = 1
    xtempi = zero(T)
    cur_stencil = eltype(stencil) <: AbstractVector ? stencil[i-A.boundary_point_count] : stencil
    cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i-A.boundary_point_count] : coeff isa Number ? coeff : true
    cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
    # @show cur_stencil
    x_idx = _x.l
    xtempi += cur_coeff * cur_stencil[idx] * x_idx
    @inbounds for idx in 2:A.stencil_length
        x_idx = use_winding(A) && cur_coeff < 0 ? x[i + mid - idx - 1] : x[i - mid + idx - 1]
        xtempi += cur_coeff * cur_stencil[idx] * x_idx
    end
    x_temp[i] = xtempi


    # Just do the middle parts
    for i in (2+A.boundary_point_count) : (length(x_temp)-A.boundary_point_count-1)
        xtempi = zero(T)
        cur_stencil = eltype(stencil) <: AbstractVector ? stencil[i-A.boundary_point_count] : stencil
        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i-A.boundary_point_count] : coeff isa Number ? coeff : true
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
        @inbounds for idx in 1:A.stencil_length
            x_idx = use_winding(A) && cur_coeff < 0 ? x[i + mid - idx - 1] : x[i - mid + idx - 1]
            xtempi += cur_coeff * cur_stencil[idx] * x_idx
        end
        x_temp[i] = xtempi
    end

    # The right boundary part
    i = length(x_temp)-A.boundary_point_count
    xtempi = zero(T)
    cur_stencil = eltype(stencil) <: AbstractVector ? stencil[i-A.boundary_point_count] : stencil
    cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i-A.boundary_point_count] : coeff isa Number ? coeff : true
    cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil
    @inbounds for idx in 1:A.stencil_length-1
        x_idx = use_winding(A) && cur_coeff < 0 ? x[i + mid - idx - 1] : x[i - mid + idx - 1]
        xtempi += cur_coeff * cur_stencil[idx] * x_idx
    end
    x_idx = _x.r
    idx = A.stencil_length
    xtempi += cur_coeff * cur_stencil[idx] * x_idx

    x_temp[i] = xtempi
end


function convolve_BC_left!(x_temp::AbstractVector{T}, _x::BoundaryPaddedVector, A::DerivativeOperator) where {T<:Real}
    stencil = A.low_boundary_coefs
    coeff   = A.coefficients

    _bpc = A.boundary_point_count
    flag = false

    if isempty(stencil)
        _bpc = 1
        flag = true
    end

    for i in 1 : _bpc
        if flag == true
            cur_stencil = A.stencil_coefs
            slen = length(A.stencil_coefs)
        else
            cur_stencil = stencil[i]
            slen = length(cur_stencil)
        end

        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[i] : coeff isa Number ? coeff : true
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil

        # need to account for x.l in first interior
        xtempi = cur_coeff*cur_stencil[1]*_x.l
        @inbounds for idx in 2:slen
            xtempi += cur_coeff * cur_stencil[idx] * _x.u[idx-1]
        end
        x_temp[i] = xtempi
    end
end

function convolve_BC_right!(x_temp::AbstractVector{T}, _x::BoundaryPaddedVector, A::DerivativeOperator) where {T<:Real}
    stencil = A.high_boundary_coefs
    coeff   = A.coefficients
    N = length(_x.u)
    bpc = A.boundary_point_count

    # need to account for _x.r in last interior convolution
    mid = div(A.stencil_length,2) + 1
    x = _x.u
    i = length(x_temp)-A.boundary_point_count
    L = A.boundary_stencil_length


    _bpc = A.boundary_point_count
    flag = false

    if isempty(stencil)
        _bpc = 1
        L = A.stencil_length
        flag = true
    end

    for i in 1 : _bpc
        if flag == true
            cur_stencil = A.stencil_coefs
            slen = length(A.stencil_coefs)
        else
            cur_stencil = stencil[i]
            slen = length(cur_stencil)
        end

        cur_coeff   = typeof(coeff)   <: AbstractVector ? coeff[end-_bpc+i] : coeff isa Number ? coeff : true
        xtempi = cur_coeff*cur_stencil[end]*_x.r
        cur_stencil = use_winding(A) && cur_coeff < 0 ? reverse(cur_stencil) : cur_stencil

        @inbounds for idx in slen-1:-1:1
            xtempi += cur_coeff * cur_stencil[end-idx] * _x.u[end-idx+1]
        end
        x_temp[end-_bpc+i] = xtempi
    end
end