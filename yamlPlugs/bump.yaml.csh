#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
_output config: &outputConfig
  date: &validDate '${jedi_time_string}'
  stream name: control
geometry:
  nml_file: "namelist.atmosphere_${DATE}"
  streams_file: "streams.atmosphere"
  deallocate non-da fields: true
  bump vunit: "${vertloc_coord_model_space_bump}"  # "height" or "scaleheight"
_input variables: &vars
- temperature
- spechum
- uReconstructZonal
- uReconstructMeridional
- surface_pressure
- qc
- qi
- qr
- qs
- qg
background:
  state variables: *vars
  filename: './mpasin.${mpas_date}.nc'
  date: '${jedi_time_string}'

background error:
  covariance model: SABER

  saber central block:
    saber block name: BUMP_NICAS
    calibration:
      io:
        files prefix: $BE_PREFIX #bumploc_1200km6km

      drivers:
        multivariate strategy: duplicated
        compute nicas: true
        write local nicas: true
        write global nicas: true
        write nicas grids: true
        internal dirac test: true
      model:
        level for 2d variables: last
      sampling:
        computation grid size: 4096
      nicas:
        resolution: 8.0
        explicit length-scales: true
        horizontal length-scale:
          - groups: [common]
            value: ${corrlength_meters}
        vertical length-scale:
          - groups: [common]
            value: ${vertloc_length_model_space}

      output model files:
      - parameter: loc_rh
        file:
          filename: ./loc_rh.\$Y-\$M-\$D_\$h.\$m.\$s.nc
          <<: *outputConfig
      - parameter: loc_rv
        file:
          filename: ./loc_rv.\$Y-\$M-\$D_\$h.\$m.\$s.nc
          <<: *outputConfig
      - parameter: nicas_norm
        file:
          filename: ./nicas_norm.\$Y-\$M-\$D_\$h.\$m.\$s.nc
          <<: *outputConfig
      - parameter: dirac_nicas
        file:
          filename: ./dirac_nicas.\$Y-\$M-\$D_\$h.\$m.\$s.nc
          <<: *outputConfig
EOF
