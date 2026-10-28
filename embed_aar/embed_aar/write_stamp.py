#!/usr/bin/env python3
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text("ok\n")
