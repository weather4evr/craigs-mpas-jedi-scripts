#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: aircraft
    _obsdatain: &ObsDataIn
      engine:
        type: H5File
        obsfile: $inputDataFile
    _obsdataout: &ObsDataOut
      engine:
        type: H5File
        obsfile: $outputDataFile
    obsdatain:
      <<: *ObsDataIn
    obsdataout: *ObsDataOut
    simulated variables: &simulatedVars [airTemperature, windEastward, windNorthward, specificHumidity]
  obs error: *ObsErrorDiagonal
  obs operator:
    name: VertInterp
    observation alias file: obsop_name_map.yaml
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 3
  - filter: Gaussian Thinning
    horizontal_mesh: $horiz_thin
    vertical_mesh: $vert_thin
  - filter: Background Check
    threshold: $bgchk_thresh #5.0
    <<: *multiIterationFilter
 #- *reduceObsSpace
EOF

if ( $assimOrEval == eval ) then
  cat >> $output_fname << EOF2
  - filter: Perform Action
    filter variables: *simulatedVars # [airTemperature, windEastward, windNorthward, specificHumidity]
    action:
      name: passivate
EOF2

endif
