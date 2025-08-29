import os, sys
import getopt
import numpy as np
import netCDF4 as nc4

#============================================================================

def calc_dimensions(ncin, ncout):
  # Calculate how many locations are not thinned.
  igroups = ncin.groups
  for grpname, group in igroups.items():
    if(grpname == "EffectiveQC0"):
      variables = list(group.variables.items())
      varname, qc_var = variables[0]
      if len(qc_var.shape) == 2:
        valid_indices = np.where(np.any(qc_var[:, 0:] == 0, axis=1))[0]
      else:
        qc_var_2d = []
        for varname, qc_var in variables:
          qc_var = np.expand_dims(qc_var, axis=1)
          qc_var_2d.append((varname, qc_var))
        qc_var = np.concatenate([var[1] for var in qc_var_2d], axis=1)
        valid_indices = np.where(np.any(qc_var[:, 0:] == 0, axis=1))[0]

  # Determine number of thinned data
  new_locs = len(valid_indices)
  print('thinned data has size: %d\n' %(new_locs))
 
 #diminfo = {}
  for name, dimension in ncin.dimensions.items():
    print('dimension: %s has size: %d\n' %(name, dimension.size))

    if (name == "Location" and thinning == 1):
     #old_locs = dimension.size
     #diminfo[name] = new_locs
      ncout.createDimension(name, new_locs)
    else:
     #diminfo[name] = dimension.size
      ncout.createDimension(name, dimension.size)

    print('Create dimension: %s, no. dim: %d\n' %(name, len(dimension)))

#-----------------------------------------------------------------------------------------
def copy_attributes(ncin, ncout):
  inattrs = ncin.ncattrs()
  for attr in inattrs:
    if ('_FillValue' != attr):
      attr_value = ncin.getncattr(attr)
      if isinstance(attr_value, str):
        ncout.setncattr_string(attr, attr_value)
      else:
        ncout.setncattr(attr, attr_value)

#-----------------------------------------------------------------------------------------
def create_var_in_group(ingroup, outgroup):
  copy_attributes(ingroup, outgroup) # copy global attributes

  fvname = '_FillValue'
  vardict = {}

 #create all var in group.
  for varname, variable in ingroup.variables.items():
    if(fvname in variable.__dict__):
      fill_value = variable.getncattr(fvname)
      if isinstance(fill_value, np.int32):
        fill_value = 999999999
      elif isinstance(fill_value, np.float32):
        fill_value = 999999999.0
      if('stationIdentification' == varname):
        print('\n\nHandle variable: %s\n' %(varname))
        print('\tvariable dtype: %s\n' %(variable.dtype))
        print('\tvariable size: %d\n' %(variable.size))
        print('\tvariable datatype: %s\n' %(variable.datatype))
        print('\tvariable dimensions: %s\n' %(variable.dimensions))
        print('\tAvoid create string variable for now.\n')

        strdims = ('Location', 'Channel')

        newvar = None
      else:
        newvar = outgroup.createVariable(varname, variable.datatype, variable.dimensions,
                                         fill_value=fill_value)
    else:
      newvar = outgroup.createVariable(varname, variable.datatype, variable.dimensions)

    copy_attributes(variable, newvar)

    print('\tcreate var: %s with %d dimension\n' %(varname, len(variable.dimensions)))

    vardict[varname] = newvar

  return vardict

#-----------------------------------------------------------------------------------------
def write_var(var, dim, varname, ingroup):
  variable = ingroup.variables[varname]

  print('\n\nPrepare to write variable: %s\n' %(varname))
  print('\tvariable dtype: %s\n' %(variable.dtype))
  print('\tvariable size: %d\n' %(variable.size))
  print('\tvariable dim: %d, %d\n' %(dim, len(variable.dimensions)))

  if (1 == dim and 'stationIdentification' == varname):
    print('\nskip write variable: %s\n' %(varname))
  else:
    write_var_reduce(var, variable)
    
  print('\nFinished write variable: %s\n' %(varname))

#-----------------------------------------------------------------------------------------
def write_var_in_group(ingroup, vardict):

 #write all var in group.
  for varname in vardict.keys():
    var = vardict[varname]
    if (varname == 'stationIdentification'):
      dim = 1
    else:
      dim = len(var.dimensions)
    write_var(var, dim, varname, ingroup)

#-----------------------------------------------------------------------------------------
def write_var_reduce(varin, varout):
  varin_length  = varin.shape[0]  if len(varin.shape)  >= 1 else 1
  varout_length = varout.shape[0] if len(varout.shape) >= 1 else 1
  
  if len(varin.shape) == 1:
    if (varin_length == self.new_locs and self.thinning == 1):
      varin[:varin_length] = varout[self.valid_indices]
    else:
      varin[:varin_length] = varout[:varin_length]

  elif len(varin.shape) == 2:
    if (varin.shape[0] == self.new_locs and self.thinning == 1):
      varin[:varin_length, :] = varout[self.valid_indices, :]
    else:
      varin[:varin_length, :] = varout[:varin_length, :]

  elif len(varin.shape) == 3:
    if (varin.shape[0] == self.new_locs and self.thinning == 1):
      varin[:varin_length, :, :] = varout[self.valid_indices, :, :]
    else:
      varin[:varin_length, :, :] = varout[:varin_length, :, :]

#-----------------------------------------------------------------------------------------

#=========================================================================================

# set defaults
  debug = 0
  rundir = '.'
  hofxfile = 'obsout_da_amsua_n19.h5'
  outfile = 'new_obsout_da_amsua_n19.h5'
 #--------------------------------------------------------------------------------
  opts, args = getopt.getopt(sys.argv[1:], '', ['debug=','thinning=', 'rundir=', 'hofxfile=', 'outfile='])

  for o, a in opts:
    if o in ('--debug'):
      debug = int(a)
    elif o in ('--thinning'):
      thinning = int(a)
    elif o in ('--rundir'):
      rundir = a
    elif o in ('--hofxfile'):
      hofxfile = a
    elif o in ('--outfile'):
      outfile = a
    else:
      print('o: <%s>' %(o))
      print('a: <%s>' %(a))
      assert False, 'unhandled option'

 #--------------------------------------------------------------------------------

    hofxfile = '%s/%s' %(rundir, hofxfile)
    outfile  = '%s/%s' %(rundir, outfile)

    print('hofxfile: %s\n' %(hofxfile))
    print('outfile: %s\n'  %(outfile))

    if(os.path.exists(outfile)): os.remove(outfile)

    IFILE = nc4.Dataset(hofxfile, 'r') # input file
    OFILE = nc4.Dataset(outfile, 'w', format='NETCDF4') # outputfile

    calc_dimensions(IFILE, OFILE) # figure out the number of points with appropriate QC

    rootvardict = create_var_in_group(IFILE, OFILE)

    igroups = IFILE.groups
  
    comgrps = []
    
    for grpname, group in igroups.items():
      if grpname in ["MetaData", "PreQC", "ObsError", "ObsValue", "ObsType"]:
        comgrps.append(grpname)
        OFILE.createGroup(grpname)

    # Save all group names for ogroups
    ogroups = OFILE.groups

    comdict = {}
    for grpname in comgrps:
      print('Create common group: %s\n' %(grpname))
      igroup = igroups[grpname]
      ogroup = ogroups[grpname]
      vardict = create_var_in_group(igroup, ogroup)
      comdict[grpname] = vardict

    print('write variables\n')
    write_var_in_group(IFILE, rootvardict)

    igroups = IFILE.groups
    for grpname in comgrps:
      print('write group: %s\n' %(grpname))
      group = igroups[grpname]
      write_var_in_group(group, comdict[grpname])

    IFILE.close()
    OFILE.close()

    print('Successfully generated thinned IODA files!')
