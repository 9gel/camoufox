"""
Programmatic Playwright-server launcher.

The bundled `camoufox server` subcommand calls `launch_server()` with no
arguments, which forces `launch_options()` to hit BrowserForge's
fingerprint generator. As of camoufox v0.5.2 / browserforge 1.2.4,
BrowserForge has no headers matching Firefox 150 and raises
`ValueError: No headers based on this input can be generated`,
so `camoufox server` is unusable until BrowserForge ships an update.

This module is a long-term workaround: it builds the same
`launch_options()` config but passes `fingerprint_preset=True`, which
draws from the locally bundled real-fingerprint presets instead of
BrowserForge. Fingerprinting still happens (every session still spoofs
OS/screen/GL/audio/headers), but the per-call uniqueness BrowserForge
provides is traded for stability.

Configuration is via env vars so it can be wired into a
systemd/launchd unit without rewriting code:

* `CAMOUFOX_SERVER_HOST`     — bind address (default 127.0.0.1)
* `CAMOUFOX_SERVER_PORT`     — TCP port (default 4545)
* `CAMOUFOX_SERVER_HEADLESS` — "true" (default), "virtual" (Xvfb), or
                                "false"
* `CAMOUFOX_SERVER_OS`       — restrict spoofed OS, e.g. "linux"; comma-
                                separated for multi (e.g. "linux,macos")

Run with `python -m camoufox.server_main` or the `camoufox-server`
entry-point installed by the package.
"""

from __future__ import annotations

import base64
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import orjson
from playwright._impl._driver import compute_driver_executable

from .server import LAUNCH_SCRIPT, to_camel_case_dict
from .utils import launch_options


def _resolve_driver() -> Tuple[str, Path]:
    """
    Resolve the Node binary and the Playwright-core package directory.

    Upstream `server.get_nodejs()` plus the launchServer.js trick of
    `cwd = Path(node).parent / "package"` only works when Playwright
    ships a bundled Node next to its driver (the pip-install layout).
    On Nixpkgs the python `playwright` package uses the system Node
    binary, and `compute_driver_executable()` returns a tuple of
    `(node_bin, cli_js)` — so the playwright-core dir is
    `Path(cli_js).parent`, not `Path(node).parent / "package"`.
    """
    result = compute_driver_executable()
    if isinstance(result, tuple):
        node_bin, cli_js = result[0], result[1]
        return node_bin, Path(cli_js).parent
    node_bin = result
    return node_bin, Path(node_bin).parent / "package"


def _parse_headless(value: str) -> Any:
    v = value.strip().lower()
    if v in ("virtual", "xvfb"):
        return "virtual"
    if v in ("false", "0", "no"):
        return False
    return True


def _parse_os(value: Optional[str]) -> Optional[Tuple[str, ...]]:
    if not value:
        return None
    parts = tuple(p.strip() for p in value.split(",") if p.strip())
    return parts or None


def main() -> None:
    host = os.environ.get("CAMOUFOX_SERVER_HOST", "127.0.0.1")
    port = int(os.environ.get("CAMOUFOX_SERVER_PORT", "4545"))
    headless = _parse_headless(os.environ.get("CAMOUFOX_SERVER_HEADLESS", "true"))
    spoof_os = _parse_os(os.environ.get("CAMOUFOX_SERVER_OS"))

    kwargs: Dict[str, Any] = {
        "fingerprint_preset": True,
        "headless": headless,
        "i_know_what_im_doing": True,
    }
    if spoof_os is not None:
        kwargs["os"] = spoof_os

    config = launch_options(**kwargs)
    # Playwright's launchServer reads `port` / `host` off the options
    # dict and binds the WebSocket to that address. `wsPath` makes the
    # endpoint URL predictable; without it, Playwright generates a
    # random GUID and clients have to scrape it from the server log.
    # to_camel_case_dict() lowercases each key before recamelling, so
    # we feed snake_case here (`ws_path` → `wsPath`). A pre-camelled
    # `wsPath` would round-trip to `wspath` and Playwright would ignore it.
    config["port"] = port
    config["host"] = host
    ws_path = os.environ.get("CAMOUFOX_SERVER_WS_PATH", "camoufox")
    if ws_path:
        config["ws_path"] = ws_path if ws_path.startswith("/") else f"/{ws_path}"

    data = orjson.dumps(to_camel_case_dict(config))
    node_bin, driver_cwd = _resolve_driver()

    print(
        f"[camoufox-server] starting on ws://{host}:{port}/ "
        f"(headless={headless!r}, os={spoof_os!r})",
        flush=True,
    )

    process = subprocess.Popen(  # nosec
        [node_bin, str(LAUNCH_SCRIPT)],
        cwd=driver_cwd,
        stdin=subprocess.PIPE,
        text=True,
    )
    assert process.stdin is not None
    process.stdin.write(base64.b64encode(data).decode())
    process.stdin.close()
    sys.exit(process.wait())


if __name__ == "__main__":
    main()
