#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
_iteration: &iterationConfig
  geometry:
    nml_file: "./namelist.atmosphere_${DATE}_ens"
    streams_file: "./streams.atmosphere_ens"
    deallocate non-da fields: true
    interpolation type: unstructured
  gradient norm reduction: 1e-2
  obs perturbations: false
  #Several 'online diagnostics' are useful for checking the H correctness and Hessian symmetry
#  online diagnostics:
#    tlm taylor test: true
#    tlm approx test: true
#    adj tlm test: true
#    adj obs test: true
#    online adj test: true
_member: &memberConfig
  date: &analysisDate '${jedi_time_string}'
 #state variables: &incvars [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal,qc,qi,qg,qr,qs]
  state variables: &incvars [water_vapor_mixing_ratio_wrt_moist_air,air_pressure_at_surface,air_temperature,northward_wind,eastward_wind]
  stream name: ensemble
_multi iteration filter: &multiIterationFilter
  apply at iterations: $iterations_list #0,1,2,3,4,5
output:
  filename: "./analysis.${mpas_date}.nc"
  stream name: analysis
variational:
  minimizer:
    algorithm: DRPCG
  iterations:
  - <<: *iterationConfig
    diagnostics:
      departures: depbg_iter1
    ninner: ${num_inner_loops}
final:
  diagnostics:
    departures: depan
cost function:
  cost type: 3D-Var
  time window:
    begin: '${time_window_begin}'
    length: PT${CYCLE_PERIOD}M #PT6H
  jb evaluation: false
  geometry:
    nml_file: "./namelist.atmosphere_${DATE}_deterministic"
    streams_file: "./streams.atmosphere_deterministic"
    deallocate non-da fields: true
    interpolation type: unstructured
  analysis variables: *incvars
  background:
   #state variables: [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal,theta,rho,u,w,qv,pressure,landmask,observable_domain_mask,xice,snowc,skintemp,ivgtyp,isltyp,snowh,vegfra,u10,v10,lai,smois,tslb,pressure_p,qc,qi,qg,qr,qs,cldfrac] #refl10cm,qh,nr,ns,ng,nh,volg,volh]
    state variables: [water_vapor_mixing_ratio_wrt_moist_air,air_pressure_at_surface,air_temperature,northward_wind,eastward_wind,air_potential_temperature,dry_air_density,u,water_vapor_mixing_ratio_wrt_dry_air,air_pressure,landmask,seaice_fraction,snowc,skin_temperature_at_surface,ivgtyp,isltyp,snowh,vegetation_area_fraction,air_temperature_at_2m,water_vapor_mixing_ratio_wrt_moist_air_at_2m,eastward_wind_at_10m,northward_wind_at_10m,lai,smois,tslb,pressure_p]
    filename: "./bg.${mpas_date}.nc"
    date: *analysisDate
  background error:
    covariance model: hybrid
    components:
EOF

if ( `echo "$static_be_weight > 0" | bc` == 1 ) then
    cat >> $output_fname << EOF1
    - weight:
        value: $static_be_weight
      covariance:
        covariance model: SABER
        no outer loop update: true
        saber central block:
          saber block name: BUMP_NICAS
          active variables: &ctlvars [air_horizontal_streamfunction,air_horizontal_velocity_potential,air_temperature,water_vapor_mixing_ratio_wrt_moist_air,air_pressure_at_surface]
          read:
            io:
              data directory: ./B_Matrix/nicas/
              files prefix: $STATIC_BE_PREFIX
            drivers:
              multivariate strategy: univariate
              read local nicas: true
            grids:
              - model:
                  variables: [air_horizontal_streamfunction,air_horizontal_velocity_potential,air_temperature,water_vapor_mixing_ratio_wrt_moist_air]
              - model:
                  variables: [air_pressure_at_surface]
                  nearest 3d level: bottom
        saber outer blocks:
        - saber block name: StdDev
          read:
            model file:
              filename: ./B_Matrix/stddev/mpas.stddev.nc
              date: *analysisDate
              stream name: control
        - saber block name: BUMP_VerticalBalance
          read:
            io:
              data directory: ./B_Matrix/vbal/
              files prefix: $STATIC_BE_PREFIX
            drivers:
              read local sampling: true
              read vertical balance: true
            model:
              nearest 3d level: bottom
            vertical balance:
              vbal:
              - balanced variable: air_horizontal_velocity_potential
                unbalanced variable: air_horizontal_streamfunction
                diagonal regression: true
              - balanced variable: air_temperature
                unbalanced variable: air_horizontal_streamfunction
              - balanced variable: air_pressure_at_surface
                unbalanced variable: air_horizontal_streamfunction
        linear variable change:
          linear variable change name: Control2Analysis
          input variables: *ctlvars
          output variables: *incvars
EOF1
endif

if ( `echo "$ensemble_be_weight > 0" | bc` == 1 ) then
    cat >> $output_fname << EOF2
    - weight:
        value: $ensemble_be_weight
      covariance:
        covariance model: ensemble
        localization:
          localization method: SABER
          saber central block:
            saber block name: BUMP_NICAS
            active variables: *incvars
            read:
              io:
                data directory: ./bump_files
                files prefix: $BE_PREFIX_ENS # bumploc_1200.0km_6.0km
              drivers:
                multivariate strategy: duplicated
                read local nicas: true
              model:
                level for 2d variables: last
    #         verbosity: main
        members from template:
          template:
            <<: *memberConfig
            filename: ./mpas_en%iMember%.nc
            #filename: /glade/p/mmm/parc/liuz/pandac_common/30km_EnsFC/2019050318/%iMember%/EnsForCov.2019-05-04_00.00.00.nc
          pattern: %iMember%
          start: 1
          zero padding: 3
          nmembers: $ENS_SIZE
EOF2
endif

