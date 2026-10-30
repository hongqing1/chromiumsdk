#!/usr/bin/env python3
# Usage: gen_r_shims.py <out_dir> <pkg>=<R.txt>[+<R.txt>...] ...
# Multiple R.txt paths (joined with '+') are unioned into one shim package.
# Chromium's content_java merges transitive ui resources into content.R;
# pass content R.txt + ui R.txt so org.chromium.content.R$array exists
# (e.g. ui_com_google_android_gms_fonts_certs used by AndroidFontLookupImpl).
import os
import sys
from collections import defaultdict

NS = 'org.chromium.crwebview.res'

out = sys.argv[1]
for arg in sys.argv[2:]:
    pkg, rtxts = arg.split('=', 1)
    types = defaultdict(list)
    seen = defaultdict(set)
    for rtxt in rtxts.split('+'):
        rtxt = rtxt.strip()
        if not rtxt:
            continue
        with open(rtxt) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3:
                    kind, rtype, name = parts[0], parts[1], parts[2]
                    if name in seen[rtype]:
                        continue
                    seen[rtype].add(name)
                    types[rtype].append((kind, name))
    lines = [f'package {pkg};', '', 'public final class R {']
    for rtype in sorted(types):
        lines.append(f'    public static final class {rtype} {{')
        for kind, name in types[rtype]:
            lines.append(f'        public static {kind} {name} = {NS}.R.{rtype}.{name};')
        lines.append('    }')
    lines.append('}')
    pkg_dir = os.path.join(out, *pkg.split('.'))
    os.makedirs(pkg_dir, exist_ok=True)
    with open(os.path.join(pkg_dir, 'R.java'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'wrote {pkg} ({sum(len(v) for v in types.values())} fields'
          f', types={sorted(types.keys())}, sources={rtxts.count("+")+1})')
