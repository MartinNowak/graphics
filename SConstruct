import os

path = ['D:\\Code\\D\\dmd_git\\install\\bin']

env = DefaultEnvironment(tools = ['dmd', 'link'], ENV={'PATH':path})

if ARGUMENTS.get('release', ''):
    _build_style='release'
    env.Append(DFLAGS=['-O', '-release', '-inline'])
else:
    _build_style='debug'
    env.Append(DFLAGS=['-debug', '-unittest', '-gc'])

env.Append(BUILD_STYLE=_build_style)

skia_lib = env.SConscript('src/skia/SConscript', duplicate=0,
                          exports='env',
                          variant_dir='build/skia/'+_build_style)
app = env.SConscript('src/SampleApp/SConscript', duplicate=0,
                     exports='env skia_lib',
                     variant_dir='build/SampleApp/'+_build_style)
