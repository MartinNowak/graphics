#!/usr/bin/env python
import re,os,sys

_dep_re = re.compile(r'(.+?)_DEP\s:=\s\$\$\((.+?)_LIB\)')
_deps = {}
_add_deps = {}
_cur_pkg = ''

def bail_parse_deps(lineno, line):
    print "Faulty deps.mk at line %u\n>%s" % (lineno, line)
    exit(1)

def finish(rc):
    exit(rc)

def parse_deps(content):
    lineno = 0
    for line in content.rstrip('\n\r ').split('\n'):
        lineno += 1
        if not line:
            continue
        m = _dep_re.match(line)
        if not m:
            bail_parse_deps(lineno, line)
        if not m.group(1) in _deps:
            _deps[m.group(1)] = set()
        _deps[m.group(1)].add(m.group(2))


def check_deps():
    src_path = os.path.join('src', 'skia')
    for dirpath, _, files in os.walk(src_path):
        global _cur_pkg
        _cur_pkg = os.path.basename(dirpath)
        gen = (os.path.join(dirpath, name) for name in files
               if name.endswith('.d'))
        check_file(gen)
    remove_self_deps()
    return len(_add_deps) == 0

def remove_self_deps():
    for k, v in _add_deps.iteritems():
        if k in v:
            v.remove(k)

_import_re = re.compile(r'import\s(.*);')
def test_import_re():
    _a = r'import skia.core.rect;'
    assert _import_re.search(_a)
    assert _import_re.search(_a).group(1) == 'skia.core.rect'
    _a = r' static import skia.core.rect, skia.core.bitmap ;'
    assert _import_re.search(_a)
    assert _import_re.search(_a).group(1) == 'skia.core.rect, skia.core.bitmap '
    _a = r'import skia.core.rect,\rn std.conv ;'
    assert _import_re.search(_a)
    assert _import_re.search(_a).group(1) == r'skia.core.rect,\rn std.conv '

    _a = r'import Win = core.sys.win;'
    assert _import_re.search(_a)
    assert _import_re.search(_a).group(1) == 'Win = core.sys.win'


def check_file(gen):
    for path in gen:
        with open(path) as fd:
            for m in _import_re.finditer(fd.read()):
                check_import_list(m)

def check_import_list(m):
    for imp in m.group(1).split(','):
        check_import(imp)

_module_re = re.compile(r'skia\.(.*)\.([^\s]*)')
def test__module_re():
    _a = r'import skia.core.rect '
    assert _module_re.search(_a)
    assert _module_re.search(_a).group(1) == 'core'
    assert _module_re.search(_a).group(2) == 'rect'
    _a = r'Win = \r\nskia.core.rect '
    assert _module_re.search(_a)
    assert _module_re.search(_a).group(1) == 'core'
    assert _module_re.search(_a).group(2) == 'rect'

    _a = r' skia.core.rect : Bitmap '
    assert _module_re.search(_a)
    assert _module_re.search(_a).group(1) == 'core'
    assert _module_re.search(_a).group(2) == 'rect'

def check_import(imp):
    m = _module_re.search(imp)
    if not m:
        return
    imp_pkg = m.group(1)
    if _cur_pkg == imp_pkg:
        return

    dep_known = _cur_pkg in _deps and imp_pkg in _deps[_cur_pkg]

    if not dep_known:
        if _cur_pkg in _add_deps:
            _add_deps[_cur_pkg].add(imp_pkg)
        else:
            _add_deps[_cur_pkg] = set([imp_pkg])

def rewrite_deps(fd):
    for k,v in _deps.iteritems():
        if k in _add_deps:
            _add_deps[k] = _add_deps[k].union(v)
        else:
            _add_deps[k] = v

    for k,v in _add_deps.iteritems():
        for dep in v:
            fd.write('%s_DEP := $$(%s_LIB)\n' % (k,dep))

if __name__=='__main__':
    if os.path.isfile('deps.mk'):
        with open('deps.mk', 'rb') as fd:
            parse_deps(fd.read().rstrip())

    if check_deps():
        finish(0)

    with open('deps.mk', 'wb') as fd:
        rewrite_deps(fd)
    finish(0)
