#! /bin/csh
#PBS -S /bin/csh
#PBS -N test
#PBS -A NMMM0015
#PBS -l walltime=6:00
#PBS -q main
#PBS -l job_priority=economy
#PBS -o ./jedi.out
#PBS -j oe 
#PBS -k eod 
#PBS -l select=3:ncpus=128:mpiprocs=128
#PBS -m n    
#PBS -M schwartz@ucar.edu
#PBS -V 
#
#--------------------------------------------
# Get Date information and set obs directory 
#--------------------------------------------
setenv DATE $DATE  #From driver, ccyymmddnn (e.g., 202305231200)
setenv mpas_date         `${TOOL_DIR}/da_advance_time.exe ${DATE} 0 -f ccyy-mm-dd_hh.nn.ss`
setenv jedi_time_string  `${TOOL_DIR}/da_advance_time.exe ${DATE} 0 -f ccyy-mm-ddThh:nn:ssZ`

set PREV_DATE = `${TOOL_DIR}/da_advance_time.exe ${DATE} -${CYCLE_PERIOD}m -f ccyymmddhhnn`

set THIS_OB_DIR = ${OB_DIR}/${DATE} #From driver
setenv time_window_begin `${TOOL_DIR}/da_advance_time.exe ${DATE} -${ob_time_window}m -f ccyy-mm-ddThh:nn:ssZ`

set file_type = ${file_type} # From driver # use mpasout or restart files?

#-------------------------------------------------------
# Don't allow JEDI analysis for first date
#   Force user to only use first date for running
#   MPAS forecasts to move away from GFS/global ICs
#   (or potentially creating initial perturbed ensemble)
#-------------------------------------------------------
# BUMP doesn't actually care about the date, so okay if $DATE == $FIRST_DATE
if ( $DATE == $FIRST_DATE ) then
   if ( $JEDI_ANALYSIS_TYPE != bump ) then
      echo "for FIRST_DATE = $FIRST_DATE you can only run a cold-start forecast"
      exit 
   endif
endif

# Do we need the first guess at multiple times for 4DEnVar?
if ( $FOUR_D_ENVAR =~ *true* || $FOUR_D_ENVAR =~ *TRUE* ) then
   set relative_fcst_minutes = ( $ens_fcst_mins ) # Relative forecast minutes compared to $DATE (e.g., -120, -60, 0, 60, 120)
else
   set relative_fcst_minutes = ( 0 ) 
endif
if ( $JEDI_ANALYSIS_TYPE == bump ) then
   set relative_fcst_minutes = ( 0 ) 
endif
if ( $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then
   set relative_fcst_minutes = ( $FHR ) # $FHR is a special environmental variable
endif

# Assume we need obs. If not, change (currently only false for $JEDI_ANALYSIS_TYPE == bump)
set observations_needed = true

# Do we need the prior ensemble?
if ( $JEDI_ANALYSIS_TYPE == envar || $JEDI_ANALYSIS_TYPE =~ *enkf* ) then
   set need_prior_ensemble = true
else
   set need_prior_ensemble = false
endif

# Do we need a deterministic background?
if ( $JEDI_ANALYSIS_TYPE == envar || $JEDI_ANALYSIS_TYPE == bump || $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then
   set need_prior_deterministic_background = true
else
   set need_prior_deterministic_background = false
endif

#------------------------------------------------
# Set some options depending on JEDI application
#------------------------------------------------
if ( $JEDI_ANALYSIS_TYPE == envar ) then
   setenv num_outer_loops    $num_outer_loops # From driver
   setenv num_inner_loops    $num_inner_loops
   set    dir_prefx =     envar
   set MPAS_GRID_INFO_DIR = $grid_info_dir_deterministic
   setenv graph_info_prefx     $graph_info_prefx_deterministic
   setenv time_step $time_step_deterministic
   setenv config_len_disp $config_len_disp_deterministic
   setenv radiation_frequency $radiation_frequency_deterministic
   set bump_files_needed = true
   set jedi_exec = mpasjedi_variational.x

else if ( $JEDI_ANALYSIS_TYPE =~ *enkf* ) then
   setenv num_outer_loops    0 # From driver
   setenv num_inner_loops    0
   set MPAS_GRID_INFO_DIR = $grid_info_dir_ens
   setenv graph_info_prefx     $graph_info_prefx_ens
   setenv time_step $time_step_ens
   setenv config_len_disp $config_len_disp_ens
   setenv radiation_frequency $radiation_frequency_ens
   set bump_files_needed = false

   set jedi_exec = mpasjedi_enkf.x

   if ( $JEDI_ANALYSIS_TYPE == enkf_prior_mean ) then
      set dir_prefx = ens_mean
      set jedi_enkf_num_procs_per_node_observer = $jedi_enkf_num_procs_per_node_observer_mean
   else if ( $JEDI_ANALYSIS_TYPE == enkf_prior_members ) then
      set dir_prefx = ens # becomes member-dependent later
      set member = $PBS_ARRAY_INDEX # #PBS with "-J" flag (PBS pro)
      set jedi_enkf_num_procs_per_node_observer = $jedi_enkf_num_procs_per_node_observer_members
   else if ( $JEDI_ANALYSIS_TYPE == enkf_all_at_once ) then
      set dir_prefx = enkf
      set jedi_enkf_num_procs_per_node_observer = $jedi_enkf_num_procs_per_node_solver
   else if ( $JEDI_ANALYSIS_TYPE == enkf_solver ) then
      set dir_prefx = enkf
      set jedi_enkf_num_procs_per_node_observer = $jedi_enkf_num_procs_per_node_observer_mean # for OMA/concatenation...might be wrong
   endif

else if ( $JEDI_ANALYSIS_TYPE == bump ) then
   setenv num_outer_loops    0
   setenv num_inner_loops    0
   set    dir_prefx = "" 
   set MPAS_GRID_INFO_DIR = $grid_info_dir_ens
   setenv graph_info_prefx     $graph_info_prefx_ens

  #set jedi_exec = mpasjedi_error_covariance_training.x
   set jedi_exec = mpasjedi_error_covariance_toolbox.x

   set observations_needed = false
   set bump_files_needed = false

else if ( $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then
   setenv num_outer_loops    0
   setenv num_inner_loops    0
   set    dir_prefx =     fcst_verif
   set MPAS_GRID_INFO_DIR = $MPAS_GRID_INFO_DIR_FREE_FCST
   setenv graph_info_prefx     $graph_info_prefx_free_fcst
   setenv time_step $time_step_free_fcst
   setenv config_len_disp $config_len_disp_free_fcst
   setenv radiation_frequency $radiation_frequency_free_fcst
   set bump_files_needed = false

   set valid_time      = `${TOOL_DIR}/da_advance_time.exe ${DATE} ${FHR} -f ccyymmddhhnn` # FHR from environment
   set valid_time_mpas = `${TOOL_DIR}/da_advance_time.exe $valid_time 0 -f ccyy-mm-dd_hh.nn.ss`
   set THIS_OB_DIR = ${OB_DIR}/${valid_time} 

   set jedi_exec = mpasjedi_hofx3d.x

else
   echo "JEDI_ANALYSIS_TYPE = $JEDI_ANALYSIS_TYPE invalid. exit."
   exit 1
endif

#-------------------------------------
# Set working directory and go to it
#-------------------------------------
if ( $JEDI_ANALYSIS_TYPE == bump ) then
   set JEDI_RUN_DIR = $BE_DIR # $BE_DIR from driver.csh
else if ( $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then # Special case, so special directory
   set JEDI_RUN_DIR = ${EXP_DIR_TOP}/${DATE}/${dir_prefx}/f${FHR} # FHR from environment
else if ( $JEDI_ANALYSIS_TYPE == enkf_prior_mean ) then
   set JEDI_RUN_DIR = ${EXP_DIR_TOP}/${DATE}/enkf/${dir_prefx}
else if ( $JEDI_ANALYSIS_TYPE == enkf_prior_members ) then
   set JEDI_RUN_DIR = ${EXP_DIR_TOP}/${DATE}/enkf/${dir_prefx}_${member}
else
   set JEDI_RUN_DIR = ${EXP_DIR_TOP}/${DATE}/${dir_prefx}
endif

mkdir -p $JEDI_RUN_DIR
cd $JEDI_RUN_DIR  # The working directory 
rm -f ./*.lock
rm -f ./*.err
rm -f ./*.abort
rm -f ./*.log*

setenv jedi_output_dir   ./dbOut # Many JEDI output files will be put in here. Make an environmental variable so .yaml.csh files can see it.
rm -rf $jedi_output_dir
mkdir -p $jedi_output_dir

# -------------------------------------------------------------------------------
# For certain analysis types, link all prior ensemble members 
# to the working directory.  Link for multiple hours in case we want FGAT/4DEnVar
# -------------------------------------------------------------------------------
if ( $need_prior_ensemble =~ *true* || $need_prior_ensemble =~ *TRUE* ) then

   set PREV_ENS_DIR_TOP = ${EXP_DIR_TOP}/${PREV_DATE}/advance_ensemble # Location of prior ensemble when cycling

   foreach minute ( $relative_fcst_minutes )
      set this_mpas_date = `${TOOL_DIR}/da_advance_time.exe ${DATE} ${minute}m -f ccyy-mm-dd_hh.nn.ss` # valid time of interest

     #@ num_diag_files = 0
      @ ie = 1
      while ( $ie <= $ENS_SIZE )
	 set m3 = `printf %03d $ie` # Each member must have three digits (i.e., 001, 010, 100)
	 set fname = ${PREV_ENS_DIR_TOP}/${ie}/${file_type}.${this_mpas_date}.nc
	 if ( -e $fname ) then
	    ln -sf $fname ./mpas_en${m3}.nc # Prior ensemble members; YAML looks for ./mpas_en${m3}.nc
	 else
	    echo "$fname not there...but needed.  exit" >> ./MISSING_ENSEMBLE_MEMBERS
	    exit 2
	 endif
	 # Also link diag files...not as strict error checking
	#set fname = ${PREV_ENS_DIR_TOP}/${ie}/diag.${this_mpas_date}.nc
	#if ( -e $fname ) then
	#   ln -sf $fname ./mpas_diag_${this_mpas_date}_en${m3}    # Link the ensemble member, this file is input
	#   @ num_diag_files ++
	#endif
	 @ ie ++
      end
   end

   # For EnKF, it's helpful to have the ensemble mean background, so compute it. not critical to cycling, 
   # so don't check for errors
   if ( $JEDI_ANALYSIS_TYPE == enkf_prior_mean || $JEDI_ANALYSIS_TYPE == enkf_all_at_once ) then
      cp ./mpas_en001.nc ./mpas_prior_ensmean.nc # float variables in ./mpas_prior_ensmean.nc will be overwritten
      cp ./mpas_en001.nc ./mpas_prior_stddev.nc

      ln -sf $ENS_AVERAGE_EXEC .
      set calc_stddev = false  # too slow for a really big problem, so set to false to bypass
      $run_cmd -n $ENS_SIZE -ppn $num_procs_per_node $ENS_AVERAGE_EXEC \
			. mpas_prior_ensmean.nc mpas_prior_stddev.nc mpas_en $ENS_SIZE $calc_stddev > ./ensmean.log
      if ( $calc_stddev == false ) rm -f ./mpas_prior_stddev.nc # just get rid of it so we don't make mistakes
   endif

   # Also need to find an invariant.nc file on the ensemble grid
   # (which can be an init.nc file) to link as invariant.nc
   ln -sf $mpas_invariant_file_ens ./invariant_ens.nc
   if ( ! -e ./invariant_ens.nc ) then
      touch -f ./MISSING_STATIC_ENS
      exit 7
   endif
endif #if ( $need_prior_ensemble =~ *true* || $need_prior_ensemble =~ *TRUE* )

# Now see about a file for the deterministic background. If need_prior_ensemble = true, 
# we've already checked to see if all ensemble members were there.
# There can be multiple backgrounds for FGAT/4DEnVar
set det_background = ./mpasin.${mpas_date}.nc # deterministic background valid at $DATE
if ( $need_prior_deterministic_background =~ *true* || $need_prior_deterministic_background =~ *TRUE* ) then

   # relative_fcst_minutes is a forced scalar (0) for JEDI_ANALYSIS_TYPE forward_operator_for_forecast_verif, bump
   foreach minute ( $relative_fcst_minutes )
      set this_mpas_date = `${TOOL_DIR}/da_advance_time.exe ${DATE} ${minute}m -f ccyy-mm-dd_hh.nn.ss` # valid time of interest

      set this_det_background = mpasin.${this_mpas_date}.nc # deterministic background that we will make (it will be a link)

      if ( $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then
	 set directory  = "."
	 set fname = ${file_type}.${this_mpas_date}.nc
      else if ( $JEDI_ANALYSIS_TYPE == bump ) then
	 set directory = ${MPAS_INIT_ENS_OUTPUT_DIR_TOP}/${DATE}
	 set fname = init.nc
      else if ( $JEDI_ANALYSIS_TYPE == envar ) then
	 if ( $envar_det_fg_source == cycle ) then
	    set directory = ${EXP_DIR_TOP}/${PREV_DATE}/fc/envar
	    set fname = ${file_type}.${this_mpas_date}.nc
	 else if ( $envar_det_fg_source == cold_start ) then
	    set directory = ${MPAS_INIT_DETERMINISTIC_OUTPUT_DIR_TOP}/${DATE}
	    set fname = init.nc
         else if ( $envar_det_fg_source == prior_ens_mean ) then
	    # Compute the ensemble mean prior
	    # Program over-writes variables in "outputname", so need to copy something to it
	    cp ./mpas_en001.nc $this_det_background # float variables in $this_det_background will be overwritten
	    cp ./mpas_en001.nc ./mpas_prior_stddev_${this_mpas_date}.nc 

	    ln -sf  $ENS_AVERAGE_EXEC .
	    set calc_stddev = false  # too slow for a really big problem, so set to false to bypass
	    $run_cmd -n $ENS_SIZE -ppn $num_procs_per_node $ENS_AVERAGE_EXEC \
		  . $this_det_background mpas_prior_stddev_${this_mpas_date}.nc mpas_en $ENS_SIZE $calc_stddev > ./ensmean_f${minute}mins.log
	    if ( $calc_stddev == false ) rm -f ./mpas_prior_stddev_${this_mpas_date}.nc # just get rid of it so we don't make mistakes
	    if ( `grep -i "All done" ./ensmean_f${minute}mins.log | wc -l` != 1 ) then
	       touch -f ./AVERAGING_FAILED_f${minute}mins # If it failed, could fall-back to ncea for just a subset of fields needed by JEDI
	       exit 3
	    endif

	    # Also average over the diag files, but only if all the files are there
	   #if ( $num_diag_files == $ENS_SIZE ) then
	   #   cp ./mpas_diag_f${f3}_en001 ./mpas_prior_mean_diag.nc # float variables in ./mpas_prior_mean_diag.nc will be overwritten
	   #   cp ./mpas_diag_f${f3}_en001 ./mpas_prior_stddev_diag.nc 
	   #   set calc_stddev = true
	   #   $run_cmd  $ENS_AVERAGE_EXEC . ./mpas_prior_mean_diag.nc ./mpas_prior_stddev_diag.nc mpas_diag_f${f3}_en $ENS_SIZE $calc_stddev > ./ensmean_diag_f${f3}.log
	   #endif
	    continue # no need to go on--we've computed our deterministic background!
	 endif # endif envar options
      endif #endif all options

      # Link the file--if envar and $envar_det_fg_source == prior_ens_mean, then this block doesn't execute
      if ( -e ${directory}/${fname} ) then
	 ln -sf ${directory}/${fname} $this_det_background
      else
	 echo "${directory}/${fname} not there...but needed.  exit" > ./MISSING_DETERMINISTIC_FILE
	 exit 4
      endif

   end # end loop over $relative_fcst_minutes

   # Get a invariant.nc file for the deterministic field; could be on the ensemble mesh.
   if ( $JEDI_ANALYSIS_TYPE == bump ) then
      set fname = $mpas_invariant_file_ens
   else
      set fname = $mpas_invariant_file_deterministic
   endif
   ln -sf $fname ./invariant_deterministic.nc  
   if ( ! -e ./invariant_deterministic.nc ) then
      touch -f ./MISSING_STATIC_DETERMINISTIC
      exit 8
   endif

endif #if ( $need_prior_deterministic_background =~ *true* || $need_prior_deterministic_background =~ *TRUE* )

# Get background error files
if ( $bump_files_needed =~ *true* || $bump_files_needed =~ *TRUE* ) then
   set p6 = `printf %06d $jedi_variational_num_procs` # 6 digits
   set num_bump_files = `ls ${BE_DIR}/${BE_PREFIX}*grids_local*${p6}-*.nc | wc -l`
   if ( $num_bump_files != $jedi_variational_num_procs ) then
      ls ${BE_DIR}/${BE_PREFIX}*
      echo "There are $num_bump_files bump files in ${BE_DIR}"
      echo "But you are running JEDI with ${jedi_variational_num_procs} processors."
      echo "These should be equal. Need to change number of processors. Try again."
      exit 5
   endif
   mkdir -p ./bump_files
   ln -sf ${BE_DIR}/${BE_PREFIX}*${p6}-*.nc ./bump_files # Link the files
endif

# Link necessary MPAS model files
ln -sf ${MPAS_TABLE_DIR}/*.TBL .
ln -sf ${MPAS_TABLE_DIR}/*.DBL .
ln -sf ${MPAS_TABLE_DIR}/*DATA .
set fnames = stream_list.atmosphere.{analysis,background,control,ensemble}
foreach fname ( $fnames ) 
   set f = `find $MPAS_JEDI_BUNDLE_DIR -name $fname -type f`
   if ( $#f == 0 ) then
      echo "$f is missing. Check $MPAS_JEDI_BUNDLE_DIR for it."
      exit
   else
      ln -sf $f .
   endif
end

# Thompson microphysics tables must come from $MPAS_JEDI_BUNDLE_DIR
if ( $config_microp_scheme =~ *thompson* ) then # Make sure we need Thompson microphysics tables
  #set fnames = `ls ${MPAS_JEDI_BUNDLE_DIR}/build/mpas-bundle/MPAS/core_atmosphere/MP_THOMPSON*`
   set fnames = `find $MPAS_JEDI_BUNDLE_DIR -name "MP_THOMPSON*"`
   if ( $#fnames != 4 ) then
      touch -f ./MISSING_THOMPSON_MP_TABLES
      echo "There must be 4 files beginning with MP_THOMPSON in ${MPAS_JEDI_BUNDLE_DIR}/build/.../MPAS/core_atmosphere"
      echo "But there are $#fnames files instead."
      echo "To create these files, within the MPAS-Bundle framework run mpas_atmosphere_build_tables"
      echo "Then copy the MP_THOMPSON* files to ${MPAS_JEDI_BUNDLE_DIR}/build/.../MPAS/core_atmosphere"
      echo " ... you might have to make that directory."
      exit 6
   else
      foreach fname ( $fnames )
         ln -sf $fname .
      end
     #ln -sf ${MPAS_JEDI_BUNDLE_DIR}/build/mpas-bundle/MPAS/core_atmosphere/MP_THOMPSON* .
   endif
endif
ln -sf ${MPAS_GRID_INFO_DIR}/${graph_info_prefx}* .
ln -sf $JEDI_GEOVARS_YAML   ./geovars.yaml # Some older versions of JEDI don't need this
ln -sf $JEDI_KEPTVARS_YAML  ./keptvars.yaml
ln -sf $OBSOP_NAME_MAP_YAML ./obsop_name_map.yaml
ln -sf ${RADAR_DA_COEFFS}/*.txt . # coefficients for radar DA

# To get the namelist/streams/YAML files to fill properly,
# need to force $DATE to valid_time...shouldn't hurt anything by doing here
if ( $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then 
   setenv DATE $valid_time
endif

# For EnKF copy ensemble background to analysis for each member; we'll overwrite the analysis.
if ( $JEDI_ANALYSIS_TYPE == enkf_solver || $JEDI_ANALYSIS_TYPE == enkf_all_at_once ) then
   @ ie = 1
   while ( $ie <= $ENS_SIZE )
      set m3 = `printf %03d $ie` # Each member must have three digits (i.e., 001, 010, 100)
      cp ./mpas_en${m3}.nc ./analysis.${mpas_date}_en${m3}.nc
      @ ie ++
   end
   cp ./mpas_en001.nc ./analysis.${mpas_date}_en000.nc # ensemble mean
endif

#-----------------------------------------------------------------------
# Get observation information,link the observation files, and fill a
#  YAML file for the observations
#------------------------------------------------------------------------
#set obs_str      = ""
set radiance_str = ""
setenv max_hloc -1 # maximum obs-space localization across all obs types; set correctly below
if ( $observations_needed =~ *true* || $observations_needed =~ *TRUE* ) then

   set obs_yaml = ./obs.yaml
   rm -f $obs_yaml

   # Select all lines not containing # (grep -v "#"); these are assumed to be lines with valid data
   if ( ! -e $OBS_INFO_FILE ) then
      echo "$OBS_INFO_FILE is missing. exit"
      exit 10
   endif
   set instruments         = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 1`
   set horiz_localizations = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 2` # km
   set vert_localizations  = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 3` # km or scale-height
   set vert_loc_unit       = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 4`
   set outlier_thresholds  = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 5`
   set horiz_thinning      = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 6` # km
   set vert_thinning       = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 7` # Pa
   set radiance_channels   = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 8`
   set radiance_bc         = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 9`
   set assim_or_eval       = `cat $OBS_INFO_FILE | grep -v "#" | cut -d "|" -f 10` # assim or eval

   if ( $JEDI_ANALYSIS_TYPE =~ *enkf* ) then
      setenv iterations_list  null
   else
      setenv iterations_list  `seq -s , 0 1 $num_outer_loops` # e.g., 0,1,2,3
   endif

   set n = $#instruments
   @ ob = 0 
   foreach i ( `seq 1 1 $n`)
      set inst = ${instruments[$i]}
      if ( -e   ${THIS_OB_DIR}/${inst}_obs_${DATE}.h5 && -e ${JEDI_YAML_PLUGS}/${inst}.yaml.csh ) then
	 setenv inputDataFile    ./${inst}_obs_${DATE}.h5
	 setenv outputDataFile   ${jedi_output_dir}/obsout_omb_${inst}.h5
	 setenv hloc         `echo "${horiz_localizations[$i]} * 1000" | bc -l` # km --> meters
	 setenv vloc_unit    ${vert_loc_unit[$i]}
	 setenv horiz_thin   ${horiz_thinning[$i]}
	 setenv vert_thin    ${vert_thinning[$i]}
	 setenv channels     ${radiance_channels[$i]}
	 setenv varBC        ${radiance_bc[$i]}
	 setenv assimOrEval  ${assim_or_eval[$i]}
	 if ( $JEDI_ANALYSIS_TYPE == enkf_prior_members ) then
	   #ln -sf ${EXP_DIR_TOP}/${DATE}/enkf/ens_mean/dbOut/obsout_omb_${inst}.h5 $inputDataFile
	    ln -sf ${EXP_DIR_TOP}/${DATE}/enkf/ens_mean/dbOut/obsout_omb_${inst}_1st_pass.h5 $inputDataFile
	    setenv bgchk_thresh 999999
	  ##setenv PreQC_maxvalue 3 #0
	   #setenv horiz_thin -1
	   #setenv vert_thin  -1
	 else if ( $JEDI_ANALYSIS_TYPE == enkf_solver ) then
	    ln -sf ${EXP_DIR_TOP}/${DATE}/enkf/ens_mean/dbOut/obsout_omb_${inst}.h5 ./${inst}_obs_${DATE}_orig.h5 # save a copy
	    cp ${EXP_DIR_TOP}/${DATE}/enkf/ens_mean/dbOut/obsout_omb_${inst}.h5 $inputDataFile
	    foreach ie ( `seq 1 1 $ENS_SIZE` )
	       ncks -A ${EXP_DIR_TOP}/${DATE}/enkf/ens_${ie}/dbOut/obsout_omb_${inst}_processed.h5 $inputDataFile
	    end
	   #set nbatches = 4
	   #foreach b ( `seq 1 1 $nbatches` )
	   #   set f = ./batch${b}.csh
	   #   rm -f $f
	   #   echo "foreach ie ( `seq $b $nbatches $ENS_SIZE` )" >> $f
	   #   echo "ncks -A ${EXP_DIR_TOP}/${DATE}/enkf/"'ens_${ie}'"/dbOut/obsout_omb_${inst}_processed.h5 ./tmp_batch${b}.h5" >> $f
	   #   echo "end" >> $f
	   #   csh $f &
	   #end
	   #wait # wait for all background processes to finish
	   #foreach b ( `seq 1 1 $nbatches` )
	   #   ncks -A ./tmp_batch${b}.h5 $inputDataFile
	   #end

	    setenv outputDataFile $inputDataFile # EnKF in solver mode looks for $outputDataFile to read in
	    setenv bgchk_thresh 999999
	   #setenv PreQC_maxvalue 3 #0
	 else
	    ln -sf ${THIS_OB_DIR}/${inst}_obs_${DATE}.h5 $inputDataFile
	    setenv bgchk_thresh ${outlier_thresholds[$i]}
	   #setenv PreQC_maxvalue 3
	 endif
	 if ( $vloc_unit == pressure ) then
	    setenv applyLogTransformation true
	    setenv vloc         ${vert_localizations[$i]
	 else if ( $vloc_unit == height ) then
	    setenv vloc         `echo "${vert_localizations[$i]} * 1000" | bc -l`  # km --> meters
	    setenv applyLogTransformation false
	 else
	    echo "vloc_unit = $vloc_unit invalid. should be either height or pressure"
	    exit 11
	 endif
	 # If we're doing the enkf analysies (enkf_solver), but assimOrEval == eval, we don't want to use it in the 
	 #  analysis so don't include the ob in the YAML file. For prior forward operators calculations, always
	 #  include the ob in the YAML.
	 if ( $JEDI_ANALYSIS_TYPE != enkf_solver || ($JEDI_ANALYSIS_TYPE == enkf_solver && $assimOrEval == assim) ) then
	    if ( $hloc > $max_hloc ) setenv max_hloc $hloc # largest horiz. localization, for EnKF obs distribution
	    ${JEDI_YAML_PLUGS}/${inst}.yaml.csh $obs_yaml $JEDI_RUN_DIR   # 'execute' the file to fill-in variables and add to $obs_yaml
	    # add localization yaml.csh
	    rm -f ./localization.yaml
	    if ( $JEDI_ANALYSIS_TYPE =~ *enkf* ) then
	       ${JEDI_YAML_PLUGS}/obsSpaceLocalization.yaml.csh ./localization.yaml $JEDI_RUN_DIR
	       sed -i "s/^/  /" ./localization.yaml # add 2 spaces at the start of each line
	       cat ./localization.yaml >> $obs_yaml
	    endif
	 endif
	 @ ob ++ 
	#set obs_str = "${obs_str}'${inst}',"

	 # if $channels is NOT -1, it's a radiance ob
	 if ( $channels != -1 ) set radiance_str = "${radiance_str}'${inst}',"

	 # If radiance, and we're doing bias correction, look for files at the last cycle, defined by $VARBC_CYCLE_PERIOD,
	 # but if not there, keep going back in time until $MAX_VARBC_CYCLE is met
	 if ( $channels != -1 && $varBC =~ "*T*" ) then

	    set found_it = false

	    foreach offset ( `seq $VARBC_CYCLE_PERIOD 1 $MAX_VARBC_CYCLE` ) # e.g., seq 60 1 1440
	       setenv PREV_DATE_VARBC `${TOOL_DIR}/da_advance_time.exe ${DATE} -${offset}m -f ccyymmddhhnn`
	       set possible_dirs = ( ${EXP_DIR_TOP}/${PREV_DATE_VARBC}/envar  \
				     ${EXP_DIR_TOP}/${PREV_DATE_VARBC}/enkf   \
				     ${EXP_DIR_TOP}/${PREV_DATE_VARBC}/jedi_ens_mean )
	       foreach LAST_RAD_BC_DIR ( $possible_dirs )
		  @ n = 0
		  if ( -e   ${LAST_RAD_BC_DIR}/satbias_${inst}_out.h5 ) then
		     ln -sf ${LAST_RAD_BC_DIR}/satbias_${inst}_out.h5  ./satbias_${inst}.h5
		     @ n ++
		  endif
		  if ( $use_static_bias_correction_covariance =~ *true* || $use_static_bias_correction_covariance =~ *TRUE* ) then
		     set bias_covariance_dir = $STATIC_BC_DIR
		  else
		     set bias_covariance_dir = $LAST_RAD_BC_DIR
		  endif
		  if ( -e   ${bias_covariance_dir}/satbias_cov_${inst}_out.h5 ) then
		     ln -sf ${bias_covariance_dir}/satbias_cov_${inst}_out.h5 ./satbias_cov_${inst}.h5
		     @ n ++
		  endif
		  # For each sensor, we have a file for bias correction and preconditioning
		  # So that's why we look for 2 files
		  if ( $n == 2 ) then
		     set found_it = true
		     break 2 # break 2 means get out of 2 levels of loops
		  endif
	       end # loop for LAST_RAD_BC_DIR
	    end # loop for offset
	    if ( $found_it == false ) then
	       echo "Missing satbias_out file for ${inst}.  Exit"
	       touch -f ./MISSING_BIAS_CORRECTION
	       exit 9
	    endif

	    # Link lapse rate files needed for MPAS-JEDI
	    ln -sf ${TLAP_DIR}/*tlapmean.txt .

	 endif #end if if radiance
      endif # end if file existence
   end # end loop over number of instruments in the $OBS_INFO_FILE

   if ( $ob == 0 ) then
      echo "all obs files in ${THIS_OB_DIR} are missing. exit"
      echo "Check $THIS_OB_DIR" > ./MISSING_OBS
      exit 11
   endif
endif

#-----------------------------------------------------
# Make MPAS streams file, and link proper backgrounds.
#   Output is always ./streams.atmosphere for streams
#-----------------------------------------------------
if ( $JEDI_ANALYSIS_TYPE == bump ) then
   setenv input_file         $det_background      #needs to be at correct time, but just grid info used
   setenv input_invariant_file  ./invariant_deterministic.nc
   $STREAMS_TEMPLATE   mpas_jedi $JEDI_RUN_DIR # output is ./streams.atmosphere
else if ( $JEDI_ANALYSIS_TYPE == envar ) then
   # For envar, need two streams files
   #  one for determinsitic background, the other for ensemble
   # The two can be the same ...
   #  ... but having two will facilitate dual-res applications

   # Define the background (./bg.${mpas_date}.nc)
   ln -sf $det_background ./bg.${mpas_date}.nc

   # Copy the background to the analysis ; we'll overwrite the analysis
   cp $det_background ./analysis.${mpas_date}.nc # the analysis

   # First the high-res deterministic background at analysis time
   setenv input_file         ./bg.${mpas_date}.nc     # name matches that in YAML file (cost function.background.filename)
   setenv input_invariant_file  ./invariant_deterministic.nc
   $STREAMS_TEMPLATE mpas_jedi $JEDI_RUN_DIR
   mv ./streams.atmosphere ./streams.atmosphere_deterministic

   # Now the ensemble perturbations for background error covariances
   setenv input_file         ./mpas_en001.nc #needs to be at correct time, but just grid info used
   setenv input_invariant_file  ./invariant_ens.nc
   $STREAMS_TEMPLATE mpas_jedi $JEDI_RUN_DIR
   mv ./streams.atmosphere ./streams.atmosphere_ens

else
   setenv input_file         ./mpas_en001.nc #needs to be at correct time, but just grid info used
   setenv input_invariant_file  ./invariant_ens.nc
   $STREAMS_TEMPLATE mpas_jedi $JEDI_RUN_DIR # Streams file
   mv ./streams.atmosphere ./streams.atmosphere_ens
endif

#------------------------------------------------------
# Add stuff to YAML files, and then concatenate
#------------------------------------------------------
set full_yaml_file = ./input.yaml
rm -f $full_yaml_file

# All JEDI applications get the same common block
if ( $MPAS_REGIONAL =~ *true* || $MPAS_REGIONAL =~ *TRUE* ) then
   setenv reduce_obs_space   regionalReduceObsSpace
else
   setenv reduce_obs_space   globalReduceObsSpace
endif
if ( $JEDI_ANALYSIS_TYPE == enkf_solver ) then
   setenv obsDistribution  HaloDistribution
else
   setenv obsDistribution  RoundRobinDistribution # in common.yaml.csh, so we need, but maybe only used for EnKF...
endif

${JEDI_YAML_PLUGS}/common.yaml.csh $full_yaml_file $JEDI_RUN_DIR

if ( $JEDI_ANALYSIS_TYPE == bump ) then
   rm -f $full_yaml_file # no need for the common block
   setenv corrlength_meters `echo "$corrlength_model_space * 1000" | bc` # needed for yaml
   ${JEDI_YAML_PLUGS}/bump.yaml.csh $full_yaml_file $JEDI_RUN_DIR
else if ( $JEDI_ANALYSIS_TYPE == envar ) then
   # each of the following yaml.csh files will be filled with the specified
   # environmental variables. 'exeucting' these files
   # appends the templates to $1 that is input
   ${JEDI_YAML_PLUGS}/variational.yaml.csh $full_yaml_file $JEDI_RUN_DIR
   echo "  observations:" >> $full_yaml_file # note the 2 spaces at the start of the string
   echo "    obs perturbations: false"  >> $full_yaml_file # note the 4 spaces at the start of the string
   echo "    observers:"  >> $full_yaml_file # note the 4 spaces at the start of the string
   sed -i "s/^/    /" $obs_yaml # add 4 spaces at the start of each line for the observations
   cat $obs_yaml >> $full_yaml_file # add observations to $full_yaml_file

else if ( $JEDI_ANALYSIS_TYPE =~ *enkf* ) then
   if ( $JEDI_ANALYSIS_TYPE =~ *enkf_prior* ) then
      setenv letkf_stage  asObserver
      setenv SaveSingleMember true

      if ( $JEDI_ANALYSIS_TYPE == enkf_prior_mean ) then
	 setenv SingleMemberNumber 0
	 setenv enkf_type LETKF # force LETKF analysis for prior mean to not produce H(x) for modulated members
      else if ( $JEDI_ANALYSIS_TYPE == enkf_prior_members ) then
	 setenv SingleMemberNumber $member
      endif
   else if ( $JEDI_ANALYSIS_TYPE == enkf_solver ) then
      setenv letkf_stage  asSolver
      setenv SaveSingleMember false
      setenv SingleMemberNumber 0 # shouldn't matter
   else if ( $JEDI_ANALYSIS_TYPE == enkf_all_at_once ) then
      setenv letkf_stage  asObserver
      setenv SaveSingleMember false
      setenv SingleMemberNumber 0 # shouldn't matter
   endif
   ${JEDI_YAML_PLUGS}/enkf.yaml.csh $full_yaml_file $JEDI_RUN_DIR
   echo "observations:" >> $full_yaml_file 
   echo "  observers:"  >> $full_yaml_file # note the 2 spaces at the start of the string
   sed -i "s/^/  /" $obs_yaml # add 2 spaces at the start of each line for the observations
   cat $obs_yaml >> $full_yaml_file # add observations to $full_yaml_file

   if ( $JEDI_ANALYSIS_TYPE == enkf_solver ) then
      sed -i "s/*ObsDataIn/*ObsDataOut/g" $full_yaml_file
      sed -i '/ obsdataout/d' $full_yaml_file # note the space in front of obsdata out; this deletes the whole line
   endif

   #sed -i "1,2 s/^/  /" ./input.yaml_${stage} # add 2 spaces before each line in lines 1 and 2
   #sed -i "3,${nlines} s/^/    /" ./input.yaml_${stage} # add 4 spaces before each line starting in line 3
else
   echo "need to add YAML for $JEDI_ANALYSIS_TYPE"
   exit
endif

#------------------------------------
# Make MPAS namelist file
#------------------------------------
setenv config_do_DAcycling  .true.
if ( $use_2stream_IO =~ *true* || $use_2stream_IO =~ *TRUE* ) then
   setenv mpas_restart  .false.    
else
   setenv mpas_restart  .true.    
endif
setenv update_sst .false. # MPAS-JEDI doesn't care about SST update, so force this to false so MPAS-JEDI doesn't 
			  #   try to read a surface "input" stream
# For BUMP, we just need the invariant.nc and init.nc file, so force mpas_restart to .false.
if ( $JEDI_ANALYSIS_TYPE == bump ) setenv mpas_restart  .false.

$NAMELIST_TEMPLATE mpas $JEDI_RUN_DIR # Output is ./namelist.atmosphere; need to append one more part for MPAS-JEDI applications
cat >> ./namelist.atmosphere << EOF2
&assimilation
   config_jedi_da = true
/
EOF2

mv ./namelist.atmosphere ./namelist.atmosphere_${DATE} # MPAS-JEDI doesn't like files named ./namelist.atmosphere...it will make it itself
  
# We need two namelists for envar in-case dual-res
# When we filled the first namelist, it was for the determinisitic mesh
# So now make a namelist for the ensemble mesh
# We also need the graph_info_prefx files for the ensemble
if ( $JEDI_ANALYSIS_TYPE == envar ) then
   mv ./namelist.atmosphere_${DATE} ./namelist.atmosphere_${DATE}_deterministic
   ln -sf ${grid_info_dir_ens}/${graph_info_prefx_ens}* .
   setenv time_step $time_step_ens
   setenv config_len_disp $config_len_disp_ens
   setenv radiation_frequency $radiation_frequency_ens
   setenv graph_info_prefx     $graph_info_prefx_ens
   $NAMELIST_TEMPLATE mpas $JEDI_RUN_DIR # Output is ./namelist.atmosphere; need to append one more part for MPAS-JEDI applications
   cat >> ./namelist.atmosphere << EOF3
&assimilation
   config_jedi_da = true
/
EOF3
   mv ./namelist.atmosphere ./namelist.atmosphere_${DATE}_ens # MPAS-JEDI doesn't like files named ./namelist.atmosphere...it will make it itself
endif

#------------------------------------------------------------------
# Make namelist for program to concatenate all JEDI/UFO output files 
# from individual processors into one file
# Helpful to do up here, so we can call the program in multiple places
#  If you want to remove the final comma: echo "$string" | sed -e "s/  /,/g"
#obs_platforms = ${conv_sensor_str} !'gnssro',${radiance_sensor_str}
#obs_platforms = 'sondes','aircraft','satwind','gnssro','sfc',${radiance_sensor_str}
#------------------------------------------------------------------
if ( $radiance_str != "" ) then
   ln -sf $NETCDF_CONCATENATE_EXEC .
   foreach prefx ( geovals ydiag )
      rm -f ./input_${prefx}.nml
      cat > ./input_${prefx}.nml << EOF4
&share
obspath = '${jedi_output_dir}'
obs_platforms = ${radiance_str}
output_path = '${jedi_output_dir}'
fname_prefx = '${prefx}'
/
EOF4
   end
endif

#---------------
# Run MPAS-JEDI
#---------------
ln -sf $jedi_environment_file .  # link to keep a record
source $jedi_environment_file
#limit stacksize unlimited
setenv OOPS_TRACE 0
setenv OOPS_DEBUG 0
setenv OMP_NUM_THREADS 1
setenv FI_CXI_RX_MATCH_MODE 'hybrid'
setenv GFORTRAN_CONVERT_UNIT 'big_endian:101-200' # needed for gfortran compiler
setenv F_UFMTENDIAN 'big:101-200' # maybe needed for intel compiler
if ( $?mpasjedi_library_path ) setenv LD_LIBRARY_PATH ${mpasjedi_library_path}:$LD_LIBRARY_PATH # need path of library on derecho

# cd again to $JEDI_RUN_DIR; under some strange conditions, probably a combination
# of job arrays on derecho, and possible use of 'pwd' in $mpas_environment_file
# (if $mpas_environment_file ==> jedi_environment), things can end up in the
# wrong directory. pretty strange, but just do it.
cd $JEDI_RUN_DIR  # The working directory 

# Find proper exectuable.  Could be in a few places.
set exec = `find $MPAS_JEDI_BUNDLE_DIR -name $jedi_exec`
ln -sf $exec .

if ( $JEDI_ANALYSIS_TYPE =~ *enkf_prior* ) then
   # first run EnKF in "observer" mode
   mv $full_yaml_file ./observer.yaml

   if ( $JEDI_ANALYSIS_TYPE == enkf_prior_members ) then
      sed -i '/Gaussian Thinning/{N;d;}' ./observer.yaml
   endif

   $run_cmd_jedi -n $jedi_enkf_num_procs_observer -ppn $jedi_enkf_num_procs_per_node_observer $jedi_exec ./observer.yaml  ./observer.log &
   set pid = $!

   # When running many instances of MPAS-JEDI simultaneously, sometimes it hangs, so check for completion in log file
   # and move on if it's actually done, potentially killing things.
   echo "$pid" > ./waiting
   while ( 1 == 1 )
      if ( ( `grep "Finishing oops::LocalEnsembleDA<MPAS, UFO and IODA observations> with status = 0" ./observer.log | wc -l` == 1 ) || \
           ( `grep "OOPS Ending" ./observer.log | wc -l` == 1 )  || \
           ( `grep "Timing Statistics" ./observer.log | wc -l` == 1 ) ) then
         rm -f ./waiting
	 if ( `ps | grep $pid | wc -l` == 1 ) kill -9 $pid 
         break
      else
         sleep 5
      endif
   end

   # Done running MPAS-JEDI, so source our main environment
   source $default_environment_file # From driver
   unsetenv GFORTRAN_CONVERT_UNIT F_UFMTENDIAN  OMP_NUM_THREADS
   module load conda/latest
   conda activate npl

   if ( $JEDI_ANALYSIS_TYPE == enkf_prior_mean ) then
      foreach inst ( $instruments )
	 set fname1 = ${jedi_output_dir}/obsout_omb_${inst}.h5
	 if ( -e $fname1 ) then
	    set fname  = ${jedi_output_dir}/obsout_omb_${inst}_1st_pass.h5

	   #Either use the next 5 lines...
	   #ncks -O --no_abc $fname1 $fname # change the format to make IODA-v3 file netCDF4-compliant
	   #ncrename -g "PreQC,PreQC_original"         $fname
	   #ncrename -g "EffectiveQC0","PreQC"         $fname
	   #ncrename -g "ObsError","ObsError_original" $fname
	   #ncrename -g "EffectiveError0","ObsError"   $fname
	   
	   # ... or this line, which requires NOT resetting PreQC_maxvalue to 0
	    python $THINNING_HofX_EXEC --thinning 1 --rundir $jedi_output_dir --hofxfile obsout_omb_${inst}.h5 --outfile obsout_omb_${inst}_1st_pass.h5

	    # Link updated files to working directory for 2nd pass through ensemble mean prior
	    mv ./${inst}_obs_${DATE}.h5 ./${inst}_obs_${DATE}_orig.h5
	    ln -sf $fname ./${inst}_obs_${DATE}.h5
	 endif
      end
      deactivate npl

      # Need to run JEDI again, using the files we just produced as our OBSERVATION files
      # The ensemble member files will use these files as observations, so we also need to use them for the ensemble mean
      # to ensure all observations are processed in the same order.  
      # We also enforce a stricter quality control for the PreQC filter for this second pass, to mimic the setting for the members
      cp observer.yaml observer.yaml_1st_pass
     #sed -i "/PreQC/{n;s/${PreQC_maxvalue}/0/}" observer.yaml # replaces the line after PreQC; $PreQC_maxvalue -->0 (set PreQC to 0)
      # See https://stackoverflow.com/questions/64842342/bash-sed-replace-line-in-file-at-same-indentation-level
      #   this is to replace the line after Background Check at the same indentation level with threshold: 999999
      sed -i '/Background Check/{n;s/^\( *\).*/\1threshold: 999999/}' observer.yaml
      sed -i '/Gaussian Thinning/{N;d;}' observer.yaml
     #sed -i "s/.*save single member for observer.*/  save single member for observer: false/g" ./observer.yaml # disable single member to compute H(x) for all members (note 2 spaces at start)

      # Run MPAS-JEDI again
      source $jedi_environment_file
      #limit stacksize unlimited
      setenv OOPS_TRACE 0
      setenv OOPS_DEBUG 0
      setenv OMP_NUM_THREADS 1
      setenv GFORTRAN_CONVERT_UNIT 'big_endian:101-200' # needed for gfortran compiler
      setenv F_UFMTENDIAN 'big:101-200' # maybe needed for intel compiler
      if ( $?mpasjedi_library_path ) setenv LD_LIBRARY_PATH ${mpasjedi_library_path}:$LD_LIBRARY_PATH # need path of library on derecho

      $run_cmd_jedi -n $jedi_enkf_num_procs_observer -ppn $jedi_enkf_num_procs_per_node_observer $jedi_exec ./observer.yaml  ./observer.log_again

      # we need to change the format of the obsout_omb files so we can use ncks on them later
      source $default_environment_file # From driver
      unsetenv GFORTRAN_CONVERT_UNIT F_UFMTENDIAN  OMP_NUM_THREADS
      foreach inst ( $instruments )
	 set fname1 = ${jedi_output_dir}/obsout_omb_${inst}.h5
	 if ( -e $fname1 ) then
	    set fname  = ./tmp.h5
	    ncks -O --no_abc $fname1 $fname # change the format to make IODA-v3 file netCDF4-compliant
	    mv $fname $fname1
	 endif
      end
   endif # endif JEDI_ANALYSIS_TYPE == enkf_prior_mean

   if ( $JEDI_ANALYSIS_TYPE == enkf_prior_members ) then
      foreach inst ( $instruments )
	 set fname1 = ${jedi_output_dir}/obsout_omb_${inst}.h5
	 if ( -e $fname1 ) then
	    set fname = ./tmp.h5
	    ncks -O --no_abc $fname1 $fname # change the format to make IODA-v3 file netCDF4-compliant
	    set groups = `ncdump -h $fname | grep group: | grep -E hofxm\|hofx0 | cut -d " " -f2` # returns hofxm0* hofx0* as array
	    set ncks_str = `echo $groups | sed -e "s/ /,/g"` # replaces all the spaces with a comma (e.g., hofx0_1,hofxm0_10_1)
	    ncks -O --no_abc -C -g $ncks_str $fname ${jedi_output_dir}/obsout_omb_${inst}_processed.h5
	 endif
      end
   endif

else if ( $JEDI_ANALYSIS_TYPE == enkf_solver ) then

  #$JEDI_YAML_TEMPLATE enkf $JEDI_RUN_DIR
   mv $full_yaml_file ./solver.yaml
   $run_cmd_jedi -n $jedi_enkf_num_procs_solver -ppn $jedi_enkf_num_procs_per_node_solver $jedi_exec ./solver.yaml  ./solver.log 
   if ( $status != 0 ) then
      echo "EnKF solver failed with status = ${status}" >> FAIL
      exit 13
   endif

   # now run EnKF to get OMA statistics
   # all we need to do is run LETKF again in observer mode, but point to the analysis files
   # also need to put the output in a unique directory
   if ( $do_oma =~ *true* || $do_oma =~ *TRUE* ) then
      set omaDir = ./dbAna
      mkdir -p $omaDir
     #cp ./observer.yaml ./oma.yaml
      cp ${EXP_DIR_TOP}/${DATE}/enkf/ens_mean/observer.yaml ./oma.yaml
      # Replace {jedi_output_dir}/obsout_omb with ${omaDir}/obsout_oma; use "|" as sed delimiter because of "/" characters in strings
      # Also replace jedi_output_dir with $omaDir for geovals and ydiag files for radiances
      sed -i "s|${jedi_output_dir}/obsout_omb|${omaDir}/obsout_oma|g" oma.yaml
      sed -i "s|${jedi_output_dir}|${omaDir}|g" oma.yaml

      rm -f ./mpas_en001.nc
      ln -sf ${EXP_DIR_TOP}/${DATE}/mpas_prior_ensmean.nc ./mpas_en001.nc

#     @ ie = 1
#     while ( $ie <= $ENS_SIZE )
      #  set m3 = `printf %03d $ie` # Each member must have three digits (i.e., 001, 010, 100)
      #  mv ./mpas_en${m3}.nc ./mpas_bak${m3}.nc # rename the background files
      #  ln -sf ./analysis.${mpas_date}_en${m3}.nc ./mpas_en${m3}.nc # YAML looks for ./mpas_en${m3}.nc
      #  @ ie ++
     #end
      $run_cmd_jedi -n $jedi_enkf_num_procs_observer -ppn $jedi_enkf_num_procs_per_node_observer $jedi_exec ./oma.yaml  ./oma.log 
   endif

else if ( $JEDI_ANALYSIS_TYPE == enkf_all_at_once ) then
   # first run EnKF in "observer" mode
   mv $full_yaml_file ./observer.yaml

   $run_cmd_jedi -n $jedi_enkf_num_procs_observer -ppn $jedi_enkf_num_procs_per_node_observer $jedi_exec ./observer.yaml  ./observer.log
   if ( $status != 0 ) then
      echo "EnKF observer failed with status = ${status}" >> FAIL
      exit 12
   endif

   # now run EnKF in "solver" mode
   # we need to change some YAML variables. Easiest way is to just change what we
   # already have (./observer.yaml) usings sed, since changes are minimal
   cp ./observer.yaml ./solver.yaml
   sed -i "s/*asObserver/*asSolver/g"  ./solver.yaml
   sed -i "s/*RoundRobinDistribution/*HaloDistribution/g" ./solver.yaml
   sed -i "s/*ObsDataIn/*ObsDataOut/g" ./solver.yaml
   sed -i '/ obsdataout/d' ./solver.yaml # note the space in front of obsdata out; this deletes the whole line

   $run_cmd_jedi -n $jedi_enkf_num_procs_solver -ppn $jedi_enkf_num_procs_per_node_solver $jedi_exec ./solver.yaml  ./solver.log 
   if ( $status != 0 ) then
      echo "EnKF solver failed with status = ${status}" >> FAIL
      exit 13
   endif

   # now run EnKF to get OMA statistics
   # all we need to do is run LETKF again in observer mode, but point to the analysis files
   # also need to put the output in a unique directory

else # envar, bump
   $run_cmd_jedi -n $jedi_variational_num_procs -ppn $jedi_variational_num_procs_per_node $jedi_exec $full_yaml_file  ./da.log 
endif
#$run_cmd_jedi ${jedi_exec} ./input.yaml  ./da.log

if ( $status != 0 ) then
   echo "JEDI FAILED with status = ${status}" >> FAIL
   exit 13
endif

if ( $JEDI_ANALYSIS_TYPE == bump ) exit # no need to go any farther if this is for BUMP

# Done running MPAS-JEDI, so source our main environment
source $default_environment_file # From driver
unsetenv GFORTRAN_CONVERT_UNIT F_UFMTENDIAN  OMP_NUM_THREADS

#-------------------------------
# JEDI has run. Deal with output
#-------------------------------

# Run concatenation program.  Output is obsout_omb_${platform}_all.nc4/h5 (e.g., obsout_omb_sondes_all.nc4/h5)
#  Can also use "./netcdf-concat" program through jedi rapids  (possibly in /glade/u/home/schwartz/.local/bin/netcdf-concat)
#if ( `grep -i "create_multiple_files_" ./da.log | wc -l` > 0 ) then # possible that just one file was made...if so, no need to concatenate
# touch -f ./JEDI_INTERNAL_CONCATENATION
#if ( 1 == 2 ) then # strange things happening, and not correct; number of procs should depend on JEDI application
if ( $radiance_str != "" ) then
   foreach prefx ( geovals ydiag )
      ln -sf ./input_${prefx}.nml ./input.nml # program looks for ./input.nml
      $run_cmd -n $jedi_enkf_num_procs_observer -ppn $jedi_enkf_num_procs_per_node_observer $NETCDF_CONCATENATE_EXEC > ./concatenate_netcdf_${prefx}.log
      if ( `grep -i "All done" ./concatenate_netcdf_${prefx}.log | wc -l` != 1 ) then
	 touch -f ./CONCATENATE_FAILED_${prefx}
       # exit 14
      else
         rm -f ${jedi_output_dir}/${prefx}*_????.nc4
         rm -f ${jedi_output_dir}/${prefx}*_????.h5
      endif
   end
endif
#endif

# We might not be using bias correction for abi_16
#   But these output files still need to be there 
#   so the next cycle finds "bias correction files" and doesn't fail
if ( $JEDI_ANALYSIS_TYPE == envar ) then
   if ( ! -e satbias_abi_g16_out.h5 )      touch -f satbias_abi_g16_out.h5
   if ( ! -e satbias_cov_abi_g16_out.h5 )  touch -f satbias_cov_abi_g16_out.h5
endif

#---------
# clean up
#---------
if ( $JEDI_ANALYSIS_TYPE == forward_operator_for_forecast_verif ) then
   rm -f ${file_type}.${valid_time_mpas}.nc
   rm -f ${jedi_output_dir}/*_????.nc4 # keep the "all" files
   rm -f ${jedi_output_dir}/*_????.h5 # keep the "all" files
endif

rm -f ./observer.log*.*  ./oma.log*.*  ./solver.log*.*
rm -f ./core*
rm -f ./*.lock
rm -f ./fort.* # BUMP files that might be there

touch -f ./ALL_DONE

exit 0
