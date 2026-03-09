#!/usr/bin/env bash
# RDP to win-forensic (192.168.10.50) with HiDPI scaling and clipboard.
#
# Password is pulled from pass store and piped via /args-from:stdin so it
# never appears on the command line or in the process list.
#
# /args-from:stdin requires it be the ONLY argument to xfreerdp — all other
# options are passed one-per-line via stdin (printf into the pipe).
#
# Scale options: /scale only accepts 100, 140, or 180 (FreeRDP limitation).
# For 4K monitors, /size:3840x2160 + /scale:180 gives the best result.
#
# cert:ignore suppresses the self-signed cert prompt (WIN-FORENSIC uses a
# self-signed RDP cert — expected in a lab environment).

PASS=$(pass soc-lab/windows-analyst)

printf '/v:192.168.10.50\n/u:analyst\n/p:%s\n/size:3840x2160\n/scale:180\n/scale-desktop:180\n/scale-device:180\n/cert:ignore\n/clipboard\n/log-level:ERROR\n' "$PASS" \
  | xfreerdp /args-from:stdin
