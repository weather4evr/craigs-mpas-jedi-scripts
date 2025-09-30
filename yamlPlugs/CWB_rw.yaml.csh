#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: RadarRW
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
    simulated variables: &simulatedVars [radialVelocity]
  obs error: *ObsErrorDiagonal
  obs operator:
    name: RadarRadialVelocity
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 3
  - filter: Bounds Check
    filter variables:
    - name: radialVelocity
    test variables:
    - name: GeoVaLs/observable_domain_mask
    flag all filter variables if any test variable is out of bounds: true
    minvalue: 0.0
    maxvalue: 0.1
  - filter: Perform Action
    filter variables:
    - name: radialVelocity
    action:
      name: assign error
      error parameter: 1.5
#  - filter: Thinning
#    amount: 0.6 # fraction to be thinned
#    random seed: 2022062406
  - filter: Background Check
    threshold: $bgchk_thresh #5.0
    <<: *multiIterationFilter
  - *reduceObsSpace
EOF

if ( $assimOrEval == eval ) then
  cat >> $output_fname << EOF2
  - filter: Perform Action
    filter variables: *simulatedVars # [airTemperature, windEastward, windNorthward, specificHumidity]
    action:
      name: passivate
EOF2

endif

