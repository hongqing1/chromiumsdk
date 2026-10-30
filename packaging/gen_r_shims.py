#!/usr/bin/env python3
# Usage: gen_r_shims.py <out_dir> <pkg>=<R.txt> ...
import os
import sys
from collections import defaultdict

NS = 'org.chromium.crwebview.res'

out = sys.argv[1]
for arg in sys.argv[2:]:
    pkg, rtxt = arg.split('=', 1)
    types = defaultdict(list)
    with open(rtxt) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3:
                types[parts[1]].append((parts[0], parts[2]))
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
    print(f'wrote {pkg} ({sum(len(v) for v in types.values())} fields)')
