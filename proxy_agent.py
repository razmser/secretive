#!/usr/bin/env python3
import asyncio
import os
import struct

REAL_SOCK = "/Users/razmser/Library/Containers/com.razmser.Secretive.SecretAgent/Data/socket-debug.ssh"
PROXY_SOCK = "/tmp/secretive-proxy-agent.sock"

import itertools

_counter = itertools.count()


async def pipe(reader, writer, direction):
    try:
        while True:
            length_bytes = await reader.readexactly(4)
            length = struct.unpack(">I", length_bytes)[0]
            payload = await reader.readexactly(length)
            msg_type = payload[0] if payload else None
            if direction == "C->S" and msg_type == 13:
                # ssh-agent sign request, parse flags for debugging
                try:
                    # message body layout: string key_blob, string data, uint32 flags
                    offset = 1
                    for _ in range(2):
                        (chunk_len,) = struct.unpack(">I", payload[offset:offset+4])
                        offset += 4 + chunk_len
                    flags = struct.unpack(">I", payload[offset:offset+4])[0]
                except Exception:
                    flags = None
                print(f"{direction} id={next(_counter)} type=13 length={length} flags=0x{flags:08x}" if flags is not None else f"{direction} id={next(_counter)} type=13 length={length} flags=?")
            else:
                print(f"{direction} id={next(_counter)} type={msg_type} length={length}")
            writer.write(length_bytes)
            writer.write(payload)
            await writer.drain()
    except asyncio.IncompleteReadError as exc:
        if exc.partial:
            print(f"{direction} partial read {len(exc.partial)} bytes")
    except Exception as exc:
        print(f"{direction} pipe error: {exc}")
    finally:
        writer.close()
        await writer.wait_closed()

async def handle_client(client_reader, client_writer):
    try:
        server_reader, server_writer = await asyncio.open_unix_connection(REAL_SOCK)
    except Exception as exc:
        print(f"Failed to connect to real agent: {exc}")
        client_writer.close()
        await client_writer.wait_closed()
        return
    await asyncio.gather(
        pipe(client_reader, server_writer, "C->S"),
        pipe(server_reader, client_writer, "S->C"),
    )

async def main():
    try:
        os.unlink(PROXY_SOCK)
    except FileNotFoundError:
        pass
    server = await asyncio.start_unix_server(handle_client, path=PROXY_SOCK)
    print(f"Proxy listening on {PROXY_SOCK}")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
