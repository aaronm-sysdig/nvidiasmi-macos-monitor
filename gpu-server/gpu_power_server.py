#!/usr/bin/env python3
"""GPU Power Server — serves total RTX power draw as JSON.

Usage:
    python gpu_power_server.py [--port 9090] [--cert cert.pem --key key.pem]

Returns:
    GET /  → {"total_watts": 320, "count": 2, "per_gpu": [160, 160]}
    GET /healthz → {"status": "ok"}
"""
import argparse
import json
import os
import re
import ssl
import subprocess
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Any

# Cache GPU names keyed by index (populated on first query)
_gpu_names: dict[str, str] = {}


def _get_gpu_names() -> dict[str, str]:
    """Query nvidia-smi for GPU names and cache them."""
    global _gpu_names
    if _gpu_names:
        return _gpu_names
    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=index,name",
            "--format=csv,nounits,noheader",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode == 0:
        for line in result.stdout.strip().split("\n"):
            parts = line.strip().split(",", 1)
            if len(parts) == 2:
                _gpu_names[parts[0].strip()] = parts[1].strip()
    return _gpu_names


def get_gpu_metrics() -> tuple[list[dict[str, Any]], str | None]:
    """Query nvidia-smi for expanded GPU metrics.

    Returns:
        (list of GPU metric dicts, or error string on failure)
    """
    names = _get_gpu_names()

    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=index,name,power.draw,power.limit,"
            "temperature.gpu,fan.speed,"
            "utilization.gpu,utilization.memory",
            "--format=csv,nounits,noheader",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        return [], result.stderr or "nvidia-smi exited with code " + str(result.returncode)

    def parse_float(val: str) -> float:
        m = re.search(r"([\d.]+)", val)
        return float(m.group(1)) if m else 0.0

    def parse_int(val: str) -> int:
        return int(parse_float(val))

    gpus = []
    for line in result.stdout.strip().split("\n"):
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 8:
            continue

        gpu_id = int(parts[0])
        # parts[1] is name — use cached version if available
        gpu_name = names.get(str(gpu_id), parts[1])

        power_watts = parse_float(parts[2])
        power_limit_watts = parse_float(parts[3])
        temperature_c = parse_int(parts[4])
        fan_pct = parse_int(parts[5])

        # utilization.gpu returns "X% / Y%" — parse both values
        util_match = re.search(r"([\d.]+)\s*%\s*/\s*([\d.]+)\s*%", parts[6])
        if util_match:
            util_gpu = int(util_match.group(1))
            util_mem = int(util_match.group(2))
        else:
            util_gpu = 0
            util_mem = 0

        gpus.append({
            "id": gpu_id,
            "name": gpu_name,
            "power_watts": round(power_watts),
            "power_limit_watts": round(power_limit_watts),
            "temperature_c": temperature_c,
            "fan_pct": fan_pct,
            "utilization_gpu": util_gpu,
            "utilization_mem": util_mem,
        })

    return gpus, None


def get_gpu_power() -> tuple[list[float], str | None]:
    """Query nvidia-smi for instantaneous power draw per GPU.

    Returns:
        (list of watt values, or error string on failure)
    """
    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=power.draw",
            "--format=csv,nounits,noheader",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        return [], result.stderr or "nvidia-smi exited with code " + str(result.returncode)

    watts = []
    for line in result.stdout.strip().split("\n"):
        m = re.search(r"([\d.]+)", line.strip())
        if m:
            watts.append(float(m.group(1)))
    return watts, None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/v1/metrics":
            try:
                gpus, error = get_gpu_metrics()
                if error:
                    self._json({"error": error}, 500)
                    return
                total = sum(g["power_watts"] for g in gpus)
                self._json({
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "gpus": gpus,
                    "total_watts": total,
                })
            except Exception as e:
                self._json({"error": str(e)}, 500)
        elif self.path == "/healthz":
            self._json({"status": "ok"})
        elif self.path in ("/", "/watts"):
            try:
                per_gpu, error = get_gpu_power()
                if error:
                    self._json({"error": error}, 500)
                    return
                rounded = [round(w) for w in per_gpu]
                self._json({
                    "total_watts": sum(rounded),
                    "count": len(rounded),
                    "per_gpu": rounded,
                    "gpus": {f"GPU{i}": w for i, w in enumerate(rounded)},
                })
            except Exception as e:
                self._json({"error": str(e)}, 500)
        else:
            self._json({"error": "not found"}, 404)

    def _json(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # silence request logs


def _self_signed_cert_dir():
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), ".certs")


def _ensure_cert():
    cert_dir = _self_signed_cert_dir()
    cert_path = os.path.join(cert_dir, "cert.pem")
    key_path = os.path.join(cert_dir, "key.pem")
    if os.path.exists(cert_path) and os.path.exists(key_path):
        return cert_path, key_path
    os.makedirs(cert_dir, exist_ok=True)
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", key_path, "-out", cert_path,
        "-days", "3650", "-nodes",
        "-subj", "/CN=localhost",
    ], check=True, capture_output=True)
    print(f"Generated self-signed cert: {cert_path}")
    return cert_path, key_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9090)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--cert", help="TLS cert path")
    parser.add_argument("--key", help="TLS key path")
    args = parser.parse_args()

    # Auto-generate self-signed cert if neither --cert nor --key provided
    if not args.cert and not args.key:
        args.cert, args.key = _ensure_cert()

    server = HTTPServer((args.host, args.port), Handler)
    if args.cert and args.key:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(args.cert, args.key)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
        print(f"GPU power server on https://{args.host}:{args.port}")
    else:
        print(f"GPU power server on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
