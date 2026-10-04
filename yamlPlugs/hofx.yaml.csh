#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
_multi iteration filter: &multiIterationFilter
  apply at iterations: $iterations_list #0,1,2,3,4,5
time window:
  begin: '${time_window_begin}'
  length: PT${CYCLE_PERIOD}M #PT6H
geometry:
  nml_file: "./namelist.atmosphere_${DATE}"
  streams_file: "./streams.atmosphere"
  deallocate non-da fields: true
state:
   #state variables: [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal,theta,rho,u,w,qv,pressure,landmask,observable_domain_mask,xice,snowc,skintemp,ivgtyp,isltyp,snowh,vegfra,u10,v10,lai,smois,tslb,pressure_p,qc,qi,qg,qr,qs,cldfrac] #refl10cm,qh,nr,ns,ng,nh,volg,volh]
  state variables: [spechum,surface_pressure,temperature,uReconstructMeridional,uReconstructZonal,theta,rho,u,w,qv,pressure,landmask,observable_domain_mask,xice,snowc,skintemp,ivgtyp,isltyp,snowh,vegfra,u10,v10,t2m,q2,lai,smois,tslb,pressure_p,qc,qi,qg,qr,qs,cldfrac,refl10cm,ni,nc,nr,ns,ng,smlf,gmlf] # after refl10cm needed for PPRO
  filename: "./bg.${mpas_date}.nc"
  date: '${jedi_time_string}'
EOF
