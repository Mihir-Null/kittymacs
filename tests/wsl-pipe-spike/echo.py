# The far end of the pipe spike: length-prefixed frames on stdin and stdout.
#
# A request is <4-byte big-endian length><op byte><body>.
# A reply is <4-byte big-endian length><32-byte SHA-256><payload>.
#   op 0, echo:   the digest of the body as received, and the body.
#   op 1, sink:   the digest of the body as received, and no payload.
#   op 2, source: the body is a 4-byte size; a payload of that many pattern bytes
#                 and its digest, so the bytes coming back are known in advance.
#   op 3, stop:   stop this process with SIGSTOP, and reply to nothing.
# So a corrupted byte shows which way it went.

import hashlib
import os
import signal
import struct

if os.name == "nt":
    import msvcrt

    msvcrt.setmode(0, os.O_BINARY)
    msvcrt.setmode(1, os.O_BINARY)

PATTERN = bytes(range(256))


def read_exactly(count):
    chunks = []
    while count > 0:
        chunk = os.read(0, min(count, 1 << 20))
        if not chunk:
            return None
        chunks.append(chunk)
        count -= len(chunk)
    return b"".join(chunks)


def write_all(data):
    view = memoryview(data)
    while view:
        view = view[os.write(1, view) :]


def reply(digest_of, payload):
    digest = hashlib.sha256(digest_of).digest()
    write_all(struct.pack(">I", 32 + len(payload)) + digest + payload)


while True:
    head = read_exactly(4)
    if head is None:
        break
    frame = read_exactly(struct.unpack(">I", head)[0])
    if frame is None:
        break
    op, body = frame[0], frame[1:]
    if op == 0:
        reply(body, body)
    elif op == 1:
        reply(body, b"")
    elif op == 2:
        size = struct.unpack(">I", body)[0]
        payload = (PATTERN * (size // 256 + 1))[:size]
        reply(payload, payload)
    elif op == 3:
        os.kill(os.getpid(), signal.SIGSTOP)
