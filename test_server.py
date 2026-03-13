#!/usr/bin/env python3
"""
Flask-based local test server that replicates httpbin.org endpoints
used by test_curl.ps1. Run via the .venv virtual environment:

    .venv/bin/python test_server.py [--port PORT] [--https-port HTTPS_PORT]

Endpoints implemented:
    /get, /headers, /post, /basic-auth/<user>/<password>,
    /redirect-to, /cookies/set/<name>/<value>, /cookies,
    /user-agent, /delete, /range/<n>, /delay/<n>
Also provides a forward-proxy endpoint on the HTTP port.
"""

import argparse
import json
import string
import ssl
import threading
import time
from flask import Flask, request, jsonify, redirect, make_response, Response

app = Flask(__name__)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

def _request_data():
    """Build a dict similar to httpbin.org's standard response."""
    return {
        "args": dict(request.args),
        "data": request.get_data(as_text=True),
        "files": {k: v.read().decode() for k, v in request.files.items()},
        "form": dict(request.form),
        "headers": dict(request.headers),
        "json": request.get_json(silent=True),
        "origin": request.remote_addr,
        "url": request.url,
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/get", methods=["GET", "HEAD"])
def get_endpoint():
    data = {
        "args": dict(request.args),
        "headers": dict(request.headers),
        "origin": request.remote_addr,
        "url": request.url,
    }
    return jsonify(data)


@app.route("/headers")
def headers_endpoint():
    return jsonify({"headers": dict(request.headers)})


@app.route("/post", methods=["POST"])
def post_endpoint():
    return jsonify(_request_data())


@app.route("/basic-auth/<user>/<password>")
def basic_auth(user, password):
    auth = request.authorization
    if auth and auth.username == user and auth.password == password:
        return jsonify({"authenticated": True, "user": user})
    return make_response(
        "Unauthorized", 401, {"WWW-Authenticate": 'Basic realm="Login"'}
    )


@app.route("/redirect-to")
def redirect_to():
    url = request.args.get("url")
    return redirect(url)


@app.route("/cookies/set/<name>/<value>")
def set_cookie(name, value):
    resp = redirect("/cookies")
    resp.set_cookie(name, value)
    return resp


@app.route("/cookies")
def get_cookies():
    return jsonify({"cookies": dict(request.cookies)})


@app.route("/user-agent")
def user_agent():
    return jsonify({"user-agent": request.headers.get("User-Agent")})


@app.route("/delete", methods=["DELETE"])
def delete_endpoint():
    return jsonify(_request_data())


@app.route("/range/<int:n>")
def range_endpoint(n):
    alphabet = string.ascii_lowercase
    data = "".join(alphabet[i % 26] for i in range(n))

    range_header = request.headers.get("Range")
    if range_header:
        byte_range = range_header.replace("bytes=", "").split("-")
        start = int(byte_range[0])
        end = int(byte_range[1]) if byte_range[1] else n - 1
        sliced = data[start : end + 1]
        resp = make_response(sliced, 206)
        resp.headers["Content-Range"] = f"bytes {start}-{end}/{n}"
        resp.headers["Content-Length"] = str(len(sliced))
        return resp
    return data


@app.route("/delay/<int:n>")
def delay_endpoint(n):
    time.sleep(n)
    return jsonify({"delayed": n})


# ---------------------------------------------------------------------------
# Simple forward-proxy handler (Test 19)
# ---------------------------------------------------------------------------

@app.route("/proxy", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"])
def proxy_handler():
    """
    Minimal forward-proxy simulation.
    curl -x http://localhost:PORT  target_url
    When curl uses a proxy it sends the full URL as the request path, e.g.
        GET http://localhost:PORT/get HTTP/1.1
    Flask sees this as the path "/get" on our server, so we just forward to
    the local /get handler.  For the test we only need to prove that the
    proxy flag works; we do this by returning a header indicating proxy use.
    """
    resp = jsonify({"proxied": True, "url": request.url})
    resp.headers["X-Proxy"] = "true"
    return resp


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_https(port):
    """Run a second Flask instance with a self-signed certificate."""
    # Generate an ad-hoc SSL context (requires pyopenssl)
    app.run(host="127.0.0.1", port=port, ssl_context="adhoc", use_reloader=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Local httpbin-like test server")
    parser.add_argument("--port", type=int, default=8080, help="HTTP port (default 8080)")
    parser.add_argument("--https-port", type=int, default=8443, help="HTTPS port (default 8443)")
    args = parser.parse_args()

    # Start HTTPS server in a background thread
    https_thread = threading.Thread(target=run_https, args=(args.https_port,), daemon=True)
    https_thread.start()

    # Start HTTP server (foreground)
    app.run(host="127.0.0.1", port=args.port, use_reloader=False)
