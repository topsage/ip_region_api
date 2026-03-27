from __future__ import annotations

import argparse
import os
from pathlib import Path

import uvicorn


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the IP region lookup API")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host address")
    parser.add_argument("--port", type=int, default=8011, help="Bind port")
    parser.add_argument("--xdb-path", default="", help="Path to ip2region.xdb")
    args = parser.parse_args()

    if args.xdb_path:
        os.environ["IP2REGION_XDB_PATH"] = str(Path(args.xdb_path).resolve())

    from ip_region_api.app import create_app

    uvicorn.run(create_app(), host=args.host, port=args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
