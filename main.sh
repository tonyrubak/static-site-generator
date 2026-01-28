#! /bin/sh
zig build run
cd public && python3 -m http.server 8888
