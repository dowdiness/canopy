#!/usr/bin/env python3
import os, stat

base = os.path.dirname(os.path.abspath(__file__))

servers = {
    "start-web.sh": "apps/web",
    "start-demo-react.sh": "examples/demo-react",
    "start-rabbita.sh": "deps/rabbita/examples/SSR",
    "start-prosemirror.sh": "examples/prosemirror",
    "start-ideal-web.sh": "apps/ideal/web",
}

for name, subdir in servers.items():
    path = os.path.join(base, name)
    workdir = f"$PROJECT_ROOT/{subdir}"
    with open(path, "w", newline="\n") as f:
        f.write("#!/bin/bash\n")
        f.write('export PATH="/home/antisatori/.moon/bin:/usr/bin:$PATH"\n')
        f.write('PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"\n')
        f.write(f'cd "{workdir}"\n')
        f.write(f'exec "{workdir}/node_modules/.bin/vite"\n')
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    print(f"wrote {name}")
