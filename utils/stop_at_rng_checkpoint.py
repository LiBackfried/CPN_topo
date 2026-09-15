#!/usr/bin/env python3
import ctypes
import os
import signal
import struct
import sys

if len(sys.argv) < 3 or len(sys.argv) % 2 != 1:
    raise SystemExit(f"usage: {sys.argv[0]} PID RNG_FILE [PID RNG_FILE ...]")

libc = ctypes.CDLL(None, use_errno=True)
fd = libc.inotify_init1(os.O_CLOEXEC)
if fd < 0:
    raise OSError(ctypes.get_errno(), "inotify_init1")

targets = {}
for index in range(1, len(sys.argv), 2):
    pid = int(sys.argv[index])
    path = os.fsencode(sys.argv[index + 1])
    wd = libc.inotify_add_watch(fd, path, 0x00000008)  # IN_CLOSE_WRITE
    if wd < 0:
        raise OSError(ctypes.get_errno(), f"inotify_add_watch({path!r})")
    targets[wd] = pid

while targets:
    data = os.read(fd, 4096)
    offset = 0
    while offset < len(data):
        wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
        offset += 16 + name_len
        pid = targets.pop(wd, None)
        if pid is None:
            continue
        try:
            os.kill(pid, signal.SIGSTOP)
        except ProcessLookupError:
            pass
        print(f"checkpoint closed; stopped PID {pid}", flush=True)
