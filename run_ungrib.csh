#!/bin/csh

# -------------------------------------------------
# This script runs UNGRIB, which is a serial code.
# -------------------------------------------------

set DATE = $DATE # from driver.csh; ccyymmddhhnn (e.g., 202305231200)
set START_DATE_WRF = `${TOOL_DIR}/da_advance_time.exe $DATE 0 -w`
set sdate = `${TOOL_DIR}/da_advance_time.exe $DATE 0 -f ccyy-mm-dd_hh`
set yyyymmddhh = `echo "$DATE" | cut -c 1-10`

if ( $RUN_STAGE == deterministic ) then
   set output_dir = ${UNGRIB_OUTPUT_DIR_DETERMINISTIC}/${DATE}
   set VTABLE_TYPE_MODEL = $EXTERNAL_ICS_DETERMINISTIC # From driver.csh
else if ( $RUN_STAGE == ensemble ) then
   set mem = $1 # input
   set output_dir = ${UNGRIB_OUTPUT_DIR_ENS}/${DATE}/ens_${mem}
   set VTABLE_TYPE_MODEL = $EXTERNAL_ICS_ENS # From driver.csh
else
   echo "RUN_STAGE = $RUN_STAGE is invalid.  Either (deterministic,ensemble). Exit."
   exit 1
endif

# Make output directory. Everything needed for later is stored here
mkdir -p $output_dir
cd $output_dir
ln -sf ${WPS_DIR}/util/rd_intermediate.exe .  # For querying the output file only, otherwise not used

#------------------------------------------------
# First iteration: MODEL fields
# Second iteration : SST, if $update_sst = true
#------------------------------------------------
foreach iter ( model sst )

   if ( $MPAS_REGIONAL =~ *true* || $MPAS_REGIONAL =~ *TRUE* ) then # $MPAS_REGIONAL from driver.csh
      set END_DATE     =  `${TOOL_DIR}/da_advance_time.exe $DATE ${FCST_RANGE}m`  # $FCST_RANGE from driver.csh
      @ LBC_FREQ_SEC = `expr $LBC_FREQ \* 3600` # $LBC_FREQ from driver.csh
   else
      set END_DATE     =  $DATE # For global run, only initial time needed (no boundary conditions)
      @ LBC_FREQ_SEC = 86400
   endif

   if ( $iter == model ) then
      set output_prefx = $ungrib_prefx_model # From driver
      set VTABLE_TYPE = $VTABLE_TYPE_MODEL
      if ( $RUN_STAGE == deterministic ) then
         set UNGRIB_INPUT_DIR = ${GRIB_INPUT_DIR_DETERMINISTIC}/${yyyymmddhh} # From driver.csh
      else if ( $RUN_STAGE == ensemble ) then
         set UNGRIB_INPUT_DIR = ${GRIB_INPUT_DIR_ENS}/${yyyymmddhh}/ens_${mem} # From driver.csh
      endif

   else if ( $iter == sst ) then
      set link = false # if this becomes true, no need to run ungrib for sst; just link to model file
      if ( $update_sst =~ *true* || $update_sst =~ *TRUE* ) then
	 set output_prefx = $ungrib_prefx_sst # From driver
	 set VTABLE_TYPE = "SST" 
	 if ( $RUN_STAGE == deterministic ) then
	    set UNGRIB_INPUT_DIR = ${GRIB_INPUT_DIR_DETERMINISTIC_SST}/${yyyymmddhh} # From driver.csh
            if ( $GRIB_INPUT_DIR_DETERMINISTIC == $GRIB_INPUT_DIR_DETERMINISTIC_SST ) set link = true # model, sst grib files are the same
	 else if ( $RUN_STAGE == ensemble ) then
	    set UNGRIB_INPUT_DIR = ${GRIB_INPUT_DIR_ENS_SST}/${yyyymmddhh}/ens_${mem} # From driver.csh
            if ( $GRIB_INPUT_DIR_ENS == $GRIB_INPUT_DIR_ENS_SST ) set link = true # model, sst grib files are the same
	 endif

	 set END_DATE     =  $DATE # SST only needed at initial time. Even if MPAS regional, SST not needed for LBCs

	 if ( $link == true ) break # break out of loop, and link SST file to model file at end

      else
         break # break out of the loop
      endif

   endif

   set END_DATE_WRF =  `${TOOL_DIR}/da_advance_time.exe $END_DATE 0 -w`

   #---- Make and go to working directory ---
   set workdir = ${output_dir}/${iter}
   mkdir -p $workdir
   cd $workdir

   # Fill WPS namelist
   rm -f namelist.wps
   cat > namelist.wps << EOF
&share
 wrf_core = 'ARW',
 max_dom = 1,
 start_date = '$START_DATE_WRF',
 end_date   = '$END_DATE_WRF',
 interval_seconds = ${LBC_FREQ_SEC},
 io_form_geogrid = 2,
 debug_level = 0
/

&ungrib
 out_format = 'WPS'
 prefix     = '${output_prefx}',
 pmin = 1.0, ! Pa
/
EOF

   # Link VTable
   if ( -e   ${VTABLE_DIR}/Vtable.${VTABLE_TYPE} ) then
      ln -sf ${VTABLE_DIR}/Vtable.${VTABLE_TYPE} ./Vtable # $VTABLE_DIR from driver.csh
   else
      echo "Vtable ${VTABLE_DIR}/Vtable.${VTABLE_TYPE} is missing."
      exit
   endif

   # Link GRIB files
   set files = "${UNGRIB_INPUT_DIR}/*"
   rm -f ./GRIBFILE*
   ${WPS_DIR}/link_grib.csh $files
   if ( ! -e ./GRIBFILE.AAA ) then
      echo "All files missing.  Exit"
      exit
   endif

   # Link executables and run
   ln -sf ${WPS_DIR}/ungrib/ungrib.exe .

   ./ungrib.exe # Run ungrib.exe

   if ( $status != 0) then
      echo "Ungrib.exe failed"
      exit 1
   endif

   rm -f ./PFILE:* # Clean temporary files

   mv ./${output_prefx}* $output_dir # move output files to final storage

   echo "$VTABLE_TYPE" | grep -i "ERA" # Check to see whether GRIB files are from ERA interim
   if ( $status == 0 ) then # If true, than ERA
      if ( ! -e ${SCRIPT_DIR}/ecmwf_coeffs ) then
	  echo "No coeffcient file."
	  echo "We looked for ${SCRIPT_DIR}/ecmwf_coeffs but it was missing."
	  exit 2
      endif
      ln -sf ${SCRIPT_DIR}/ecmwf_coeffs .
      ln -sf ${WPS_DIR}/util/calc_ecmwf_p.exe .
      ./calc_ecmwf_p.exe
   endif

end # end loop over "iter"

# If the input model and sst GRIB directories are the same
#, link the SST file to the model file
if ( $link == true ) then
   cd $output_dir
   ln -sf ./${ungrib_prefx_model}:${sdate} ./${ungrib_prefx_sst}:${sdate}
endif

exit 0
