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
# State for retry test
# ---------------------------------------------------------------------------
retry_counts = {}


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


@app.route("/put", methods=["PUT"])
def put_endpoint():
    return jsonify(_request_data())


@app.route("/patch", methods=["PATCH"])
def patch_endpoint():
    return jsonify(_request_data())


@app.route("/basic-auth-check")
def basic_auth_check():
    return jsonify({"authorization": request.headers.get("Authorization")})


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


@app.route("/status/<int:code>")
def status_endpoint(code):
    return make_response(f"Status: {code}", code)


@app.route("/bearer")
def bearer_endpoint():
    auth = request.headers.get("Authorization")
    if auth and auth.startswith("Bearer "):
        token = auth.split(" ")[1]
        return jsonify({"authenticated": True, "token": token})
    return make_response("Unauthorized", 401, {"WWW-Authenticate": 'Bearer realm="Login"'})


@app.route("/redirect/<int:n>")
def redirect_n(n):
    if n > 1:
        return redirect(f"/redirect/{n-1}")
    return redirect("/get")


@app.route("/retry/<string:id>/<int:n>")
def retry_endpoint(id, n):
    """Fails n times with 500 for a given id before returning 200."""
    count = retry_counts.get(id, 0)
    if count < n:
        retry_counts[id] = count + 1
        return make_response(f"Retry attempt {count + 1}/{n} - Failing with 500", 500)
    return jsonify({"success": True, "attempts": count})


# ---------------------------------------------------------------------------
# Simple forward-proxy handler (Test 19)
# ---------------------------------------------------------------------------

@app.route("/redirect-302", methods=["GET", "POST", "PUT", "DELETE"])
def redirect_302():
    return redirect("/get", code=302)


@app.route("/redirect-307", methods=["GET", "POST", "PUT", "DELETE"])
def redirect_307():
    return redirect("/post", code=307)


@app.route("/redirect-301", methods=["GET", "POST", "PUT", "DELETE"])
def redirect_301():
    return redirect("/get", code=301)


@app.route("/redirect-308", methods=["GET", "POST", "PUT", "DELETE"])
def redirect_308():
    return redirect("/post", code=308)


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
    resp = jsonify({
        "proxied": True,
        "url": request.url,
        "proxy-auth": request.headers.get("Proxy-Authorization")
    })
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
