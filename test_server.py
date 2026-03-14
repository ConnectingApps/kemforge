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
import os
import string
import threading
import time
import socket
import datetime
import ipaddress
import ssl
from flask import Flask, request, jsonify, redirect, make_response, Response
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

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
        "files": {k: v.read().decode('utf-8', errors='ignore') for k, v in request.files.items()},
        "form": dict(request.form),
        "headers": dict(request.headers),
        "json": request.get_json(silent=True),
        "origin": request.remote_addr,
        "url": request.url,
    }


def generate_cert(cert_path, key_path):
    """Modernized certificate generation using the cryptography library."""
    key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "127.0.0.1"),
    ])

    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.now(datetime.timezone.utc)
    ).not_valid_after(
        # Standard validity for modern clients (e.g. Chrome 398-day limit)
        datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=365)
    ).add_extension(
        x509.SubjectAlternativeName([
            x509.IPAddress(ipaddress.ip_address("127.0.0.1")),
            x509.DNSName("localhost"),
        ]),
        critical=False,
    ).add_extension(
        x509.BasicConstraints(ca=True, path_length=None),
        critical=True,
    ).add_extension(
        x509.KeyUsage(
            digital_signature=True,
            content_commitment=False,
            key_encipherment=True,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=True,
            crl_sign=True,
            encipher_only=False,
            decipher_only=False,
        ),
        critical=True,
    ).add_extension(
        x509.ExtendedKeyUsage([
            ExtendedKeyUsageOID.SERVER_AUTH,
            ExtendedKeyUsageOID.CLIENT_AUTH
        ]),
        critical=False,
    ).sign(key, hashes.SHA256())

    with open(cert_path, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    with open(key_path, "wb") as f:
        f.write(key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        ))


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/get", methods=["GET", "HEAD", "OPTIONS", "TRACE"])
def get_endpoint():
    if request.method == "OPTIONS":
        resp = make_response("", 204)
        resp.headers["Allow"] = "GET, POST, OPTIONS, HEAD, PUT, DELETE, PATCH, TRACE"
        return resp
    
    if request.method == "TRACE":
        # TRACE echoes the request
        headers = "\n".join(f"{k}: {v}" for k, v in request.headers.items())
        body = f"TRACE {request.path} HTTP/1.1\n{headers}\n\n"
        return Response(body, mimetype="message/http")

    if_modified_since = request.headers.get("If-Modified-Since")
    if if_modified_since:
        # For simulation, just return 304 if any date is provided
        return make_response("", 304)

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


@app.route("/digest-auth/<user>/<password>")
def digest_auth(user, password):
    # This is a very simplified mock of Digest auth challenge
    auth = request.headers.get("Authorization")
    if auth and "Digest" in auth and f'username="{user}"' in auth:
        return jsonify({"authenticated": True, "user": user})
    
    # Send challenge
    nonce = "dcd98b7102dd2f0e8b11d0f600bfb0c093"
    opaque = "5ccc069c403ebaf9f0171e9517f40e41"
    header = f'Digest realm="Login", qop="auth", algorithm=MD5, nonce="{nonce}", opaque="{opaque}"'
    return make_response(
        "Unauthorized", 401, {"WWW-Authenticate": header}
    )


@app.route("/hsts")
def hsts_endpoint():
    resp = make_response("HSTS Enabled")
    resp.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return resp


@app.route("/mtls")
def mtls_endpoint():
    # In a real mTLS setup, we'd check request.environ.get('SSL_CLIENT_CERT')
    # but with Flask's simple dev server, we can't easily do that.
    # We'll just assume it's authenticated if the request reached here via the HTTPS port
    # and maybe look for some specific header we can set in the test to simulate.
    return jsonify({
        "authenticated": True,
        "certificate": "client.crt"
    })


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
    if code == 204:
        return make_response("", 204)
    return make_response(f"Status: {code}", code)


@app.route("/bearer")
def bearer_endpoint():
    auth = request.headers.get("Authorization")
    if auth and auth.startswith("Bearer "):
        token = auth.split(" ")[1]
        return jsonify({"authenticated": True, "token": token})
    return make_response("Unauthorized", 401, {"WWW-Authenticate": 'Bearer realm="Login"'})


@app.route("/dns-query", methods=["GET", "POST"])
def dns_query():
    # Mock DoH response (success)
    return Response(b"Mocked DoH binary response", content_type="application/dns-message")


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


@app.route("/multiple-headers")
def multiple_headers():
    resp = make_response(jsonify({"message": "Check headers"}))
    resp.headers.add("Set-Cookie", "cookie1=value1")
    resp.headers.add("Set-Cookie", "cookie2=value2")
    resp.headers.add("Link", "<http://example.com/rel1>; rel=\"next\"")
    resp.headers.add("Link", "<http://example.com/rel2>; rel=\"prev\"")
    return resp


@app.route("/chunked")
def chunked():
    def generate():
        for i in range(5):
            yield f"chunk {i}\n"
            time.sleep(0.1)
    return Response(generate(), content_type='text/plain')


@app.route("/redirect-303", methods=["GET", "POST", "PUT", "DELETE"])
def redirect_303():
    # 303 See Other: Always converts to GET
    return redirect("/get", code=303)


@app.route("/redirect-relative")
def redirect_relative():
    resp = make_response("", 302)
    resp.headers["Location"] = "/get"
    return resp


@app.route("/post-data-raw", methods=["POST"])
def post_data_raw():
    return jsonify({"data": request.get_data(as_text=True)})


@app.route("/cookies/domain")
def cookies_domain():
    resp = make_response(jsonify({"message": "Setting domain cookie"}))
    # Note: For local testing, domain must match exactly or be omitted
    resp.set_cookie("domain_cookie", "domain_val", domain="127.0.0.1")
    return resp


@app.route("/cookies/expire")
def cookies_expire():
    resp = make_response(jsonify({"message": "Setting cookies"}))
    # Set a cookie that expires in the past
    resp.set_cookie("expired_cookie", "expired_val", max_age=-1)
    # Set a cookie that expires in the future
    resp.set_cookie("valid_cookie", "valid_val", max_age=3600)
    return resp


@app.route("/decompressed")
def decompressed_endpoint():
    # Flask with standard setup might not automatically compress unless we use an extension
    # but we can manually return a gzipped body if we want to test curl's decompression.
    import gzip
    content = json.dumps({"message": "this was compressed"}).encode('utf-8')
    out = gzip.compress(content)
    resp = make_response(out)
    resp.headers['Content-Encoding'] = 'gzip'
    resp.headers['Content-Type'] = 'application/json'
    return resp


@app.route("/content-disposition")
def content_disposition():
    resp = make_response("This is a file content")
    resp.headers["Content-Disposition"] = 'attachment; filename="remote-file.txt"'
    return resp


@app.route("/remote-time")
def remote_time():
    resp = make_response("Check my timestamp")
    # Set Last-Modified to a fixed date
    resp.headers["Last-Modified"] = "Wed, 21 Oct 2015 07:28:00 GMT"
    return resp


@app.route("/cookies/path")
def cookies_path():
    resp = make_response(jsonify({"message": "Setting path cookies"}))
    resp.set_cookie("path_cookie_root", "root_val", path="/")
    resp.set_cookie("path_cookie_sub", "sub_val", path="/cookies/path/sub")
    return resp


@app.route("/cookies/path/sub")
def cookies_path_sub():
    return jsonify({"cookies": dict(request.cookies)})


@app.route("/post-form-type", methods=["POST"])
def post_form_type():
    files_info = {}
    for name in request.files.keys():
        file_list = request.files.getlist(name)
        if len(file_list) > 1:
            files_info[name] = [{
                "filename": f.filename,
                "content_type": f.content_type,
                "data": f.read().decode('utf-8', errors='ignore')
            } for f in file_list]
        else:
            file = file_list[0]
            files_info[name] = {
                "filename": file.filename,
                "content_type": file.content_type,
                "data": file.read().decode('utf-8', errors='ignore')
            }
    
    form_info = {}
    for key in request.form.keys():
        val_list = request.form.getlist(key)
        form_info[key] = val_list if len(val_list) > 1 else val_list[0]

    return jsonify({
        "form": form_info,
        "files": files_info
    })


@app.route("/large-response")
def large_response():
    # Return 1MB of data
    return "X" * (1024 * 1024)


@app.route("/slow-response")
def slow_response():
    def generate():
        for i in range(10):
            yield f"part {i}\n"
            time.sleep(0.5)
    return Response(generate(), content_type='text/plain')


@app.route("/redirect-301-post", methods=["GET", "POST"])
def redirect_301_post():
    return redirect("/post", code=301)


@app.route("/redirect-302-post", methods=["GET", "POST"])
def redirect_302_post():
    return redirect("/post", code=302)


@app.route("/redirect-303-post", methods=["GET", "POST"])
def redirect_303_post():
    return redirect("/post", code=303)


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
# Simple TCP CONNECT proxy (Test 83)
# ---------------------------------------------------------------------------

def run_connect_proxy(port):
    """A minimal TCP-level CONNECT proxy for tunneling."""
    server = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind(("::", port))
    except Exception as e:
        print(f"CONNECT proxy bind failed: {e}")
        return
    server.listen(5)
    while True:
        client, _ = server.accept()
        def tunnel(c):
            remote = None
            try:
                data = c.recv(4096)
                if data.startswith(b"CONNECT"):
                    # Format: CONNECT target:port HTTP/1.1
                    parts = data.split(b" ")
                    if len(parts) > 1:
                        target = parts[1].decode().split(":")
                        host = target[0]
                        port_num = int(target[1])
                        remote = socket.create_connection((host, port_num))
                        c.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                        def forward(src, dst):
                            try:
                                while True:
                                    d = src.recv(4096)
                                    if not d: break
                                    dst.sendall(d)
                            except: pass
                            finally:
                                try: src.close()
                                except: pass
                                try: dst.close()
                                except: pass
                        t1 = threading.Thread(target=forward, args=(c, remote), daemon=True)
                        t2 = threading.Thread(target=forward, args=(remote, c), daemon=True)
                        t1.start()
                        t2.start()
                        # No join needed as we want them to run in parallel and they will close each other
                else:
                    c.close()
            except:
                if c: c.close()
                if remote: remote.close()
        threading.Thread(target=tunnel, args=(client,), daemon=True).start()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_https(port):
    """Run a second Flask instance with a self-signed certificate."""
    cert_path = "server.crt"
    key_path = "server.key"
    if not os.path.exists(cert_path) or not os.path.exists(key_path):
        generate_cert(cert_path, key_path)
    app.run(host="0.0.0.0", port=port, ssl_context=(cert_path, key_path), use_reloader=False)


def run_mtls(port):
    """Run a third Flask instance with mTLS enabled."""
    cert_path = "server.crt"
    key_path = "server.key"
    if not os.path.exists(cert_path) or not os.path.exists(key_path):
        generate_cert(cert_path, key_path)
    
    # Create SSL context that REQUIRES a client certificate
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert_path, key_path)
    # We trust the server's own cert as a CA for the test client certs
    context.load_verify_locations(cafile=cert_path)
    context.verify_mode = ssl.CERT_REQUIRED
    
    app.run(host="0.0.0.0", port=port, ssl_context=context, use_reloader=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Local httpbin-like test server")
    parser.add_argument("--port", type=int, default=8080, help="HTTP port (default 8080)")
    parser.add_argument("--https-port", type=int, default=8443, help="HTTPS port (default 8443)")
    parser.add_argument("--mtls-port", type=int, default=8444, help="mTLS port (default 8444)")
    parser.add_argument("--proxy-port", type=int, default=8081, help="CONNECT proxy port (default 8081)")
    args = parser.parse_args()

    # Generate certificates once before starting threads
    cert_path = "server.crt"
    key_path = "server.key"
    if not os.path.exists(cert_path) or not os.path.exists(key_path):
        generate_cert(cert_path, key_path)

    # Start HTTPS server in a background thread
    https_thread = threading.Thread(target=run_https, args=(args.https_port,), daemon=True)
    https_thread.start()

    # Start mTLS server in a background thread
    mtls_thread = threading.Thread(target=run_mtls, args=(args.mtls_port,), daemon=True)
    mtls_thread.start()

    # Start CONNECT proxy in a background thread
    proxy_thread = threading.Thread(target=run_connect_proxy, args=(args.proxy_port,), daemon=True)
    proxy_thread.start()

    # Start HTTP server (foreground)
    app.run(host="0.0.0.0", port=args.port, use_reloader=False)
