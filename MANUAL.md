# KemForge Manual

KemForge is a powerful, modern command-line tool designed for making HTTP requests with a focus on security, efficiency, and ease of use. It is highly compatible with `curl` but includes modern features like native Post-Quantum Cryptography (ML-KEM) and built-in parallel transfer support.

## Basic Usage

The simplest way to fetch a resource:
```bash
kemforge https://example.com
```

### 1. Saving Output
Save the response to a file with `-o` or use the remote filename with `-O`:
```bash
kemforge -o index.html https://example.com
kemforge -O https://example.com/logo.png
```

### 2. Sending Custom Headers
Add custom HTTP headers with the `-H` flag:
```bash
kemforge -H "Authorization: Bearer mytoken" -H "Accept: application/json" https://api.example.com/data
```

### 3. POST Data
Send form-encoded data with `-d` (shorthand for `--data`):
```bash
kemforge -d "name=Alice&status=active" https://httpbin.org/post
```

Send literal JSON data with the `--json` flag:
```bash
kemforge --json '{"id": 123, "type": "test"}' https://httpbin.org/post
```

For large data or to preserve newlines as-is, use `--data-raw`:
```bash
kemforge --data-raw "line1\nline2" https://httpbin.org/post
```

### 4. Following Redirects
Use `-L` to automatically follow HTTP redirects:
```bash
kemforge -L http://google.com
```

### 5. Verbose Mode & Header Inspection
Use `-v` to see detailed information about the request and response, including TLS handshake details (like PQC groups) and headers:
```bash
kemforge -v https://example.com
```

To include only the response headers in the output, use `-i`:
```bash
kemforge -i https://example.com
```

To show only the headers and skip the body (HEAD request), use `-I`:
```bash
kemforge -I https://example.com
```

### 6. Authentication
Provide basic authentication credentials with `-u`:
```bash
kemforge -u "username:password" https://protected.example.com
```

### 7. Cookies
Send cookies from a string or file with `-b`, and save received cookies to a jar file with `-c`:
```bash
kemforge -b "sessionid=12345" https://example.com
kemforge -c cookie_jar.txt https://example.com
```

### 8. Parallel Transfers
Speed up multiple requests by running them in parallel with `-Z`:
```bash
kemforge -Z https://example.com/file1 https://example.com/file2 https://example.com/file3
```

### 9. Post-Quantum Cryptography (PQC)
KemForge automatically prefers PQC-enabled TLS connections (using ML-KEM/X25519MLKEM768) when supported by the server. No special flags are needed. You can verify the PQC status by checking the verbose output (`-v`) for the key exchange group.

## Reference Table of Common Options

| Option | Description |
| :--- | :--- |
| `-A, --user-agent <agent>` | Set a custom User-Agent string (Default: `kemforge/1.0`) |
| `-b, --cookie <data>` | Send cookies from string or file |
| `-c, --cookie-jar <file>` | Write cookies to a file after the operation |
| `-C, --continue-at <offset>` | Resume a transfer at a given offset |
| `-d, --data <data>` | HTTP POST data |
| `-D, --dump-header <file>` | Write received headers to a file |
| `-f, --fail` | Fail silently on server errors (no output) |
| `-F, --form <data>` | Multipart/form-data POST |
| `-G, --get` | Put the post data in the URL and use GET |
| `-H, --header <header>` | Pass custom headers |
| `-i, --include` | Include response headers in output |
| `-I, --head` | Fetch headers only (HEAD request) |
| `-k, --insecure` | Allow insecure SSL connections (skip verification) |
| `-L, --location` | Follow HTTP redirects |
| `-o, --output <file>` | Write output to a specific file |
| `-O, --remote-name` | Use the remote file name for output |
| `-r, --range <range>` | Retrieve only the bytes within RANGE |
| `-s, --silent` | Silent mode (no progress info) |
| `-u, --user <user:pass>` | Server username and password |
| `-v, --verbose` | Verbose output (including TLS details) |
| `-x, --proxy <proxy>` | Use a proxy server |
| `-X, --request <method>` | Specify the HTTP method (GET, POST, etc.) |
| `-Z, --parallel` | Run multiple transfers in parallel |
| `--json <data>` | Send literal JSON data |
| `--manual` | Show this manual |
| `--help` | Show brief help |
| `--version` | Show version number and exit |

---
For more advanced usage and all available options, run `kemforge --help`.
