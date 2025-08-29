#!/bin/csh
cd $2
set output_fname = $1 # file that is output (added to, given 'cat >>' )
cat >> $output_fname << EOF
obs localizations:
- localization method: Horizontal Gaspari-Cohn
  lengthscale: $hloc
  max nobs: 1000
EOF

if ( $enkf_type != GETKF ) then
   cat >> $output_fname << EOF2
- localization method: Vertical localization
  vertical lengthscale: $vloc
  ioda vertical coordinate: $vloc_unit #pressure or height
  ioda vertical coordinate group: MetaData
  apply log transformation: $applyLogTransformation #true
  localization function: Gaspari Cohn
EOF2
endif
