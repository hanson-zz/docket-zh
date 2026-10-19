#!/usr/bin/env python3
"""Read one FIFO frame with an absolute timeout, including partial lines."""
import os
import select
import sys
import time

end = time.monotonic() + float(sys.argv[1])
frame = bytearray()
while True:
    remaining = end - time.monotonic()
    if remaining <= 0 or not select.select([0], [], [], max(0, remaining))[0]:
        sys.exit(124)
    byte = os.read(0, 1)
    if not byte:
        sys.exit(1)
    if byte == b"\n":
        sys.stdout.buffer.write(frame + b"\n")
        break
    frame.extend(byte)
