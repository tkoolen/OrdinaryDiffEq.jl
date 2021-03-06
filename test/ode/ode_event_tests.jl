using OrdinaryDiffEq, RecursiveArrayTools, Base.Test, StaticArrays


f = function (t,u)
  - u + sin(-t)
end


prob = ODEProblem(f,1.0,(0.0,-10.0))

condition= function (t,u,integrator) # Event when event_f(t,u,k) == 0
  - t - 2.95
end

affect! = function (integrator)
  integrator.u = integrator.u + 2
end

callback = ContinuousCallback(condition,affect!)

sol = solve(prob,Tsit5(),callback=callback)

f = function (t,u,du)
  du[1] = - u[1] + sin(t)
end


prob = ODEProblem(f,[1.0],(0.0,10.0))

condtion= function (t,u,integrator) # Event when event_f(t,u,k) == 0
  t - 2.95
end

affect! = function (integrator)
  integrator.u = integrator.u + 2
end

callback = ContinuousCallback(condtion,affect!)

sol = solve(prob,Tsit5(),callback=callback,abstol=1e-8,reltol=1e-6)

#=
f = @ode_def BallBounce begin
  dy =  v
  dv = -g
end g=9.81
=#

f = function (t,u,du)
  du[1] = u[2]
  du[2] = -9.81
end

condtion= function (t,u,integrator) # Event when event_f(t,u,k) == 0
  u[1]
end

affect! = nothing
affect_neg! = function (integrator)
  integrator.u[2] = -integrator.u[2]
end

callback = ContinuousCallback(condtion,affect!,affect_neg!,interp_points=100)

u0 = [50.0,0.0]
tspan = (0.0,15.0)
prob = ODEProblem(f,u0,tspan)


sol = solve(prob,Tsit5(),callback=callback,adaptive=false,dt=1/4)

condtion_single = function (t,u,integrator) # Event when event_f(t,u,k) == 0
  u
end

affect! = nothing
affect_neg! = function (integrator)
  integrator.u[2] = -integrator.u[2]
end

callback_single = ContinuousCallback(condtion_single,affect!,affect_neg!,interp_points=100,idxs=1)

u0 = [50.0,0.0]
tspan = (0.0,15.0)
prob = ODEProblem(f,u0,tspan)

sol = solve(prob,Tsit5(),callback=callback_single,adaptive=false,dt=1/4)

#plot(sol,denseplot=true)

sol = solve(prob,Vern6(),callback=callback)
#plot(sol,denseplot=true)
sol = solve(prob,BS3(),callback=callback)

sol33 = solve(prob,Vern7(),callback=callback)

bounced = ODEProblem(f,sol[8],(0.0,1.0))
sol_bounced = solve(bounced,Vern6(),callback=callback,dt=sol.t[9]-sol.t[8])
#plot(sol_bounced,denseplot=true)
sol_bounced(0.04) # Complete density
@test maximum(maximum.(map((i)->sol.k[9][i]-sol_bounced.k[2][i],1:length(sol.k[9])))) == 0


sol2= solve(prob,Vern6(),callback=callback,adaptive=false,dt=1/2^4)
#plot(sol2)

sol2= solve(prob,Vern6())

sol3= solve(prob,Vern6(),saveat=[.5])

## Saving callback

condtion = function (t,u,integrator)
  true
end
affect! = function (integrator) end

save_positions = (true,false)
saving_callback = DiscreteCallback(condtion,affect!,save_positions=save_positions)

sol4 = solve(prob,Tsit5(),callback=saving_callback)

@test sol2(3) ≈ sol(3)

affect! = function (integrator)
  u_modified!(integrator,false)
end
saving_callback2 = DiscreteCallback(condtion,affect!,save_positions=save_positions)
sol4 = solve(prob,Tsit5(),callback=saving_callback2)

cbs = CallbackSet(saving_callback,saving_callback2)
sol4_extra = solve(prob,Tsit5(),callback=cbs)

@test length(sol4_extra) == 2length(sol4) - 1

condtion= function (t,u,integrator)
  u[1]
end

affect! = function (integrator)
  terminate!(integrator)
end

terminate_callback = ContinuousCallback(condtion,affect!)

tspan2 = (0.0,Inf)
prob2 = ODEProblem(f,u0,tspan2)

sol5 = solve(prob2,Tsit5(),callback=terminate_callback)

@test sol5[end][1] < 3e-12
@test sol5.t[end] ≈ sqrt(50*2/9.81)

affect2! = function (integrator)
  if integrator.t >= 3.5
    terminate!(integrator)
  else
    integrator.u[2] = -integrator.u[2]
  end
end
terminate_callback2 = ContinuousCallback(condtion,nothing,affect2!,interp_points=100)


sol5 = solve(prob2,Vern7(),callback=terminate_callback2)

@test sol5[end][1] < 1.3e-12
@test sol5.t[end] ≈ 3*sqrt(50*2/9.81)

condtion= function (t,u,integrator) # Event when event_f(t,u,k) == 0
  t-4
end

affect! = function (integrator)
  terminate!(integrator)
end

terminate_callback3 = ContinuousCallback(condtion,affect!,interp_points=100)

bounce_then_exit = CallbackSet(callback,terminate_callback3)

sol6 = solve(prob2,Vern7(),callback=bounce_then_exit)

@test sol6[end][1] > 0
@test sol6.t[end] ≈ 4


# More ODE event tests, cf. #201, #199, #198, #197
function test_callback_inplace(alg)
    f = (t, u, du) -> @. du = u
    cb = ContinuousCallback((t,u,int) -> u[1] - exp(1), terminate!)
    prob = ODEProblem(f, [1.0], (0.0, 2.0), callback=cb)
    sol = solve(prob, alg)
    sol.u[end][1] ≈ exp(1)
end

function test_callback_outofplace(alg)
    f = (t, u) -> copy(u)
    cb = ContinuousCallback((t,u,int) -> u[1] - exp(1), terminate!)
    prob = ODEProblem(f, [1.0], (0.0, 2.0), callback=cb)
    sol = solve(prob, alg)
    sol.u[end][1] ≈ exp(1)
end

function test_callback_scalar(alg)
    f = (t, u) -> u
    cb = ContinuousCallback((t,u,int) -> u - exp(1), terminate!)
    prob = ODEProblem(f, 1.0, (0.0, 2.0), callback=cb)
    sol = solve(prob, alg)
    sol.u[end] ≈ exp(1)
end

function test_callback_svector(alg)
    f = (t, u) -> u
    cb = ContinuousCallback((t,u,int) -> u[1] - exp(1), terminate!)
    prob = ODEProblem(f, SVector(1.0), (0.0, 2.0), callback=cb)
    sol = solve(prob, alg)
    sol.u[end][1] ≈ exp(1)
end

function test_callback_mvector(alg)
    f = (t, u) -> copy(u)
    cb = ContinuousCallback((t,u,int) -> u[1] - exp(1), terminate!)
    prob = ODEProblem(f, MVector(1.0), (0.0, 2.0), callback=cb)
    sol = solve(prob, alg)
    sol.u[end][1] ≈ exp(1)
end

@test test_callback_inplace(BS3())
@test test_callback_inplace(BS5())
@test test_callback_inplace(SSPRK432())
@test test_callback_inplace(SSPRK932())
@test test_callback_inplace(OwrenZen3())
@test test_callback_inplace(OwrenZen4())
@test test_callback_inplace(OwrenZen5())
@test test_callback_inplace(DP5())
@test test_callback_inplace(DP8())
@test test_callback_inplace(Feagin10())
@test test_callback_inplace(Feagin12())
@test test_callback_inplace(Feagin14())
@test test_callback_inplace(TanYam7())
@test test_callback_inplace(Tsit5())
@test test_callback_inplace(TsitPap8())
@test test_callback_inplace(Vern6())
@test test_callback_inplace(Vern7())
@test test_callback_inplace(Vern8())
@test test_callback_inplace(Vern9())
@test test_callback_inplace(Rosenbrock23())
@test test_callback_inplace(Rosenbrock32())

@test test_callback_outofplace(BS3())
@test test_callback_outofplace(BS5())
@test test_callback_outofplace(SSPRK432())
@test test_callback_outofplace(SSPRK932())
@test test_callback_outofplace(OwrenZen3())
@test test_callback_outofplace(OwrenZen4())
@test test_callback_outofplace(OwrenZen5())
@test test_callback_outofplace(DP5())
@test test_callback_outofplace(DP8())
@test test_callback_outofplace(Feagin10())
@test test_callback_outofplace(Feagin12())
@test test_callback_outofplace(Feagin14())
@test test_callback_outofplace(TanYam7())
@test test_callback_outofplace(Tsit5())
@test test_callback_outofplace(TsitPap8())
@test test_callback_outofplace(Vern6())
@test test_callback_outofplace(Vern7())
@test test_callback_outofplace(Vern8())
@test test_callback_outofplace(Vern9())
@test test_callback_outofplace(Rosenbrock23())
@test test_callback_outofplace(Rosenbrock32())

@test test_callback_scalar(BS3())
@test test_callback_scalar(BS5())
@test test_callback_scalar(SSPRK432())
@test test_callback_scalar(SSPRK932())
@test test_callback_scalar(OwrenZen3())
@test test_callback_scalar(OwrenZen4())
@test test_callback_scalar(OwrenZen5())
@test test_callback_scalar(DP5())
@test test_callback_scalar(DP8())
@test test_callback_scalar(Feagin10())
@test test_callback_scalar(Feagin12())
@test test_callback_scalar(Feagin14())
@test test_callback_scalar(TanYam7())
@test test_callback_scalar(Tsit5())
@test test_callback_scalar(TsitPap8())
@test test_callback_scalar(Vern6())
@test test_callback_scalar(Vern7())
@test test_callback_scalar(Vern8())
@test test_callback_scalar(Vern9())
@test test_callback_scalar(Rosenbrock23())
@test test_callback_scalar(Rosenbrock32())

@test test_callback_svector(BS3())
@test test_callback_svector(BS5())
@test test_callback_svector(SSPRK432())
@test test_callback_svector(SSPRK932())
@test test_callback_svector(OwrenZen3())
@test test_callback_svector(OwrenZen4())
@test test_callback_svector(OwrenZen5())
@test test_callback_svector(DP5())
@test test_callback_svector(DP8())
@test test_callback_svector(Feagin10())
@test test_callback_svector(Feagin12())
@test test_callback_svector(Feagin14())
@test test_callback_svector(TanYam7())
@test test_callback_svector(Tsit5())
@test test_callback_svector(TsitPap8())
@test test_callback_svector(Vern6())
@test test_callback_svector(Vern7())
@test test_callback_svector(Vern8())
@test test_callback_svector(Vern9())
@test test_callback_svector(Rosenbrock23())
@test test_callback_svector(Rosenbrock32())

@test test_callback_mvector(BS3())
@test test_callback_mvector(BS5())
@test test_callback_mvector(SSPRK432())
@test test_callback_mvector(SSPRK932())
@test test_callback_mvector(OwrenZen3())
@test test_callback_mvector(OwrenZen4())
@test test_callback_mvector(OwrenZen5())
@test test_callback_mvector(DP5())
@test test_callback_mvector(DP8())
@test test_callback_mvector(Feagin10())
@test test_callback_mvector(Feagin12())
@test test_callback_mvector(Feagin14())
@test test_callback_mvector(TanYam7())
@test test_callback_mvector(Tsit5())
@test test_callback_mvector(TsitPap8())
@test test_callback_mvector(Vern6())
@test test_callback_mvector(Vern7())
@test test_callback_mvector(Vern8())
@test test_callback_mvector(Vern9())
@test test_callback_mvector(Rosenbrock23())
@test test_callback_mvector(Rosenbrock32())
