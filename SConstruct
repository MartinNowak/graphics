import os

env = DefaultEnvironment(tools=['dmd', 'link', 'gcc', 'ar'])

if ARGUMENTS.get('release', ''):
    _build_style='release'
    _dflags = ['-O', '-release', '-inline', '-gc']
else:
    _build_style='debug'
    _dflags=['-debug', '-unittest', '-gc']

_version_flags=ARGUMENTS.get('version', '')
if _version_flags:
   for flag in _version_flags.split(','):
       _dflags.append('-version=' + flag)
       _build_style+='_'+flag

if ARGUMENTS.get('profile', ''):
   _dflags.append('-profile')
   _build_style+='_profile'

if ARGUMENTS.get('cov', ''):
   _dflags.append('-cov')
   _build_style+='_cov'

#Scons dmd tool is broken, so define to be linked libs here
_d_link_flags=['-lphobos2', '-lpthread', '-lm']

if ARGUMENTS.get('m64', ''):
   _dflags.append('-m64')
   _link_flags = ['-m64']
   _build_style+='_64'
else:
   _dflags.append('-m32')
   _link_flags = ['-m32']
   _build_style+='_32'

env.Append(DFLAGS=_dflags, LINKFLAGS=_link_flags,
                           DLINKFLAGS=_d_link_flags, BUILD_STYLE=_build_style)

qcheck_imp = Dir('../quickCheck/src')
qcheck_lib = File('../quickCheck/build/quickcheck/'+_build_style+'/libqcheck.a')

ut_runner = File('../site-packages/unittestrunner.d')
x_lib_bundle = env.SConscript('src/X11/SConscript', duplicate=0,
                          exports='env',
                          variant_dir='build/X11/'+_build_style)
skia_lib = env.SConscript('src/skia/SConscript', duplicate=0,
                          exports='env',
                          variant_dir='build/skia/'+_build_style)
env.SConscript('src/SampleApp/SConscript', duplicate=0,
               exports='env skia_lib qcheck_lib qcheck_imp x_lib_bundle',
               variant_dir='build/SampleApp/'+_build_style)
env.SConscript('src/QuickCheck/SConscript', duplicate=0,
               exports='env skia_lib qcheck_lib qcheck_imp',
               variant_dir='build/QuickCheck/'+_build_style)
env.SConscript('src/benchmark/SConscript', duplicate=0,
               exports='env skia_lib qcheck_lib qcheck_imp',
               variant_dir='build/benchmark/'+_build_style)
