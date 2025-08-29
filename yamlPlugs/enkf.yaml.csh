#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
_member: &memberConfig
  date: &analysisDate ${jedi_time_string}
  state variables: [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal,theta,rho,u,w,qv,pressure,landmask,observable_domain_mask,xice,snowc,skintemp,ivgtyp,isltyp,snowh,vegfra,u10,v10,lai,smois,tslb,pressure_p,qc,qi,qg,qr,qs,cldfrac,refl10cm] #refl10cm,qh,nr,ns,ng,nh,volg,volh]
  stream name: background

_multi iteration filter: &multiIterationFilter
  _blank: null

_as observer: &asObserver
  run as observer only: true
  update obs config with geometry info: false
  save single member for observer: $SaveSingleMember
  single memeber number for save: $SingleMemberNumber
# save prior mean: false

_as solver: &asSolver
  read HX from disk: true
  #do test prints: false
  do posterior observer: false
  save posterior ensemble: true
  save posterior mean: true

_letkf geometry: &3DLETKFGeometry
  iterator dimension: 3

_letkf geometry: &2DLETKFGeometry
  iterator dimension: 2

_lgetkf geometry: &3DGETKFGeometry
  iterator dimension: 2

geometry:
  <<: *3D${enkf_type}Geometry
  nml_file: "./namelist.atmosphere_${DATE}"
  streams_file: "./streams.atmosphere_ens"
  deallocate non-da fields: true
  #interpolation type: unstructured # no Increment/State interp in enkf

time window:
  begin: ${time_window_begin}
  length: PT${CYCLE_PERIOD}M #PT1H

background:
  members from template:
    template:
      <<: *memberConfig
      filename: ./mpas_en%iMember%.nc
    pattern: %iMember%
    start: 1
    zero padding: 3
    nmembers: $ENS_SIZE

increment variables: [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal,qc,qi,qg,qr,qs]

driver: *${letkf_stage} #*asObserver or *asSolver

local ensemble DA:
  solver: $enkf_type # LETKF
  use linear observer: False
  vertical localization: # only used by GETKF solver
    fraction of retained variance: 0.95
    lengthscale: $vertloc_length_model_space # meters if height 4000.0
    lengthscale units: $vertloc_coord_model_space #height
  inflation:
    rtps: $rtps_inflation_factor
    rtpp: $rtpp_inflation_factor
    mult: 1.0
output:
  filename: ./analysis.\$Y-\$M-\$D_\$h.\$m.\$s_en%{member}%.nc
  stream name: analysis

#output mean prior:
#  filename: ./ens_mean_prior.\$Y-\$M-\$D_\$h.\$m.\$s.nc
#  stream name: analysis
EOF
