#!/usr/bin/env python3
"""Patch the DFS disc image to fix the !Boot filename.

BeebAsm generates a !Boot file with '*RUN MaJong' but the binary is
saved as 'MAHJONG'. DFS uppercases the filename from *RUN, so it looks
for 'MAJONG' which doesn't exist. Patch the !Boot content to use the
correct filename.

Usage: python3 patch_boot.py <disc_image.ssd>
"""

import sys


def patch_boot(disc_path):
    with open(disc_path, "rb") as f:
        data = bytearray(f.read())

    # The !Boot file content starts at sector 2 (offset 0x200) in a
    # standard single-sided DFS disc. BeebAsm writes:
    #   *BASIC\r*RUN MaJong\r
    # We need to replace 'MaJong' with 'MAHJONG'.

    # Search for the !Boot content pattern
    needle = b"*BASIC\r*RUN "
    idx = data.find(needle)
    if idx == -1:
        print("ERROR: Could not find !Boot content in disc image")
        sys.exit(1)

    name_start = idx + len(needle)  # offset where filename begins

    # Check if it's already correct
    current_name = data[name_start : name_start + 8]
    if current_name == b"MAHJONG\r":
        print("Already patched — no changes needed.")
        return

    # Find the CR that terminates the filename
    cr_offset = data.index(b"\r", name_start)
    current_filename = data[name_start:cr_offset].decode("ascii", errors="replace")
    print(f"Current !Boot filename: *RUN {current_filename!r}")

    # We need to replace the filename with 'MAHJONG'
    # The content layout is:
    #   ... *RUN <filename> \r ...
    # We'll overwrite starting at name_start with 'MAHJONG\r'
    new_filename = b"MAHJONG\r"
    old_len = cr_offset - name_start + 1  # includes the CR

    if len(new_filename) > old_len:
        # Need to shift bytes down — content grows
        shift = len(new_filename) - old_len
        # Check we won't overflow the disc
        if len(data) + shift > 65536:
            # Just overwrite in place (there should be null padding)
            pass
        data[name_start : name_start + len(new_filename)] = new_filename
    else:
        data[name_start : name_start + len(new_filename)] = new_filename
        # Clear remaining old bytes
        for i in range(name_start + len(new_filename), cr_offset + 1):
            data[i] = 0x00

    # Verify
    verify = data.find(b"*BASIC\r*RUN MAHJONG\r")
    if verify == -1:
        print("ERROR: Patch verification failed!")
        sys.exit(1)

    with open(disc_path, "wb") as f:
        f.write(data)

    print(f"Patched !Boot: *RUN MAHJONG (was *RUN {current_filename})")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <disc_image.ssd>")
        sys.exit(1)
    patch_boot(sys.argv[1])
