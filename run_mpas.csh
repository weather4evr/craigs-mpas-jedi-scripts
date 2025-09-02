#!/bin/csh
#PBS -S /bin/csh
#PBS -N forecast
#PBS -A NMMM0021
#PBS -l walltime=10:00
#PBS -q main
#PBS -l job_priority=economy
#PBS -o forecast.out
#PBS -j oe 
#PBS -k oed
#PBS -l select=1:ncpus=128:mpiprocs=128
#PBS -m n
#PBS -r y
#PBS -M schwartz@ucar.edu
#PBS -V 
#
set DATE = $DATE   # From driver; ccyymmddhhnn
set hh = `echo "$DATE" | cut -c 9-10` # hour of $DATE
set minutes = `echo "$DATE" | cut -c 11-12` # minutes of $DATE
set mpas_date = `${TOOL_DIR}/da_advance_time.exe ${DATE} 0 -f ccyy-mm-dd_hh.nn.ss`

set PREV_DATE = `${TOOL_DIR}/da_advance_time.exe ${DATE} -${CYCLE_PERIOD}m -f ccyymmddhhnn`
set prev_mpas_date = `$TOOL_DIR/da_advance_time.exe $PREV_DATE 0 -f ccyy-mm-dd_hh.nn.ss`
set ENS_SIZE = $ENS_SIZE  # From driver

if ( $RUN_STAGE == next_cycle ) then
   setenv FCST_RANGE   $FCST_RANGE_DA
else if ( $RUN_STAGE == forecast ) then
   setenv FCST_RANGE   $FCST_RANGE
else
   echo "Error, Running forecasts for what?"
   echo "To run forecast or just advance model for next cycle?"
   echo "Usage is $0 (next_cycle,forecast)"
   exit 1
endif

# If first_date, only option is to run a cold-start forecast from external ICs
if ( $DATE == $FIRST_DATE )  then
   set MPAS_INPUT_SOURCE = external
   echo "Running an MPAS forecast from external ensemble on FIRST_DATE = $FIRST_DATE"
endif

# Figure out the correct "restart" setting
if ( $MPAS_INPUT_SOURCE == external ) then
   setenv mpas_restart   .false.  # default is true
   setenv config_do_DAcycling .false.  # default is false
   setenv restart_type   output   # default is input;output in streams_template.csh
else
   setenv mpas_restart   .true.  # default is true
   setenv config_do_DAcycling .true.  # Very important to cycle correctly; default is false
   setenv restart_type  "input;output"  # default is input;output in streams_template.csh
endif

# Figure out the resolution of this MPAS run
if ( $MPAS_STAGE == ensemble ) then
   set mesh = ensemble
else if ( $MPAS_STAGE == deterministic ) then
   if ( $MPAS_INPUT_SOURCE_DET == enkf ) then
      set mesh = ensemble # forecast initialized from enkf ens mean should be on ensemble mesh
   else
      set mesh = deterministic
   endif
else
   echo "MPAS_STAGE = $MPAS_STAGE which does not make sense"
   echo "It should be (ensemble,deterministic)"
   exit 2
endif
if ( $mesh == ensemble ) then
   setenv MPAS_GRID_INFO_DIR $grid_info_dir_ens
   setenv graph_info_prefx   $graph_info_prefx_ens
   setenv time_step $time_step_ens
   setenv config_len_disp $config_len_disp_ens
   setenv radiation_frequency $radiation_frequency_ens
   setenv num_mpas_cells      $num_mpas_cells_ens
   set lbc_dir_top = $MPAS_INIT_ENS_OUTPUT_DIR_TOP
   set mpas_invariant_file =  $mpas_invariant_file_ens
else if ( $mesh == deterministic ) then
   setenv MPAS_GRID_INFO_DIR $grid_info_dir_deterministic
   setenv graph_info_prefx   $graph_info_prefx_deterministic
   setenv time_step $time_step_deterministic
   setenv config_len_disp $config_len_disp_deterministic
   setenv radiation_frequency $radiation_frequency_deterministic
   setenv num_mpas_cells      $num_mpas_cells_deterministic
   set lbc_dir_top = $MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP
   set mpas_invariant_file =  $mpas_invariant_file_deterministic
else
   echo "mesh = ${mesh}, which makes no sense. exit"
   exit
endif

# See if we're running the forecast on a higher-resolution grid
#  than the analysis (e.g., run a 15-km forecast initialized from 30-km ICs).
set need_to_interpolate = false
if ( $RUN_STAGE == forecast ) then
   if ( $num_mpas_cells != $num_mpas_cells_free_fcst ) then
      setenv MPAS_GRID_INFO_DIR $grid_info_dir_free_fcst
      setenv graph_info_prefx   $graph_info_prefx_free_fcst
      setenv time_step $time_step_free_fcst
      setenv config_len_disp $config_len_disp_free_fcst
      setenv radiation_frequency $radiation_frequency_free_fcst
      setenv num_mpas_cells           $num_mpas_cells_free_fcst
      set lbc_dir_top = $MPAS_INIT_FREE_FCST_OUTPUT_DIR_TOP
      set need_to_interpolate = true
      set mpas_num_procs = $mpas_num_procs_free_fcst # mpas_num_procs_free_fcst environmental variable
   endif
endif

# Deal with batch stuff and specifying ensemble size
if ( $MPAS_STAGE == ensemble ) then
   #set mem_start = $PBS_ARRAYID  #PBS with "-t" flag
   set mem_start = $PBS_ARRAY_INDEX  #PBS with "-J" flag (PBS pro)
else if ( $MPAS_STAGE == deterministic ) then
   set mem_start =  -99999 # dummy, needs to be negative because of checking for ensemble size
endif
set mem_end =  $mem_start

######### Main code to run MPAS below here #########
@ mem = $mem_start
while ( $mem <= $mem_end && $mem <= $ENS_SIZE )

   set i3 = `printf %03d $mem` # three digit member (i.e., 001)
   set i4 = `printf %04d $mem` # four digit member (i.e., 0001)

   # ----------------------------------
   # Make and go to working directory
   # ----------------------------------
   if ( $MPAS_STAGE == ensemble ) then
      if ( $RUN_STAGE == next_cycle ) then
	 set rundir = ${EXP_DIR_TOP}/${DATE}/advance_ensemble/${mem}
      else if ( $RUN_STAGE == forecast ) then
	 set rundir = ${EXP_DIR_TOP}/${DATE}/fc/${mem}
      endif
   else if ( $MPAS_STAGE == deterministic ) then
      #if RUN_STAGE == forecast, put fc_${FCST_RANGE}h in directory?
      if ( $MPAS_INPUT_SOURCE == external ) then
         set rundir = ${EXP_DIR_TOP}/${DATE}/fc/${EXTERNAL_ICS_DETERMINISTIC}_initial_conditions
      else if ( $MPAS_INPUT_SOURCE == envar ) then
         set rundir = ${EXP_DIR_TOP}/${DATE}/fc/envar
      else if ( $MPAS_INPUT_SOURCE == enkf ) then
         set rundir = ${EXP_DIR_TOP}/${DATE}/fc/enkf_ens_mean
      endif
   endif

   mkdir -p $rundir
   cd $rundir

   rm -f ./restart*
   rm -f ./mpasout*
   rm -f ./*.lock
   rm -f ./MEMBER_DONE
   rm -f ./log*.abort
   rm -f ./core* ./*.err

   # Sometimes MPAS doesn't exit properly, so we don't remove the 
   # mpasout/restart file valid at the initial time, which is 
   # not needed for cycling.  So try to get rid of it from the last cycle to clean-up.
   if ( $RUN_STAGE == next_cycle ) then
      if ( $MPAS_STAGE == ensemble ) then
         rm -f ${EXP_DIR_TOP}/${PREV_DATE}/advance_ensemble/${mem}/${file_type}.${prev_mpas_date}.nc
         rm -f ${EXP_DIR_TOP}/${PREV_DATE}/advance_ensemble/${mem}/template_file.nc
      endif
   endif

   # ----------------------------------------------
   # Set some variables depending on input source
   # ----------------------------------------------
   if ( $MPAS_STAGE == ensemble ) then
      if ( $MPAS_INPUT_SOURCE == external ) then
	 setenv mpas_filename ${MPAS_INIT_ENS_OUTPUT_DIR_TOP}/${DATE}/ens_${mem}/init.nc  # This is the only input file needed
      else if ( $MPAS_INPUT_SOURCE == enkf ) then
	 setenv mpas_filename ${EXP_DIR_TOP}/${DATE}/enkf/analysis.${mpas_date}_en${i3}.nc
      endif

   else if ( $MPAS_STAGE == deterministic ) then
      if ( $MPAS_INPUT_SOURCE == external ) then
	 setenv mpas_filename   ${MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP}/${DATE}/init.nc
      else if ( $MPAS_INPUT_SOURCE == envar ) then
         setenv mpas_filename ${EXP_DIR_TOP}/${DATE}/envar/analysis.${mpas_date}.nc
      endif
   endif

   # --------------------------
   # Check for files
   # --------------------------
   foreach p ( $mpas_filename )
      if ( ! -e $p ) then
          echo "$p does not exist" > MISSING_FILE
          exit 3
      endif
   end

   # If we are using 2 stream I/O, we don't run MPAS in restart mode.
   if ( $use_2stream_IO =~ *true* || $use_2stream_IO =~ *TRUE* ) then
      setenv mpas_restart  .false.
   endif

   # --------------------------
   # Link proper input files
   # --------------------------

   # If in restart mode, we just need restart.nc file and will read the restart stream
   # Otherwise, we will read the input and invariant streams, which look for files
   #   named init.nc and invariant.nc, respectively
   if ( $mpas_restart =~ *true* || $mpas_restart =~ *TRUE* ) then
      ln -sf $mpas_filename    ./restart.${mpas_date}.nc # For a restart run, this is needed
   else
      # If ./MPAS2MPAS_SUCCESS is there, we assume we want to use the init.nc file
      #   that is already in this directory
      if ( ! -e ./MPAS2MPAS_SUCCESS ) ln -sf $mpas_filename    ./init.nc 

      # Link a file for the 'invariant' stream.  Can be an 'init.nc'-style file.
      ln -sf $mpas_invariant_file ./invariant.nc
      if ( ! -e ./invariant.nc ) then
         echo "Missing ./invariant.nc" > MISSING_INVARIANT_FILE
         exit 5
      endif
      if ( $need_to_interpolate == true ) then
         ln -sf $mpas_invariant_file_free_fcst ./invariant_interp_grid.nc
	 if ( ! -e ./invariant_interp_grid.nc ) then
	    echo "Missing ./invariant.nc for interp file" > MISSING_INVARIANT_FILE
	    exit
	 endif
      endif
   endif

   # See if we need to update sst for this cycle. If so, point to the file.
   setenv update_sst_interval  none # namelist.template.csh uses this to set the MPAS namelist. also used in streams_template.csh
   if ( $update_sst =~ *true* || $update_sst =~ *TRUE* ) then
      foreach sst_hour ( $update_sst_hours ) # update_sst_hours from driver.csh; could be a list
         if ( $sst_hour == $hh && $minutes == 00 ) then
            if ( $mesh == ensemble ) then
	       set sst_fname = ${MPAS_INIT_ENS_OUTPUT_DIR_TOP}/${DATE}/ens_${mem}/sfc_update.nc
            else if ( $mesh == deterministic ) then
	       set sst_fname = ${MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP}/${DATE}/sfc_update.nc
	    endif
	    if ( $need_to_interpolate == true ) then
	       set sst_fname = ${MPAS_INIT_FREE_FCST_OUTPUT_DIR_TOP}/${DATE}/sfc_update.nc
	    endif
	    if ( -e $sst_fname ) then
	       ln -sf $sst_fname  ./sfc_update.nc
	    else
	       echo "SST file ${sst_fname} not there. Exit." > MISSING_SST
	       exit 1
	    endif
	    setenv update_sst_interval "99_00:00:00" # "initial_only" may not work, so set it to "99_00:00:00", which is absurd but will still read at initial time
	    break # no need to continue loop; we already found our match
         endif
      end
   endif

   if ( $need_to_interpolate == true && ( ! -e ./MPAS2MPAS_SUCCESS ) ) then
      if ( $mpas_restart =~ *true* || $mpas_restart =~ *TRUE* ) then
         set file_to_interpolate = ./restart.${mpas_date}.nc
         set source_grid_template_file = $file_to_interpolate
         set destination_grid_template_file = 
      else
         set file_to_interpolate = ./init.nc
         set source_grid_template_file = ./invariant.nc
         set destination_grid_template_file = ./invariant_interp_grid.nc
      endif
      set variables_to_copy_from_destination_file = \
        "'rho_base','theta_base','isice_lu','iswater_lu','sst','vegfra','seaice','xice','xland','dzs','ter'"

      rm -f ./namelist.input
      cat > ./namelist.input << EOF
&share
source_grid_template_file = '${source_grid_template_file}'
destination_grid_template_file = '${destination_grid_template_file}'
file_to_interpolate = '${file_to_interpolate}'
output_file = './interpolated_file.nc'
weight_file = '${interpolation_weight_file}' ! './weights.dat'
netcdf_output_type = 'cdf5'
print_before_and_after_interp_values = .true.
do_vertical_interpolation = .true.
variables_to_copy_from_destination_file = ${variables_to_copy_from_destination_file}
exit_on_landuse_mismatch = .false.
/
EOF

       ln -sf $MPAS2MPAS_EXEC ./mpas2mpas.exe
       rm -f ./interpolated_file.nc
       ./mpas2mpas.exe >& mpas2mpas.log # serial code
       if ( `grep -i "All done" ./mpas2mpas.log | wc -l` != 1 ) then
          touch -f ./MPAS2MPAS_FAILED
          exit 5
       else
          touch -f ./MPAS2MPAS_SUCCESS
          mv $file_to_interpolate ${file_to_interpolate}_ORIG
          mv ./interpolated_file.nc $file_to_interpolate # This is the new initial condition file
       endif
    endif

   #---------------------------------------------------------
   # Link necessary input files and code, and fill namelist
   #---------------------------------------------------------
   if ( $mpas_compiled_within_jedi == true || $mpas_compiled_within_jedi == .true. ) then
     #ln -sf ${MPAS_CODE_DIR}/build/mpas-bundle/bin/mpas_atmosphere ./atmosphere_model
      set exec = `find $MPAS_JEDI_BUNDLE_DIR -name mpas_atmosphere` # could be several places
      ln -sf $exec[1] ./atmosphere_model
      set this_run_cmd = $run_cmd_jedi
      # If these aren't in $mpas_environment_file, they need to be set
      setenv GFORTRAN_CONVERT_UNIT 'native;big_endian:101-200' # needed for gfortran compiler
      setenv F_UFMTENDIAN 'big_endian:101-200' # maybe needed for intel compiler
      if ( $?mpasjedi_library_path ) setenv LD_LIBRARY_PATH ${mpasjedi_library_path}:$LD_LIBRARY_PATH # need path of library on derecho
   else
      ln -sf ${MPAS_CODE_DIR}/atmosphere_model .
      set this_run_cmd = $run_cmd
   endif
   ln -sf ${MPAS_TABLE_DIR}/*.TBL .
   ln -sf ${MPAS_TABLE_DIR}/*.DBL .
   ln -sf ${MPAS_TABLE_DIR}/*DATA .
   if ( $config_microp_scheme =~ *thompson* ) then
      set fnames = `ls ./*MP_THOMPSON*` # were hopeully linked in the previous 3 lines
      if ( $#fnames != 4 ) then
	 touch -f ./MISSING_THOMPSON_MP_TABLES
	 echo "Missing MP_THOMPSON files in $MPAS_TABLE_DIR".
	 exit 6
      endif
   endif

   ln -sf ${MPAS_GRID_INFO_DIR}/${graph_info_prefx}* .
   if ( -e $soundings_file ) ln -sf $soundings_file ./sounding_locations.txt

   # Need to find proper LBC directory; there may not be external files
   # exactly at $DATE, which is okay--we can go back in time to find LBC files
   # so long as they contain information extending through $FCST_RANGE
   if ( $MPAS_REGIONAL =~ *true* || $MPAS_REGIONAL =~ *TRUE* ) then
      set offsets = ( `seq 0 1 360`) #minutes; don't go back more than 6 hours
      set lbc_dir = "missing"
      foreach offset ( $offsets ) 
         set this_date = `$TOOL_DIR/da_advance_time.exe $DATE -${offset}m -f ccyymmddhhnn`
	 if ( $MPAS_STAGE == ensemble ) then
	    if ( -d ${lbc_dir_top}/${this_date}/ens_${mem} ) then
	       set lbc_dir = ${lbc_dir_top}/${this_date}/ens_${mem}
	       break
	    endif
	 else if ( $MPAS_STAGE == deterministic ) then
	    if ( -d ${lbc_dir_top}/${this_date} ) then
	       set lbc_dir = ${lbc_dir_top}/${this_date}
	       break
	    endif
	 endif
      end
      if ( $lbc_dir == missing ) then
	 echo "No LBCs within $offset minutes" >> ./FAIL
	 exit 6
      else
	#setenv lbc_date `${TOOL_DIR}/da_advance_time.exe ${this_date} 0 -f ccyy-mm-dd_hh:nn:ss`
	 ln -sf ${lbc_dir}/lbc*.nc .
      endif
   endif

   # Fill namelist and streams
   $NAMELIST_TEMPLATE mpas $rundir # Output is ./namelist.atmosphere
   $STREAMS_TEMPLATE mpas $rundir # Streams file

   #-------------------------------------------------------------
   # Run MPAS; Important to source default environment when done
   #   because $TOOL_DIR/da_advance_time.exe could be called
   #-------------------------------------------------------------
   ln -sf $mpas_environment_file # have a copy of this in working directory for testing
   source $mpas_environment_file

   # cd again to $rundir; under some strange conditions, probably a combination
   # of job arrays on derecho, and possible use of 'pwd' in $mpas_environment_file
   # (if $mpas_environment_file ==> jedi_environment), things can end up in the
   # wrong directory. pretty strange, but just do it.
   cd $rundir

   $this_run_cmd -n $mpas_num_procs -ppn $mpas_num_procs_per_node ./atmosphere_model # mpiexec -n 144 -ppn 32
  #$this_run_cmd ./atmosphere_model # Run the model! ; this was used on Cheyenne

   if ( $status != 0 ) then
      echo "MPAS failed. Exit." >> ./FAIL
      exit 6
   endif

   source $default_environment_file

   if ( 1 == 2 ) then
   if ( $RUN_STAGE == next_cycle ) then
      if ( $MPAS_INPUT_SOURCE == enkf && $MPAS_STAGE == ensemble ) then
	 set expected_date = `${TOOL_DIR}/da_advance_time.exe $DATE ${FCST_RANGE}m -f ccyy-mm-dd_hh.nn.ss`
	 set expected_filename = ./${file_type}.${expected_date}.nc
	 if ( -e $expected_filename ) then # first check : existence
	    if ( `stat -c %s $expected_filename` > 2000000 ) then # second check: file size
	       if ( `grep "Logging complete.  Closing file at" ./log.atmosphere.0000.out | wc -l` == 1 ) then # third check: log
		  touch -f ./MEMBER_DONE # flag indicates success
		  if ( $CYCLE_PERIOD == 60 ) then
		     if ( $hh == 00 || $hh == 06 || $hh == 12 || $hh == 18 ) then
			echo ""
		     else
			foreach fhr ( `seq 0 5 $FCST_RANGE` ) # $FCST_RANGE in minutes
			  # strip down previous cycle's files for use in envar...we don't need everything...
			  set this_mpas_date = `$TOOL_DIR/da_advance_time.exe $PREV_DATE ${fhr}m -f ccyy-mm-dd_hh.nn.ss`
			  set fname = ${EXP_DIR_TOP}/${PREV_DATE}/advance_ensemble/${mem}/${file_type}.${this_mpas_date}.nc
			  if ( -e $fname ) ncks -O -v theta,pressure_p,pressure_base,qv,uReconstructZonal,uReconstructMeridional,surface_pressure,qr,qs,qg,qc,qi,xtime $fname $fname
			end
		     endif
		  endif
	       endif # log check
	    endif # file size check
	 endif # existence check
      endif # ( $MPAS_INPUT_SOURCE == enkf && $MPAS_STAGE == ensemble )
   endif # ( $RUN_STAGE == next_cycle ) then
   endif

   # Cleanup to save disk space
   rm -f ./output*.nc # not used
   rm -f ./template_file.nc # not needed
   if ( $RUN_STAGE == next_cycle ) rm -f ./${file_type}.${mpas_date}.nc # mpasout/restart file not needed at initial time.

   #--------------------------------------------
   # Go to next member or exit if deterministic
   #--------------------------------------------
   @ mem ++

end   # End loop over members

exit 0
