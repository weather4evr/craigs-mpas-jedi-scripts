#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
- obs space:
    <<: *ObsSpace
    name: Sfc_uvtq
    _obsdatain: &ObsDataIn
      engine:
        type: H5File
        obsfile: $inputDataFile
    _obsdataout: &ObsDataOut
      engine:
        type: H5File
        obsfile: $outputDataFile
    obsdatain: *ObsDataIn
    obsdataout: *ObsDataOut
    simulated variables: &simulatedVars [airTemperatureAt2M, specificHumidity, windEastward, windNorthward]
  obs error: *ObsErrorDiagonal
  obs operator:
    name: Composite
    components:
    - name: SfcCorrected
      correction scheme to use: GSL
      geovar_sfc_geomz: surface_geopotential_height
      geovar_geomz: geopotential_height

      gsl parameters:
        temperature lapse rate option: Local
        temperature local lapse rate level: 10
        temperature lapse rate threshold: true
        min threshold: 0.5
        max threshold: 10.0
      variables:
      - name: airTemperatureAt2M

    - name: SfcCorrected
      correction scheme to use: GSL
      geovar_sfc_geomz: surface_geopotential_height
      geovar_geomz: geopotential_height
      variables:
      - name: specificHumidity

    - name: SfcCorrected
      correction scheme to use: GSL
      geovar_sfc_geomz: surface_geopotential_height
      geovar_geomz: geopotential_height
      variables:
      - name: windNorthward
      - name: windEastward
  linear obs operator:
    name: Identity
  get values:
    <<: *GetValues
  obs filters:
  - filter: PreQC
    minvalue: 0
    maxvalue: 0
    filter variables:
    - name: airTemperatureAt2M
    - name: specificHumidity
    - name: windEastward
    - name: windNorthward

  - filter: Difference Check
    reference: MetaData/stationElevation
    value: GeoVaLs/surface_altitude
    threshold: 200.0

  # Assign observation errors
  - filter: Perform Action
    filter variables:
    - name: airTemperatureAt2M
    action:
      name: assign error
      error parameter: 1.0
  - filter: Perform Action
    filter variables:
    - name: windEastward
    - name: windNorthward
    action:
      name: assign error
      error parameter: 1.0

  # Bounds check
  - filter: Bounds Check
    filter variables:
    - name: airTemperatureAt2M
    minvalue: 200.0
    maxvalue: 400.0

  - filter: Bounds Check
    filter variables:
    - name: specificHumidity
    minvalue: 0.0
    maxvalue: 1.0

  - filter: Bounds Check
    filter variables:
    - name: windEastward
    - name: windNorthward
    minvalue: -50.0
    maxvalue: 50.0

  # Regional domain check
  - filter: Bounds Check
    filter variables:
    - name: airTemperatureAt2M
    - name: specificHumidity
    - name: windEastward
    - name: windNorthward
    test variables:
    - name: GeoVaLs/observable_domain_mask
    flag all filter variables if any test variable is out of bounds: true
    minvalue: 0.0
    maxvalue: 0.1
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
