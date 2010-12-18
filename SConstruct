import os

path = ['D:\\Code\\D\\dmd_git\\install\\bin']

env = DefaultEnvironment(tools = ['dmd', 'link'], ENV={'PATH':path})

if ARGUMENTS.get('release', ''):
    _build_style='release'
    _dflags = ['-O', '-release', '-inline']
else:
    _build_style='debug'
    _dflags=['-debug', '-unittest', '-g']

_version_flags=ARGUMENTS.get('version', '')
if _version_flags:
   for flag in _version_flags.split(','):
       _dflags.append('-version=' + flag)

if ARGUMENTS.get('profile', ''):
   _dflags.append('-profile')

if ARGUMENTS.get('cov', ''):
   _dflags.append('-cov')

env.Append(DFLAGS=_dflags)
env.Append(BUILD_STYLE=_build_style)

qcheck_imp = Dir('../quickCheck/src')
qcheck_lib = File('../quickCheck/build/quickcheck/'+_build_style+'/qcheck.lib')

ut_runner = File('../site-packages/unittestrunner.d')
skia_lib = env.SConscript('src/skia/SConscript', duplicate=0,
                          exports='env',
                          variant_dir='build/skia/'+_build_style)
env.SConscript('src/SampleApp/SConscript', duplicate=0,
               exports='env skia_lib qcheck_lib qcheck_imp',
               variant_dir='build/SampleApp/'+_build_style)
env.SConscript('src/QuickCheck/SConscript', duplicate=0,
               exports='env skia_lib qcheck_lib qcheck_imp',
               variant_dir='build/QuickCheck/'+_build_style)
env.SConscript('src/Benchmark/SConscript', duplicate=0,
               exports='env skia_lib',
               variant_dir='build/Benchmark/'+_build_style)

