function [soilvar] = soil_temperature (physcon, soilvar, tsurf, dt)
% Use an implicit formulation with the surface boundary condition specified
% as the surface temperature to solve for soil temperatures at time n+1.
%
% Calculate soil temperatures as:
%
%      dT   d     dT
%   cv -- = -- (k --)
%      dt   dz    dz
%
% where: T = temperature (K)
%        t = time (s)
%        z = depth (m)
%        cv = volumetric heat capacity (J/m3/K)
%        k = thermal conductivity (W/m/K)
%
% Set up a tridiagonal system of equations to solve for T at time n+1,
% where the temperature equation for layer i is
%
%   d_i = a_i [T_i-1] n+1 + b_i [T_i] n+1 + c_i [T_i+1] n+1
%
% For soil layers undergoing phase change, set T_i = Tf (freezing) and use
% excess energy to freeze or melt ice:
%
%   Hf_i = (Tf - [T_i] n+1) * cv_i * dz_i / dt
%
% During the phase change, the unfrozen and frozen soil water
% (h2osoi_liq, h2osoi_ice) are adjusted.
%
% Or alternatively, use the apparent heat capacity method to
% account for phase change. In this approach, h2osoi_liq
% and h2osoi_ice are not calculated.
%
% ------------------------------------------------------
% Input
%   tsurf                   ! Surface temperature (K)
%   dt                      ! Time step (s)
%   soilvar.method          ! Use excess heat or apparent heat capacity for phase change
%   soilvar.solution        ! `implicit` or `Crank-Nicolson`
%   soilvar.n            ! Number of soil layers
%   soilvar.z               ! Soil depth (m)
%   soilvar.z_plus_onehalf  ! Soil depth (m) at i+1/2 interface between layers i and i+1
%   soilvar.dz              ! Soil layer thickness (m)
%   soilvar.dz_plus_onehalf ! Thickness (m) between between i and i+1
%   soilvar.tk              ! Thermal conductivity (W/m/K)
%   soilvar.cv              ! Heat capacity (J/m3/K)
%
% Input/output
%   soilvar.tsoi            ! Soil temperature (K)
%   soilvar.h2osoi_liq      ! Unfrozen water, liquid (kg H2O/m2)
%   soilvar.h2osoi_ice      ! Frozen water, ice (kg H2O/m2)
%
% Output
%   soilvar.gsoi            ! Energy flux into soil (W/m2)
%   soilvar.hfsoi           ! Soil phase change energy flux (W/m2)
% ------------------------------------------------------

% solution = 'Crank-Nicolson'; % Use Crank-Nicolson solution
% solution = 'implicit';       % Use implicit solution
solution = soilvar.solution;

% --- Save current soil temperature for energy conservation check
tsoi0 = soilvar.tsoi;

n = soilvar.nsoi;

z = soilvar.z;
z_plus_onehalf = soilvar.z_plus_onehalf;
dz_plus_onehalf = soilvar.dz_plus_onehalf;
tk = soilvar.tk;

% --- Thermal conductivity at interface (W/m/K)
tk_plus_onehalf = zeros(1, n-1);
for i = 1:n-1
  tk_plus_onehalf(i) = tk(i) * tk(i+1) * (z(i)-z(i+1)) / ...
    (tk(i)*(z_plus_onehalf(i)-z(i+1)) + tk(i+1)*(z(i) - z_plus_onehalf(i))); % Eq. 5.16
end

% --- Set up tridiagonal matrix
% Top soil layer with tsurf as boundary condition
a = zeros(n, 1);
b = zeros(n, 1);
c = zeros(n, 1);
d = zeros(n, 1);

if solution == "implicit"  
  for i = 1:n
    m = soilvar.cv(i) * soilvar.dz(i) / dt;
    if i == 1
      a(i) = 0;
      c(i) = -tk_plus_onehalf(i) / dz_plus_onehalf(i);
      b(i) = m - c(i) + tk(i) / (0 - z(i));
      d(i) = m * tsoi0(i) + tk(i) / (0 - z(i)) * tsurf;
      
    elseif i < n
      a(i) = -tk_plus_onehalf(i-1) / dz_plus_onehalf(i-1);
      c(i) = -tk_plus_onehalf(i) / dz_plus_onehalf(i);
      b(i) = m - a(i) - c(i);
      d(i) = m * tsoi0(i);
      
    elseif i == n
      a(i) = -tk_plus_onehalf(i-1) / dz_plus_onehalf(i-1);
      c(i) = 0;
      b(i) = m - a(i);
      d(i) = m * tsoi0(i);
    end
  end
  
elseif solution == "Crank-Nicolson"
  % --- Heat flux at time n (W/m2)
  f = zeros(1, n);
  for i = 1:n-1
    f(i) = -tk_plus_onehalf(i) * (tsoi0(i) - tsoi0(i+1)) / dz_plus_onehalf(i);
  end
  % f(soilvar.n) = 0;
  for i = 1:n
    m = soilvar.cv(i) * soilvar.dz(i) / dt;
    if i == 1
      a(i) = 0;
      c(i) = -0.5 * tk_plus_onehalf(i) / dz_plus_onehalf(i);
      b(i) = m - c(i) + soilvar.tk(i) / (0 - soilvar.z(i));
      d(i) = m * tsoi0(i) + 0.5 * f(i) + soilvar.tk(i) / (0 - soilvar.z(i)) * tsurf;
      
    elseif i < n
      a(i) = -0.5 * tk_plus_onehalf(i-1) / dz_plus_onehalf(i-1);
      c(i) = -0.5 * tk_plus_onehalf(i) / dz_plus_onehalf(i);
      b(i) = m - a(i) - c(i);
      d(i) = m * tsoi0(i) + 0.5 * (f(i) - f(i-1));
      
    elseif i == n
      a(i) = -0.5 * tk_plus_onehalf(i-1) / dz_plus_onehalf(i-1);
      c(i) = 0;
      b(i) = m - a(i);
      d(i) = m * tsoi0(i) - 0.5 * f(i-1);
    end
  end
  
end

% --- Solve for soil temperature
soilvar.tsoi = tridiagonal_solver (a, b, c, d, n);

% --- Derive energy flux into soil (W/m2)
soilvar.gsoi = soilvar.tk(1) * (tsurf - soilvar.tsoi(1)) / (0 - soilvar.z(1));

% --- Phase change for soil layers undergoing freezing of thawing
switch soilvar.method
  case 'apparent-heat-capacity'
    % No explicit phase change energy flux. This is included in the heat capacity.
    soilvar.hfsoi = 0;
    
  case 'excess-heat'
    % Adjust temperatures for phase change. Freeze or melt ice using energy
    % excess or deficit needed to change temperature to the freezing point.
    % The variable hfsoi is returned as the energy flux from phase change (W/m2).
    [soilvar] = phase_change (physcon, soilvar, dt);
end

% --- Check for energy conservation
% Sum change in energy (W/m2)
edif = 0;
for i = 1:n
  edif = edif + soilvar.cv(i) * soilvar.dz(i) * (soilvar.tsoi(i) - tsoi0(i)) / dt;
end

% Error check
err = edif - soilvar.gsoi - soilvar.hfsoi;
if (abs(err) > 1e-03)
  error ('Soil temperature energy conservation error')
end
