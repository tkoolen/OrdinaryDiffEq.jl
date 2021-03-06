mutable struct ImplicitRHS_Scalar{F,uType,tType} <: Function
  f::F
  C::uType
  a::tType
  t::tType
  dt::tType
end

function (p::ImplicitRHS_Scalar)(u,resid)
  resid[1] = first(u) .- first(p.C) .- p.a.*first(p.f(p.t+p.dt,first(u)))
end

mutable struct ImplicitRHS{F,uType,tType,DiffCacheType} <: Function
  f::F
  C::uType
  a::tType
  t::tType
  dt::tType
  dual_cache::DiffCacheType
end

function (p::ImplicitRHS)(u,resid)
  du1 = get_du(p.dual_cache, eltype(u))
  p.f(p.t+p.dt,reshape(u,size(du1)),du1)
  vecdu1 = vec(du1)
  @. resid = u - p.C - p.a*vecdu1
end

function initialize!(integrator,
                     cache::Union{GenericImplicitEulerConstantCache,GenericTrapezoidConstantCache})
  cache.uhold[1] = integrator.uprev; cache.C[1] = integrator.uprev
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.t, integrator.uprev)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::GenericImplicitEulerConstantCache, repeat_step=false)
  @unpack t,dt,uprev,u,f = integrator
  @unpack uhold,C,rhs,nl_rhs = cache
  C[1] = uprev

  if integrator.success_iter > 0 && !integrator.u_modified && integrator.alg.extrapolant == :interpolant
    uhold[1] = current_extrapolant(t+dt,integrator)
  elseif integrator.alg.extrapolant == :linear
    uhold[1] = @. uprev + dt*integrator.fsalfirst
  else # :constant
    uhold[1] = uprev
  end

  rhs.t = t
  rhs.dt = dt
  rhs.a = dt
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)
  uhold[1] = nlres[1]
  integrator.fsallast = f(t+dt,uhold[1])
  u = uhold[1]

  if integrator.opts.adaptive && integrator.success_iter > 0
    # local truncation error (LTE) bound by dt^2/2*max|y''(t)|
    # use 2nd divided differences (DD) a la SPICE and Shampine

    # TODO: check numerical stability
    uprev2 = integrator.uprev2
    tprev = integrator.tprev

    dt1 = dt*(t+dt-tprev)
    dt2 = (t-tprev)*(t+dt-tprev)
    c = 7/12 # default correction factor in SPICE (LTE overestimated by DD)
    r = c*dt^2 # by mean value theorem 2nd DD equals y''(s)/2 for some s

    tmp = @. r*abs((u - uprev)/dt1 - (uprev - uprev2)/dt2)
    atmp = calculate_residuals(tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(atmp)
  else
    integrator.EEst = 1
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator,
                     cache::Union{GenericImplicitEulerCache,GenericTrapezoidCache})
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  integrator.f(integrator.t, integrator.uprev, integrator.fsalfirst)

  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::GenericImplicitEulerCache, repeat_step=false)
  @unpack t,dt,uprev,u,f = integrator
  @unpack C,dual_cache,k,nl_rhs,rhs,uhold,tmp,atmp = cache
  copy!(C,uprev)

  if integrator.success_iter > 0 && !integrator.u_modified && integrator.alg.extrapolant == :interpolant
    current_extrapolant!(u,t+dt,integrator)
  elseif integrator.alg.extrapolant == :linear
    @. u = uprev + dt*integrator.fsalfirst
  else
    copy!(u,uprev)
  end

  rhs.t = t
  rhs.dt = dt
  rhs.a = dt
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)
  copy!(uhold,nlres)

  if integrator.opts.adaptive && integrator.success_iter > 0
    # local truncation error (LTE) bound by dt^2/2*max|y''(t)|
    # use 2nd divided differences (DD) a la SPICE and Shampine

    # TODO: check numerical stability
    uprev2 = integrator.uprev2
    tprev = integrator.tprev

    dt1 = dt*(t+dt-tprev)
    dt2 = (t-tprev)*(t+dt-tprev)
    c = 7/12 # default correction factor in SPICE (LTE overestimated by DD)
    r = c*dt^2 # by mean value theorem 2nd DD equals y''(s)/2 for some s

    @. tmp = r*abs((u - uprev)/dt1 - (uprev - uprev2)/dt2)
    calculate_residuals!(atmp, tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(atmp)
  else
    integrator.EEst = 1
  end

  f(t+dt,u,k)
end

function initialize!(integrator, cache::GenericTrapezoidConstantCache)
  cache.uhold[1] = integrator.uprev; cache.C[1] = integrator.uprev
  integrator.fsalfirst = integrator.f(integrator.t, integrator.uprev)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::GenericTrapezoidConstantCache, repeat_step=false)
  @unpack t,dt,uprev,u,f = integrator
  @unpack uhold,C,rhs,nl_rhs = cache
  C[1] = first(uprev) + (dt/2)*first(integrator.fsalfirst)

  if integrator.success_iter > 0 && !integrator.u_modified && integrator.alg.extrapolant == :interpolant
    uhold[1] = current_extrapolant(t+dt,integrator)
  elseif integrator.alg.extrapolant == :linear
    uhold[1] = @. uprev + dt*integrator.fsalfirst
  else # :constant
    uhold[1] = uprev
  end

  rhs.t = t
  rhs.dt = dt
  rhs.a = dt/2
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)
  uhold[1] = nlres[1]
  integrator.fsallast = f(t+dt,uhold[1])
  u = uhold[1]

  if integrator.opts.adaptive
    if integrator.iter > 2
      # local truncation error (LTE) bound by dt^3/12*max|y'''(t)|
      # use 3rd divided differences (DD) a la SPICE and Shampine

      # TODO: check numerical stability
      uprev2 = integrator.uprev2
      tprev = integrator.tprev
      uprev3 = cache.uprev3
      tprev2 = cache.tprev2

      dt1 = dt*(t+dt-tprev)
      dt2 = (t-tprev)*(t+dt-tprev)
      dt3 = (t-tprev)*(t-tprev2)
      dt4 = (tprev-tprev2)*(t-tprev2)
      dt5 = t+dt-tprev2
      c = 7/12 # default correction factor in SPICE (LTE overestimated by DD)
      r = c*dt^3/2 # by mean value theorem 3rd DD equals y'''(s)/6 for some s

      # tmp = @. r*abs(((u - uprev)/dt1 - (uprev - uprev2)/dt2) - ((uprev - uprev2)/dt3 - (uprev2 - uprev3)/dt4)/dt5)
      DD31 = @. (u - uprev)/dt1 - (uprev - uprev2)/dt2
      DD30 = @. (uprev - uprev2)/dt3 - (uprev2 - uprev3)/dt4
      tmp = @. r*abs((DD31 - DD30)/dt5)
      atmp = calculate_residuals(tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol)
      integrator.EEst = integrator.opts.internalnorm(atmp)
      if integrator.EEst <= 1
        cache.uprev3 = uprev2
        cache.tprev2 = tprev
      end
    elseif integrator.success_iter > 0
      integrator.EEst = 1
      cache.uprev3 = integrator.uprev2
      cache.tprev2 = integrator.tprev
    else
      integrator.EEst = 1
    end
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::GenericTrapezoidCache)
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  integrator.f(integrator.t, integrator.uprev, integrator.fsalfirst)
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::GenericTrapezoidCache, repeat_step=false)
  @unpack t,dt,uprev,u,f = integrator
  @unpack C,dual_cache,k,rhs,nl_rhs,uhold,tmp,atmp = cache
  C .= vec(uprev) .+ (dt/2).*vec(integrator.fsalfirst)

  if integrator.success_iter > 0 && !integrator.u_modified && integrator.alg.extrapolant == :interpolant
    current_extrapolant!(u,t+dt,integrator)
  elseif integrator.alg.extrapolant == :linear
    @. u = uprev + dt*integrator.fsalfirst
  else
    copy!(u,uprev)
  end

  # copy!(rhs.fsalfirst,fsalfirst) Implicitly done by pointers: fsalfirst === fsalfirst == rhs.fsalfirst
  rhs.t = t
  rhs.dt = dt
  rhs.a = dt/2
  nlres = integrator.alg.nlsolve(nl_rhs,uhold)
  copy!(uhold,nlres)

  if integrator.opts.adaptive
    if integrator.iter > 2
      # local truncation error (LTE) bound by dt^3/12*max|y'''(t)|
      # use 3rd divided differences (DD) a la SPICE and Shampine

      # TODO: check numerical stability
      uprev2 = integrator.uprev2
      tprev = integrator.tprev
      uprev3 = cache.uprev3
      tprev2 = cache.tprev2

      dt1 = dt*(t+dt-tprev)
      dt2 = (t-tprev)*(t+dt-tprev)
      dt3 = (t-tprev)*(t-tprev2)
      dt4 = (tprev-tprev2)*(t-tprev2)
      dt5 = t+dt-tprev2
      c = 7/12 # default correction factor in SPICE (LTE overestimated by DD)
      r = c*dt^3/2 # by mean value theorem 3rd DD equals y'''(s)/6 for some s

      # @. tmp = r*abs(((u - uprev)/dt1 - (uprev - uprev2)/dt2) - ((uprev - uprev2)/dt3 - (uprev2 - uprev3)/dt4)/dt5)
      @inbounds for i in eachindex(u)
        DD31 = (u[i] - uprev[i])/dt1 - (uprev[i] - uprev2[i])/dt2
        DD30 = (uprev[i] - uprev2[i])/dt3 - (uprev2[i] - uprev3[i])/dt4
        tmp[i] = r*abs((DD31 - DD30)/dt5)
      end
      calculate_residuals!(atmp, tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol)
      integrator.EEst = integrator.opts.internalnorm(atmp)
      if integrator.EEst <= 1
        copy!(cache.uprev3,uprev2)
        cache.tprev2 = tprev
      end
    elseif integrator.success_iter > 0
      integrator.EEst = 1
      copy!(cache.uprev3,integrator.uprev2)
      cache.tprev2 = integrator.tprev
    else
      integrator.EEst = 1
    end
  end

  f(t+dt,u,k)
end
