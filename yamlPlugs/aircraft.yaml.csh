#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: aircraft
    _obsdatain:
      engine:
        type: H5File
        obsfile: $inputDataFile #./aircraft_obs_${DATE}.h5
    _obsdataout:
      engine:
        type: H5File
        obsfile: $outputDataFile #Data/obsout_omb_aircraft.h5
    obsdatain:
      <<: *ObsDataIn
    obsdataout: *ObsDataOut
    simulated variables: [air_temperature, eastward_wind, northward_wind, specific_humidity]
  obs error: *ObsErrorDiagonal
  obs operator:
    name: VertInterp
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 0
  - filter: Gaussian Thinning
    horizontal_mesh: $horiz_thin
    vertical_mesh: $vert_thin
  - filter: Background Check
    threshold: $bgchk_thresh #5.0
    <<: *multiIterationFilter
  - *reduceObsSpace
EOF
