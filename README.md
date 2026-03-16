# KemForge

**KemForge** is a modern, curl-compatible CLI tool for making web requests — built from the ground up with **Post-Quantum Cryptography (PQC)** support. It is the security-first successor to curl, designed to address the primary threat of the modern era: **quantum attacks**.

---

## Table of Contents

- [Why KemForge?](#why-kemforge)
- [TLS Data & PQC Feedback](#tls-data--pqc-feedback)
- [Curl Feature Compatibility](#curl-feature-compatibility)
- [Usage Examples](#usage-examples)
- [Installation](#installation)
- [Testing](#testing)
- [Sponsors](#sponsors)
- [License](#license)

---

## Why KemForge?

Traditional encryption algorithms (RSA, ECDH) that protect today's internet traffic are vulnerable to attacks by quantum computers. Adversaries are already harvesting encrypted data today with the intent to decrypt it once quantum computers become powerful enough — a strategy known as **"Harvest Now, Decrypt Later"**.

**Post-Quantum Cryptography (PQC)** refers to cryptographic algorithms designed to be secure against both classical and quantum computers. Standards such as **ML-KEM** (Module-Lattice-Based Key Encapsulation Mechanism, formerly known as CRYSTALS-Kyber) have been standardized by NIST to replace vulnerable key exchange mechanisms.

KemForge makes PQC accessible and effortless:

- **No dependency on system TLS libraries** — Unlike curl, which relies on the installed version of Schannel (Windows), OpenSSL (Linux), or Secure Transport (macOS) for PQC support, KemForge provides PQC out of the box on every platform, regardless of the underlying TLS library version.
- **Automatic PQC detection** — Every HTTPS request returns TLS metadata indicating whether PQC was used. If PQC is not negotiated, KemForge warns you that the server is not protected against quantum attacks.
- **Drop-in curl replacement** — KemForge supports all common curl features and flags, so you can switch seamlessly.

---

## TLS Data & PQC Feedback

Every HTTPS request made with KemForge outputs **TLS Data** to stderr, giving you immediate insight into the security of your connection:

```
* TLS DATA:
* TlsVersion: 1.3
* Cipher:     TLS_AES_128_GCM_SHA256
* KeyExchangeGroup: X25519MLKEM768
* This server supports post quantum cryptography so the server has protection against quantum attacks.
```

If the server does **not** support PQC, you will see a warning:

```
* TLS DATA:
* TlsVersion: 1.3
* Cipher:     TLS_AES_128_GCM_SHA256
* KeyExchangeGroup: X25519
* This server is not protected against quantum attacks as the key exchange group does not contain MLKEM.
```

> **Note:** If PQC is not used, it is caused by the server's configuration — not KemForge. KemForge always negotiates PQC when the server supports it.

---

## Curl Feature Compatibility

KemForge supports all common curl features, including but not limited to:

| Feature | Flags |
|---|---|
| GET / POST / PUT / PATCH / DELETE | `-X`, `-d`, `--data-raw`, `--json` |
| Custom headers | `-H` |
| File uploads (multipart) | `-F` |
| Follow redirects | `-L`, `--max-redirs`, `--post301`, `--post302`, `--post303` |
| Authentication | `-u` (Basic), `--digest` |
| Cookies | `-b`, `-c` (cookie jar) |
| TLS / SSL | `-k` (insecure), `--cacert`, `--cert`, `--key`, `--pinnedpubkey` |
| Proxy support | `-x`, `--noproxy`, `--proxy-user` |
| Output control | `-o`, `-O`, `-i`, `-I`, `-s`, `-v`, `-w`, `-D` |
| Transfer control | `-C` (resume), `-r` (range), `--limit-rate`, `--compressed` |
| Timeouts & retries | `-m`, `--connect-timeout`, `--retry`, `--retry-delay` |
| Parallel transfers | `-Z` |
| DNS & networking | `--resolve`, `--doh-url`, `-4`, `-6`, `--unix-socket` |
| Config files | `-K` |
| HTTP versions | `--http1.1`, HTTP/2 by default |

For a complete specification with input/output examples, see [CURL_FEATURES.md](CURL_FEATURES.md).

---

## Usage Examples

### Simple GET request
```bash
kemforge https://example.com
```

### GET request with custom headers
```bash
kemforge -H "Authorization: Bearer mytoken" https://api.example.com/data
```

### POST request with JSON data
```bash
kemforge --json '{"key": "value"}' https://api.example.com/items
```

### POST request with form data
```bash
kemforge -d "user=admin&pass=secret" https://example.com/login
```

### File upload
```bash
kemforge -F "file=@document.pdf" https://example.com/upload
```

### Follow redirects with verbose output
```bash
kemforge -L -v https://example.com
```

### HEAD request (show headers only)
```bash
kemforge -I https://www.google.com
```

### Use a proxy
```bash
kemforge -x http://proxy:8080 https://example.com
```

### Insecure mode (skip certificate verification)
```bash
kemforge -k https://self-signed.example.com
```

### Save output to file
```bash
kemforge -o output.html https://example.com
```

### Parallel transfers
```bash
kemforge -Z https://example.com https://example.org
```

### Retry on failure
```bash
kemforge --retry 3 --retry-delay 2 https://flaky-api.example.com
```

---

## Installation

### Ubuntu / Debian

1. Install Go (if not already installed):

```bash
sudo apt update
sudo apt install -y golang-go
```

2. Ensure the Go bin directory is in your PATH:

```bash
echo 'export PATH="$PATH:$(go env GOBIN):$(go env GOPATH)/bin"' >> ~/.bashrc
source ~/.bashrc
```

3. Install kemforge:

```bash
go install github.com/ConnectingApps/kemforge@latest
```

### macOS

1. Install Go (if not already installed) using [Homebrew](https://brew.sh/):

```bash
brew install go
```

2. Ensure the Go bin directory is in your PATH:

```bash
echo 'export PATH="$PATH:$(go env GOBIN):$(go env GOPATH)/bin"' >> ~/.zshrc
source ~/.zshrc
```

3. Install kemforge:

```bash
go install github.com/ConnectingApps/kemforge@latest
```

### Windows

1. Install Go by downloading the installer from [https://go.dev/dl/](https://go.dev/dl/) and running it. The installer adds Go to your PATH automatically.

2. Ensure the Go bin directory is in your PATH. Open PowerShell and run:

```powershell
$GoBin = go env GOBIN
$GoPath = go env GOPATH
$BinPath = if ($GoBin) { $GoBin } else { "$GoPath\bin" }
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$BinPath", "User")
```

Then restart your terminal for the change to take effect.

3. Install kemforge:

```powershell
go install github.com/ConnectingApps/kemforge@latest
```

### After installation

Once installed, kemforge can be used just like curl:

```bash
kemforge -I https://www.google.com
```

### Build from source

Requires **Go 1.25+**.

```bash
git clone https://github.com/ConnectingApps/kemforge.git
cd kemforge
go build -v .
```

This produces the `kemforge` binary (or `kemforge.exe` on Windows).

---

## Testing

KemForge uses a two-stage testing strategy, as reflected in the CI/CD pipeline:

### Stage 1: Verify the test infrastructure against curl

Before testing KemForge itself, the test script and Python test server are validated against standard `curl` to ensure the test harness is correct:

```bash
# Create a Python virtual environment and install dependencies
python -m venv .venv
.venv/bin/pip install flask cryptography    # Linux/macOS
# .venv\Scripts\pip install flask cryptography  # Windows

# Run tests against curl to verify the test script and server
pwsh -File test_curl.ps1 curl
```

This step ensures that `test_curl.ps1` (the PowerShell test runner) and `test_server.py` (the local Flask test server) work correctly — any failure here is a problem with the test infrastructure, not KemForge.

### Stage 2: Build and test KemForge

Once the test infrastructure is verified, KemForge is built and tested against the same test suite:

```bash
# Build
go build -v .

# Run the same test suite against the KemForge binary
pwsh -File test_curl.ps1 ./kemforge          # Linux/macOS
# pwsh -File test_curl.ps1 ./kemforge.exe    # Windows
```

The test script starts a local Flask test server (`test_server.py`) automatically — no external services are required.

### CI/CD Pipeline

The GitHub Actions pipeline (`.github/workflows/go.yml`) runs both stages across **Ubuntu**, **Windows**, and **macOS** to ensure cross-platform compatibility.

---

## Sponsors

KemForge is an open-source project that relies on community support. If you find KemForge useful, please consider sponsoring us on [Open Collective](https://opencollective.com/connecting-apps). Your sponsorship helps us maintain and improve the project — and as a sponsor, you can get your company logo featured right here on this README page.

---

## License

See [LICENSE](LICENSE) for details.
