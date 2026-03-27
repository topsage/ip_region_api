from __future__ import annotations

import ipaddress
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

import ip2region.searcher as xdb
import ip2region.util as util



def _default_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[2]


BASE_DIR = _default_base_dir()
DEFAULT_XDB_PATH = BASE_DIR / "ip2region.xdb"
IP2REGION_VERSION = {
    "ipv4": util.IPv4,
    "ipv6": util.IPv6,
}


class LookupRequest(BaseModel):
    ip: str = Field(..., description="IP address to look up")


class LookupResponse(BaseModel):
    ip: str
    country: str
    province: str
    city: str
    isp: str
    country_code: str
    region: str


@dataclass(slots=True)
class RegionRecord:
    country: str
    province: str
    city: str
    isp: str
    country_code: str
    region: str

    def to_response(self, ip: str) -> LookupResponse:
        return LookupResponse(
            ip=ip,
            country=self.country,
            province=self.province,
            city=self.city,
            isp=self.isp,
            country_code=self.country_code,
            region=self.region,
        )


class Ip2RegionService:
    def __init__(self, db_path: Path, version: str = "ipv4") -> None:
        if version not in IP2REGION_VERSION:
            raise ValueError(f"unsupported ip2region version: {version}")

        self.db_path = db_path
        self.version_name = version
        self.version = IP2REGION_VERSION[version]

        if not self.db_path.exists():
            raise FileNotFoundError(f"ip2region xdb file not found: {self.db_path}")

        util.verify_from_file(str(self.db_path))
        content = util.load_content_from_file(str(self.db_path))
        self.searcher = xdb.new_with_buffer(self.version, content)

    def lookup(self, ip: str) -> RegionRecord:
        self._validate_ip_version(ip)
        region = self.searcher.search(ip)
        if not region:
            raise LookupError(f"no region found for ip: {ip}")
        return parse_region(region)

    def _validate_ip_version(self, ip: str) -> None:
        parsed = ipaddress.ip_address(ip)
        if self.version_name == "ipv4" and parsed.version != 4:
            raise ValueError("this service is using an IPv4 xdb file, IPv6 is not supported")
        if self.version_name == "ipv6" and parsed.version != 6:
            raise ValueError("this service is using an IPv6 xdb file, IPv4 is not supported")


def parse_region(region: str) -> RegionRecord:
    parts = (region or "").split("|")
    while len(parts) < 5:
        parts.append("")
    cleaned = ["" if item == "0" else item for item in parts[:5]]
    return RegionRecord(
        country=cleaned[0],
        province=cleaned[1],
        city=cleaned[2],
        isp=cleaned[3],
        country_code=cleaned[4],
        region=region,
    )


def create_app(service: Ip2RegionService | None = None) -> FastAPI:
    app = FastAPI(
        title="IP Region API",
        version="1.0.0",
        description="Lookup region info from a local ip2region.xdb file",
    )

    if service is None:
        db_path = Path(os.getenv("IP2REGION_XDB_PATH", DEFAULT_XDB_PATH))
        db_version = os.getenv("IP2REGION_DB_VERSION", "ipv4").lower()
        service = Ip2RegionService(db_path=db_path, version=db_version)

    @app.get("/health")
    def health() -> dict[str, Any]:
        return {
            "status": "ok",
            "db_path": str(service.db_path),
            "db_version": service.version_name,
        }

    @app.get("/lookup", response_model=LookupResponse)
    def lookup_get(ip: str = Query(..., description="IP address to look up")) -> LookupResponse:
        return _handle_lookup(service, ip)

    @app.post("/lookup", response_model=LookupResponse)
    def lookup_post(payload: LookupRequest) -> LookupResponse:
        return _handle_lookup(service, payload.ip)

    return app


def _handle_lookup(service: Ip2RegionService, ip: str) -> LookupResponse:
    try:
        result = service.lookup(ip)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover - keep API errors stable
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return result.to_response(ip)


app = create_app()
