#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: Refl10cm
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
    simulated variables: &simulatedVars [equivalentReflectivityFactor]
  obs error: *ObsErrorDiagonal
##<<: *heightAndHorizObsLocCloud
  obs operator:
#   name: VertInterp
#   observation vertical coordinate: height
#   vertical coordinate: geometric_height
#   interpolation method: linear
    name: PPRO
  options: # For PPRO-not need for VertInterp
  # microphysics option: tcwa2
    var_cloud_mixing_ratio: mixing_ratio_of_cloud_liquid_water
    var_ice_mixing_ratio: cloud_ice
    var_ice_number_concentration: ice_number_concentration
    var_snow_melted_fraction: melted_fraction_of_snow
    var_graupel_melted_fraction: melted_fraction_of_graupel
    observation vertical coordinate: height
    vertical coordinate: geometric_height
    interpolation method: linear
    #observation alias file: obsop_name_map.yaml

  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    maxvalue: 3
  - filter: Bounds Check
    filter variables:
    - name: equivalentReflectivityFactor
    test variables:
    - name: GeoVaLs/observable_domain_mask
    flag all filter variables if any test variable is out of bounds: true
    minvalue: 0.0
    maxvalue: 0.1

  - filter: Perform Action
    filter variables:
    - name: equivalentReflectivityFactor
    action:
      name: assign error
      error parameter: 1.5

  - filter: Bounds Check
    filter variables:
    - name: equivalentReflectivityFactor
    maxvalue: 75.0
    minvalue: -15.0

  - filter: Background Check # uses the obs error you assigned earlier
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

