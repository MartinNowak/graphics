#! /usr/bin/env python

VERSION='0.1'
LIBNAME='skia'

top = '.'
out = 'build'


def options(opt):
	opt.load('compiler_d')

def configure(conf):
        conf.setenv('debug')
	conf.load('compiler_d')
        conf.env.LIB_FREETYPE = ['freetype']
        conf.env.LIB_PNG = ['png']
        conf.env.DFLAGS = ['-debug', '-gc', '-unittest']
        conf.check(features='d dprogram', fragment='void main() {}', compile_filename='test.d')

        conf.setenv('release')
	conf.load('compiler_d')
        conf.env.LIB_FREETYPE = ['freetype']
        conf.env.LIB_PNG = ['png']
        conf.env['DFLAGS'] = ['-release', '-O', '-inline', '-nofloat']
        conf.check(features='d dprogram', fragment='void main() {}', compile_filename='test.d')

def build(bld):
        if not bld.variant:
                bld.fatal('call "waf build_debug" or "waf build_release", and try "waf --help"')

        bld.stlib(
                source = bld.path.ant_glob('src/skia/**/*d'),
                target = 'skia',
                includes = 'src')

        bld.program(
                source = bld.path.ant_glob('tests/qcheck/**/*d'),
                target = 'qcheck',
                includes = 'src tests',
                lib = 'qcheck',
                use = 'skia')

        bld.program(
                source = bld.path.ant_glob('tests/benchmark/**/*d'),
                target = 'benchmark',
                includes = 'src tests',
                lib = 'qcheck',
                use = 'skia FREETYPE')

        bld.program(
                source = bld.path.ant_glob('examples/SampleApp/**/*d'),
                target = 'SampleApp',
                includes = 'src examples',
                lib = ['X11', 'xcb', 'Xau', 'Xdmcp', 'qcheck'],
                use = 'skia FREETYPE PNG')

from waflib.Build import BuildContext, CleanContext, \
        InstallContext, UninstallContext

for x in 'debug release'.split():
        for y in (BuildContext, CleanContext, InstallContext, UninstallContext):
                name = y.__name__.replace('Context','').lower()
                class tmp(y):
                        cmd = name + '_' + x
                        variant = x
