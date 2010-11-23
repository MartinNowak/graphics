#!/usr/bin/env python
import re,os,sys
import random
import logging

_dep_re = re.compile(r'(.+?)_DEP\s:=\s\$\$\((.+?)_LIB\)')
_deps = {}
_add_deps = {}
_cur_pkg = ''
_rewrite_files_mk = False
_intra_pkg_imps = {}
_logger = None

def glog(*args):
    pass

def _glog(*args):
    global _logger
    if not _logger:
        ch = logging.FileHandler('deps.log')
        _logger = logging.getLogger('debug_log')
        _logger.setLevel(logging.WARNING)
        _logger.addHandler(ch)

    _logger.debug(','.join(map(str, args)))

def bail_parse_deps(lineno, line):
    print "Faulty deps.mk at line %u\n>%s" % (lineno, line)
    exit(1)

def finish(rc):
    exit(rc)


################################################################################
##
################################################################################

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
        check_files(gen)
        if _rewrite_files_mk:
            rewrite_files_mk(dirpath)
    remove_self_deps()
    return len(_add_deps) == 0

def remove_self_deps():
    for mod, mod_deps in _add_deps.iteritems():
        if mod in mod_deps:
            mod_deps.remove(mod)

################################################################################
## Parsing for imports
################################################################################

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


def check_files(gen):
    for path in gen:
        with open(path) as fd:
            pkg_int_imps = check_import_list(fd)
            if _rewrite_files_mk:
                cur_mod = os.path.basename(path)
                pkg_int_imps = map(lambda nm: nm+'.d', pkg_int_imps)
                _intra_pkg_imps[cur_mod] = set(pkg_int_imps)

def check_import_list(fd):
    pkg_int_imps = []
    for m in _import_re.finditer(fd.read()):
        for imp in m.group(1).split(','):
            pkg_int_imp = check_import(imp)
            if _rewrite_files_mk and pkg_int_imp:
                pkg_int_imps.append(pkg_int_imp)
    return pkg_int_imps

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
        return m.group(2)

    dep_known = _cur_pkg in _deps and imp_pkg in _deps[_cur_pkg]

    if not dep_known:
        if _cur_pkg in _add_deps:
            _add_deps[_cur_pkg].add(imp_pkg)
        else:
            _add_deps[_cur_pkg] = set([imp_pkg])

################################################################################
## Rewrite Makefile includes
################################################################################

def rewrite_deps(fd):
    for k,v in _deps.iteritems():
        if k in _add_deps:
            _add_deps[k] = _add_deps[k].union(v)
        else:
            _add_deps[k] = v

    for k,v in _add_deps.iteritems():
        for dep in v:
            fd.write('%s_DEP := $$(%s_LIB)\n' % (k,dep))

def rewrite_files_mk(dirpath):
    global _intra_pkg_imps
    if not _rewrite_files_mk or len(_intra_pkg_imps) == 0:
        return

    build_bundles = sort_intra_pkg_deps(_intra_pkg_imps)
    with open(os.path.join(dirpath, 'files.mk'), 'wb') as fd:
        fd.write('%s_SRCS := \\\n' % _cur_pkg)
        build_bundles = map(lambda bndl: ' '.join(bndl), build_bundles)
        for bundle in build_bundles:
            fd.write(bundle + ' \\\n')

        bundle_names = map(lambda nr: _cur_pkg+'_'+str(nr), range(len(build_bundles)))
        fd.write('\n')
        fd.write('%s_BUNDLES := %s\n' %(_cur_pkg, ' '.join(bundle_names)))
        for nm, fs in zip(bundle_names, build_bundles):
            fd.write('%s_SRCS := %s\n' %(nm, fs))

    _intra_pkg_imps = {}


################################################################################
## Directed Graph -> Directed Acyclic Graph
################################################################################

def sort_intra_pkg_deps(dep_map):
    glog("SORT", dep_map)
    assert len(reduce(set.union, dep_map.values(), set())) \
        <= len(dep_map.keys())

    result = []
    resolved = set()
    unresolved = set()

    def insert_sorted(mod, dep_set):
        KEMPTY = (set(), set())
        glog("INSERT", mod)
        if mod in resolved:
            return KEMPTY
        to_resolve = dep_set.difference(resolved)
        glog("TO_RESOLVE", mod, to_resolve)

        if len(to_resolve) == 0:
            glog("NO_UNRESOLVED_DEPS", mod, dep_set)
            resolved.add(mod)
            result.append([mod])
            return KEMPTY

        unresolved.add(mod)

        glog("RESOLVING_DEPS", mod, to_resolve)
        cyclic = to_resolve.intersection(unresolved)
        glog("CYCLIC", mod, cyclic)
        cy_depnds = set()

        def update_cy(add_cyclic, add_cy_depnds):
            glog("ADD_CYCLIC", add_cyclic, add_cy_depnds)
            cyclic.update(add_cyclic)
            cy_depnds.update(add_cy_depnds)

        to_resolve.difference_update(unresolved)
        glog("RESOLVEABLE", mod, to_resolve)
        walk_deps = (insert_sorted(dep, dep_map[dep])
                     for dep in to_resolve)
        for dep in walk_deps:
            update_cy(*dep)

        unresolved.discard(mod)

        if len(cyclic) == 0:
            glog("RESOLVED", mod)
            resolved.add(mod)
            result.append([mod])

            return KEMPTY

        elif cyclic == set([mod]):
            glog("BUNDLE", mod, cy_depnds)
            unresolved.difference_update(cy_depnds)
            resolved.update(cy_depnds)
            resolved.add(mod)

            bundle = list(cy_depnds)
            bundle.append(mod)
            result.append(bundle)

            return KEMPTY

        else:
            glog("UNRESOLVED", mod, cyclic, cy_depnds)
            cyclic.discard(mod)
            cy_depnds.add(mod)

            return (cyclic, cy_depnds)

    for k, v in dep_map.iteritems():
        if len(result) >= len(dep_map):
            # finished
            return result
        to_resolve = insert_sorted(k, v)

    return result

def test_intra_pkg_deps():
    KNum = 10
    elems = range(KNum);
    intra_pkg_deps = {}
    for f in elems:
        rnd_deps = set(random.sample(elems, random.randint(0, KNum)))
        rnd_deps.discard(f)
        intra_pkg_deps[f] = rnd_deps

    sorted_deps = sort_intra_pkg_deps(intra_pkg_deps)

    all_mods = set()
    for bundle in sorted_deps:
        all_mods.update(bundle)
    assert all_mods == set(elems)

    there = set()
    for bundle in sorted_deps:
        for elem in bundle:
            for dep in intra_pkg_deps[elem]:
                assert(dep in there or dep in bundle)
        there.update(bundle)

def assert_cmp(result, exp):
    assert map(set, result) == map(set, exp)

def test_special_intra_pkg_deps():
    ip_deps = {1:set([2]), 2:set([3]), 3:set([1])}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[3,2,1]])
    ip_deps = {1:set([2]), 2:set([3]), 3:set([2])}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[3,2],[1]])
    ip_deps = {1:set(), 2:set(), 3:set()}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[1],[2],[3]])
    ip_deps = {1:set([2]), 2:set([3]), 3:set()}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[3],[2],[1]])
    ip_deps = {1:set([2,3]), 2:set([3]), 3:set()}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[3],[2],[1]])
    ip_deps = {1:set([2]), 2:set([3]), 3:set([4,2]), 4:set()}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[4], [3,2],[1]])
    ip_deps = {1:set([2]), 2:set([3]), 3:set([1,2])}
    assert_cmp(sort_intra_pkg_deps(ip_deps), [[3,2,1]])


################################################################################
## MAIN
################################################################################

if __name__=='__main__':
    if os.path.isfile('deps.mk'):
        with open('deps.mk', 'rb') as fd:
            parse_deps(fd.read().rstrip())

    global _rewrite_files_mk
    _rewrite_files_mk = len(sys.argv) > 1 and int(sys.argv[1]) & 0x1

    if check_deps():
        finish(0)

    with open('deps.mk', 'wb') as fd:
        rewrite_deps(fd)
    finish(0)
