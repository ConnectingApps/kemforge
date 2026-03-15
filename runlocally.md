Here are the step-by-step commands to manually test everything:

#### Step 1: Set up the virtual environment (one-time)

```bash
cd /home/daan-acohen/repos/KemForge
python3 -m venv .venv
.venv/bin/pip install flask cryptography
```

#### Step 2: Start the Flask test server

```bash
.venv/bin/python test_server.py
```

This starts:
- **HTTP** on `http://127.0.0.1:8080`
- **HTTPS** (self-signed cert) on `https://127.0.0.1:8443`
- **mTLS** (client certificate required) on `https://127.0.0.1:8444`

> Leave this running in its own terminal.

#### Step 3: Run the PowerShell test suite (in a second terminal)

```bash
cd /home/daan-acohen/repos/KemForge
pwsh -File test_curl.ps1 ./kemforge
```

This runs all tests against the local Flask server using `kemforge`.

To test against `curl` as a baseline:

```bash
pwsh -File test_curl.ps1 curl
```

---

### Optional: Test individual endpoints manually with kemforge

While the Flask server is running, you can hit individual endpoints directly:

```bash
# Simple GET
./kemforge -s http://127.0.0.1:8080/get

# POST with form data
./kemforge -s -d "param1=val1&param2=val2" http://127.0.0.1:8080/post

# Basic auth
./kemforge -s -u user:password http://127.0.0.1:8080/basic-auth/user/password

# Custom headers
./kemforge -s -H "X-Custom-Header: MyValue" http://127.0.0.1:8080/headers

# Insecure SSL (self-signed cert)
./kemforge -s -k https://127.0.0.1:8443/get

# Delay endpoint
./kemforge -s http://127.0.0.1:8080/delay/2

# Range request
./kemforge -s -r 0-50 http://127.0.0.1:8080/range/1024
```

---

### Summary of commands

| Step | Command | Terminal |
|------|---------|----------|
| Setup (once) | `python3 -m venv .venv && .venv/bin/pip install flask cryptography` | any |
| Start server | `.venv/bin/python test_server.py` | terminal 1 |
| Run all tests | `pwsh -File test_curl.ps1 ./kemforge` | terminal 2 |
| Stop server | `Ctrl+C` in terminal 1 | terminal 1 |

> **Note:** The `test_curl.ps1` script automatically starts and stops the Flask server when you run it, so Steps 2 and 3 can be combined into just Step 3 if you prefer the automated approach. The manual server start is useful when you want to test individual curl commands yourself.