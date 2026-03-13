# Curl Features Reference

This document describes the main features of `curl` through concrete input and output examples, structured as test cases. This can serve as a specification or a reference for curl-like CLI tools such as KemForge.

---

## 1. Simple GET Request
**Description**: Performs a standard HTTP GET request to fetch a resource.
**Input**:
```bash
curl -s httpbin.org/get
```
**Output**:
```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
    "X-Amzn-Trace-Id": "Root=1-69b3fe48-2a939db2305fb22a33429891"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/get"
}
```

---

## 2. Custom Headers
**Description**: Sends custom HTTP headers with the request using the `-H` flag.
**Input**:
```bash
curl -s -H "X-Custom-Header: MyValue" httpbin.org/headers
```
**Output**:
```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
    "X-Amzn-Trace-Id": "Root=1-69b3fe4b-49aacb92354a47c00e402bc1",
    "X-Custom-Header": "MyValue"
  }
}
```

---

## 3. POST Request with Form Data
**Description**: Sends a POST request with data encoded as `application/x-www-form-urlencoded` using the `-d` flag.
**Input**:
```bash
curl -s -d "param1=val1&param2=val2" httpbin.org/post
```
**Output**:
```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {
    "param1": "val1",
    "param2": "val2"
  },
  "headers": {
    "Accept": "*/*",
    "Content-Length": "23",
    "Content-Type": "application/x-www-form-urlencoded",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
    "X-Amzn-Trace-Id": "Root=1-69b3fe4e-23ccd0c84dd3b4387ee73e60"
  },
  "json": null,
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/post"
}
```

---

## 4. Multi-part Form Data (File Upload)
**Description**: Uploads a file using `multipart/form-data` with the `-F` flag.
**Input**:
```bash
# Assuming test.txt contains "This is a test file for curl.\n"
curl -s -F "file=@test.txt" httpbin.org/post
```
**Output**:
```json
{
  "args": {},
  "data": "",
  "files": {
    "file": "This is a test file for curl.\n"
  },
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Content-Length": "228",
    "Content-Type": "multipart/form-data; boundary=------------------------W7O3qXtqXLdxVDpqhSBbGx",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
    "X-Amzn-Trace-Id": "Root=1-69b3fe5d-4deb01da007546f7475b42e6"
  },
  "json": null,
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/post"
}
```

---

## 5. Basic Authentication
**Description**: Provides user credentials for Basic Authentication using the `-u` flag.
**Input**:
```bash
curl -s -u user:password httpbin.org/basic-auth/user/password
```
**Output**:
```json
{
  "authenticated": true,
  "user": "user"
}
```

---

## 6. Following Redirects
**Description**: Automatically follows 3xx HTTP redirects using the `-L` flag.
**Input**:
```bash
curl -s -L httpbin.org/redirect-to?url=http://httpbin.org/get
```
**Output**:
```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
    "X-Amzn-Trace-Id": "Root=1-69b3fe58-5880996f6412f27c780df320"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/get"
}
```

---

## 7. Cookie Handling
**Description**: Saves received cookies to a file (`-c`) and sends them back in subsequent requests (`-b`).
**Input**:
```bash
# Set a cookie and save it
curl -s -L -c cookies.txt httpbin.org/cookies/set/session/123456
# Send the saved cookie back
curl -s -b cookies.txt httpbin.org/cookies
```
**Output**:
```json
{
  "cookies": {
    "session": "123456"
  }
}
```

---

## 8. Verbose Output
**Description**: Displays the complete request and response lifecycle, including headers and connection details, using the `-v` flag.
**Input**:
```bash
curl -v -s httpbin.org/get
```
**Output (Excerpt)**:
```text
* Host httpbin.org:80 was resolved.
* Connected to httpbin.org (54.197.177.21) port 80
> GET /get HTTP/1.1
> Host: httpbin.org
> User-Agent: curl/8.5.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Date: Fri, 13 Mar 2026 12:08:53 GMT
< Content-Type: application/json
< Content-Length: 253
< Connection: keep-alive
< Server: gunicorn/19.9.0
< Access-Control-Allow-Origin: *
< Access-Control-Allow-Credentials: true
<
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
    "X-Amzn-Trace-Id": "Root=1-69b3fe48-2a939db2305fb22a33429891"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/get"
}
```

---

## 9. Custom User-Agent
**Description**: Overrides the default curl User-Agent string using the `-A` flag.
**Input**:
```bash
curl -s -A "MyTestAgent" httpbin.org/user-agent
```
**Output**:
```json
{
  "user-agent": "MyTestAgent"
}
```

---

## 10. Saving Output to File
**Description**: Saves the response body to a specified file instead of printing to stdout using the `-o` flag.
**Input**:
```bash
curl -s -o response.json httpbin.org/get
```
**Output**:
(No terminal output. The file `response.json` is created with the response content.)

---

## 11. HEAD Request
**Description**: Performs an HTTP HEAD request to fetch only the headers of a resource without the body, using the `-I` flag.
**Input**:
```bash
curl -s -I httpbin.org/get
```
**Output**:
```text
HTTP/1.1 200 OK
Date: Fri, 13 Mar 2026 12:14:15 GMT
Content-Type: application/json
Content-Length: 253
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```

---

## 12. Custom HTTP Method
**Description**: Uses a specific HTTP method for the request (e.g., DELETE, PUT, PATCH) using the `-X` flag.
**Input**:
```bash
curl -s -X DELETE httpbin.org/delete
```
**Output**:
```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0"
  },
  "json": null,
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/delete"
}
```

---

## 13. Sending JSON Data
**Description**: Sends a POST request with a JSON payload, specifying the `Content-Type: application/json` header.
**Input**:
```bash
curl -s -H "Content-Type: application/json" -d '{"key": "value"}' httpbin.org/post
```
**Output**:
```json
{
  "args": {},
  "data": "{\"key\": \"value\"}",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Content-Type": "application/json",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0"
  },
  "json": {
    "key": "value"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/post"
}
```

---

## 14. Query Parameters with URL Encoding
**Description**: Sends a GET request with multiple query parameters that are automatically URL-encoded using the `--data-urlencode` flag combined with `-G`.
**Input**:
```bash
curl -s --data-urlencode "name=John Doe" --data-urlencode "city=New York" -G httpbin.org/get
```
**Output**:
```json
{
  "args": {
    "city": "New York",
    "name": "John Doe"
  },
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/get?name=John+Doe&city=New+York"
}
```

---

## 15. Write-out Format (HTTP Status Code)
**Description**: Extracts specific information from the request/response lifecycle (like the HTTP status code) using the `-w` flag.
**Input**:
```bash
curl -s -o /dev/null -w "%{http_code}\n" httpbin.org/get
```
**Output**:
```text
200
```

---

## 16. Silent Mode with Errors
**Description**: Suppresses the progress meter but still shows error messages if the request fails, using the `-s` and `-S` flags together.
**Input**:
```bash
curl -sS http://non-existent-domain.com
```
**Output**:
```text
curl: (6) Could not resolve host: non-existent-domain.com
```

---

## 17. Insecure SSL (Ignore Certificate Errors)
**Description**: Allows `curl` to connect to a server with an invalid or self-signed SSL certificate using the `-k` (or `--insecure`) flag.
**Input**:
```bash
curl -s -k https://self-signed.badssl.com/
```
**Output**:
(Standard HTML response body from the server, which would have failed without `-k`.)

---

## 18. Connect Timeout
**Description**: Limits the maximum time in seconds allowed for the initial connection to the server using the `--connect-timeout` flag.
**Input**:
```bash
curl -s --connect-timeout 2 httpbin.org/delay/5
```
**Output**:
(If the connection takes more than 2 seconds, curl will exit with an error.)

---

## 19. Using a Proxy
**Description**: Routes the request through a specified proxy server using the `-x` flag.
**Input**:
```bash
curl -s -x http://proxy.example.com:8080 httpbin.org/get
```
**Output**:
(The response from httpbin.org, delivered via the proxy server.)

---

## 20. Include Headers in Output
**Description**: Includes the HTTP response headers in the output before the body using the `-i` flag.
**Input**:
```bash
curl -s -i httpbin.org/get
```
**Output**:
```text
HTTP/1.1 200 OK
Date: Fri, 13 Mar 2026 12:15:25 GMT
Content-Type: application/json
Content-Length: 253
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true

{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/get"
}
```

---

## 21. Simple HEAD Request
**Description**: Performs a basic HTTP HEAD request using only the `-I` flag. This is the simplest and most common way to retrieve headers only.
**Input**:
```bash
curl -I httpbin.org/get
```
**Output**:
```text
HTTP/1.1 200 OK
Date: Fri, 13 Mar 2026 12:20:22 GMT
Content-Type: application/json
Content-Length: 253
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```

---

## 22. Compressed Response
**Description**: Requests the server to send the response in a compressed format (e.g., gzip, deflate) using the `--compressed` flag. Curl will automatically decompress the response for you.
**Input**:
```bash
curl -s -I --compressed httpbin.org/get
```
**Output**:
```text
HTTP/1.1 200 OK
Date: Fri, 13 Mar 2026 12:20:42 GMT
Content-Type: application/json
Content-Length: 304
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```
(Note: The `Content-Length` might differ from non-compressed requests depending on server implementation.)

---

## 23. Range Request (Partial Content)
**Description**: Requests a specific byte range of a resource using the `-r` (or `--range`) flag. The server should respond with `206 Partial Content`.
**Input**:
```bash
curl -s -r 0-50 httpbin.org/range/1024
```
**Output**:
```text
abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx
```
(Output shows the first 51 bytes of the generated random data from httpbin.org.)

---

## 24. Saving with Remote Filename
**Description**: Saves the response to a local file using the same name as the remote resource using the `-O` (uppercase O) flag.
**Input**:
```bash
# This will save the content to a file named 'get'
curl -s -O httpbin.org/get
```
**Output**:
(No terminal output. A file named `get` is created with the response content.)

---

## 25. Maximum Time for Request
**Description**: Limits the total time in seconds that the entire operation is allowed to take using the `--max-time` (or `-m`) flag.
**Input**:
```bash
# This will time out since the server is instructed to delay for 5 seconds
curl -s --max-time 2 httpbin.org/delay/5
```
**Output**:
(No output or error message depending on flags, but curl will exit with code 28 after 2 seconds.)

---

## 26. Retry Logic
**Description**: Retries the request if it fails with a transient error (e.g., 5xx status codes or connection drops) using the `--retry` flag.
**Input**:
```bash
# Retries 3 times if the server returns a 500 error.
curl -s --retry 3 httpbin.org/status/500
```
**Output**:
(The response from the server after the last retry, or an error if all retries fail.)

---

## 27. Fail on Server Error
**Description**: Returns a non-zero exit code if the server returns an HTTP error code (4xx or 5xx), using the `-f` (or `--fail`) flag.
**Input**:
```bash
curl -s -f httpbin.org/status/404
```
**Output**:
(No output, but curl will exit with code 22.)

---

## 28. Referer Header
**Description**: Sends the `Referer` header with the request using the `-e` (or `--referer`) flag.
**Input**:
```bash
curl -s -e "http://example.com" httpbin.org/headers
```
**Output**:
```json
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    "Referer": "http://example.com",
    "User-Agent": "curl/8.5.0"
  }
}
```

---

## 29. Limit Redirects
**Description**: Limits the maximum number of redirects to follow using the `--max-redirs` flag.
**Input**:
```bash
curl -s -L --max-redirs 2 httpbin.org/redirect/3
```
**Output**:
```text
curl: (47) Maximum (2) redirects followed
```

---

## 30. Bearer Token Authentication
**Description**: Sends a Bearer token in the `Authorization` header.
**Input**:
```bash
curl -s -H "Authorization: Bearer my-secret-token" httpbin.org/bearer
```
**Output**:
```json
{
  "authenticated": true,
  "token": "my-secret-token"
}
```

---

## 31. Multiple URL Fetching
**Description**: Fetches multiple URLs in a single command.
**Input**:
```bash
curl -s httpbin.org/get httpbin.org/headers
```
**Output**:
(The concatenated output of both requests.)

---

## 32. Configuration Files
**Description**: Reads command-line arguments from a configuration file using the `-K` (or `--config`) flag.
**Input**:
```bash
# Assuming config.txt contains:
# url = "httpbin.org/get"
# header = "X-My-Header: CustomValue"
curl -s -K config.txt
```
**Output**:
(The response from httpbin.org/get, including the custom header.)

---

## 33. Rate Limiting
**Description**: Limits the maximum transfer rate using the `--limit-rate` flag.
**Input**:
```bash
curl -s --limit-rate 10k httpbin.org/range/102400
```
**Output**:
(The 100KB file downloaded at a rate of 10KB/s, taking approximately 10 seconds.)

---

## 34. Parallel Downloads
**Description**: Downloads multiple URLs in parallel using the `-Z` (or `--parallel`) flag.
**Input**:
```bash
curl -s -Z httpbin.org/get httpbin.org/headers
```
**Output**:
(The responses from both URLs.)

---

## 35. Modern JSON Flag
**Description**: Sends a JSON request using the `--json` flag, which automatically sets `Content-Type` and `Accept` to `application/json`.
**Input**:
```bash
curl -s --json '{"foo": "bar"}' httpbin.org/post
```
**Output**:
```json
{
  "args": {},
  "data": "{\"foo\": \"bar\"}",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "application/json",
    "Content-Type": "application/json",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0"
  },
  "json": {
    "foo": "bar"
  },
  "origin": "94.215.21.151",
  "url": "http://httpbin.org/post"
}
```

---

## 36. Custom Resolve
**Description**: Overrides host resolution for a specific domain and port with a custom IP address using the `--resolve` flag.
**Input**:
```bash
curl -s --resolve example.com:80:127.0.0.1 http://example.com/get
```
**Output**:
(The response from the local server at 127.0.0.1, even though the URL uses example.com.)

---

## 37. Additional HTTP Methods (PUT and PATCH)
**Description**: Uses PUT and PATCH methods for requests using the `-X` flag.
**Input**:
```bash
curl -s -X PUT -d '{"update": "true"}' httpbin.org/put
curl -s -X PATCH -d '{"patch": "true"}' httpbin.org/patch
```
**Output**:
(The JSON response reflecting the method used and the data sent.)

---

## 38. Failed Authentication (Negative Testing)
**Description**: Verifies that incorrect credentials result in an unauthorized error (401).
**Input**:
```bash
curl -s -u user:wrongpassword httpbin.org/basic-auth/user/password
```
**Output**:
(Unauthorized message or 401 status code depending on flags.)

---

## 39. Dumping Headers to a File
**Description**: Saves only the response headers to a specified file using the `--dump-header` flag.
**Input**:
```bash
curl -s --dump-header headers.txt httpbin.org/get
```
**Output**:
(No terminal output. The file `headers.txt` is created with the response headers.)

---

## 40. Reading Data from Stdin
**Description**: Reads data from standard input to send in a POST request using the `-d @-` flag.
**Input**:
```bash
echo "data" | curl -s -d @- httpbin.org/post
```
**Output**:
(The JSON response reflecting the data sent via stdin.)

---

## 41. Header Suppression/Removal
**Description**: Removes a default header or sends an empty header by providing no value after the colon, using the `-H` flag.
**Input**:
```bash
curl -s -H "User-Agent:" httpbin.org/headers
```
**Output**:
(The JSON response showing the headers without the `User-Agent`.)

---

## 42. Enforcing HTTP Versions
**Description**: Forces the use of a specific HTTP version (e.g., HTTP/1.1) using the `--http1.1` flag.
**Input**:
```bash
curl -s --http1.1 httpbin.org/get
```
**Output**:
(The response delivered via the specified HTTP version.)

---

## 43. Resuming Downloads
**Description**: Continues a previously interrupted transfer from a specific offset using the `-C -` flag with `-o`.
**Input**:
```bash
curl -s -C - -o partial_file.txt httpbin.org/range/1024
```
**Output**:
(The remaining part of the file is appended to `partial_file.txt`.)

---

## 44. Expanded Write-out Variables
**Description**: Extracts multiple pieces of information about the request/response using more detailed variables in the `-w` flag.
**Input**:
```bash
curl -s -o /dev/null -w "Status: %{http_code}, Size: %{size_download}, Total Time: %{time_total}s\n" httpbin.org/get
```
**Output**:
```text
Status: 200, Size: 253, Total Time: 0.045s
```

---

## 45. Uploading Files via PUT
**Description**: Performs a binary file upload using the PUT method with the `-T` flag.
**Input**:
```bash
curl -s -T testfile.txt httpbin.org/put
```
**Output**:
(The JSON response reflecting the file upload.)

---

## 46. URL Globbing
**Description**: Fetches multiple resources by specifying a range or set of values in the URL using braces.
**Input**:
```bash
curl -s "httpbin.org/status/{200,404}"
```
**Output**:
(The responses for each of the specified status codes.)

---

## 47. Cumulative Headers (Multiple `-H`)
**Description**: Sends multiple custom HTTP headers using multiple `-H` flags.
**Input**:
```bash
curl -s -H "X-Header1: Val1" -H "X-Header2: Val2" httpbin.org/headers
```
**Output**:
```json
{
  "headers": {
    "X-Header1": "Val1",
    "X-Header2": "Val2"
  }
}
```

---

## 48. Concatenating Multiple Data Arguments (Multiple `-d`)
**Description**: Concatenates multiple `-d` arguments with an ampersand (`&`).
**Input**:
```bash
curl -s -d "user=admin" -d "session=active" httpbin.org/post
```
**Output**:
```json
{
  "form": {
    "session": "active",
    "user": "admin"
  }
}
```

---

## 49. URL-Embedded Credentials
**Description**: Extracts credentials from the URL and converts them to a Basic Authentication header.
**Input**:
```bash
curl -s http://user:password@httpbin.org/basic-auth/user/password
```
**Output**:
```json
{
  "authenticated": true,
  "user": "user"
}
```

---

## 50. Proxy Authentication
**Description**: Supports proxy authentication within the proxy URL.
**Input**:
```bash
curl -s -x http://puser:ppass@proxy.example.com:8080 httpbin.org/get
```
**Output**:
(Request is sent to proxy with `Proxy-Authorization: Basic ...` header.)

---

## 51. Redirect Method Conversion (301/302 vs 307/308)
**Description**: Handles method conversion during redirects. 301/302 converts POST to GET; 307/308 preserves it.
**Input**:
```bash
curl -s -L -d "data" httpbin.org/redirect-to?url=http://httpbin.org/get&status_code=302
```
**Output**:
(Subsequent request is a GET to /get)

---

## 52. Overriding the Host Header
**Description**: Overrides the default `Host` header using `-H`.
**Input**:
```bash
curl -s -H "Host: production.com" httpbin.org/headers
```
**Output**:
```json
{
  "headers": {
    "Host": "production.com"
  }
}
```

---

## 53. Binary Data via `--data-binary`
**Description**: Sends raw binary data without any processing or newline stripping.
**Input**:
```bash
curl -s --data-binary @file.bin httpbin.org/post
```
**Output**:
(The exact bytes from file.bin are sent in the request body.)

---

## 54. Customizing Cookie Storage (Cookies without File)
**Description**: Enables cookie handling for the current session without using a disk file by passing an empty string to `-b`.
**Input**:
```bash
curl -s -b "" httpbin.org/cookies/set/tmp/val httpbin.org/cookies
```
**Output**:
```json
{
  "cookies": {
    "tmp": "val"
  }
}
```

---

## 55. Mutual TLS (Client Certificates)
**Description**: Presents a client-side certificate for authentication using the `--cert` and `--key` flags.
**Input**:
```bash
curl -s --cert client.crt --key client.key -k https://127.0.0.1:8443/mtls
```
**Output**:
```json
{
  "authenticated": true,
  "certificate": "client.crt"
}
```

---

## 56. Negative SSL Verification
**Description**: Verifies that `curl` fails to connect to a server with an invalid or self-signed certificate *unless* the `-k` (or `--insecure`) flag is provided.
**Input**:
```bash
curl -s https://127.0.0.1:8443/get
```
**Output**:
```text
curl: (60) SSL certificate problem: self-signed certificate
```

---

## 57. HSTS Support
**Description**: Respects the `Strict-Transport-Security` header, which informs the client that all subsequent requests to the domain should be made via HTTPS.
**Input**:
```bash
# First request to fetch the HSTS header
curl -s -I http://127.0.0.1:8080/hsts
# Subsequent requests to the same domain (even via HTTP) are upgraded automatically by curl
```
**Output**:
```text
HTTP/1.1 200 OK
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

---

## 58. Digest Authentication
**Description**: Supports Digest Authentication, a more secure challenge-response mechanism than Basic Auth, using the `--digest` flag.
**Input**:
```bash
curl -s --digest -u user:password http://127.0.0.1:8080/digest-auth/user/password
```
**Output**:
```json
{
  "authenticated": true,
  "user": "user"
}
```

---

## 59. Netrc Support
**Description**: Automatically reads user credentials from a `.netrc` file (or specified file) using the `-n` (or `--netrc`) flag.
**Input**:
```bash
# Assuming .netrc contains: machine 127.0.0.1 login user password password
curl -s -n http://127.0.0.1:8080/basic-auth/user/password
```
**Output**:
```json
{
  "authenticated": true,
  "user": "user"
}
```

---

## 60. Environment Variable Proxy Support
**Description**: Respects standard environment variables like `http_proxy`, `https_proxy`, and `no_proxy` for routing requests.
**Input**:
```bash
export http_proxy=http://proxy.example.com:8080
curl -s http://127.0.0.1:8080/get
```
**Output**:
(The request is routed through the proxy defined in the environment.)

---

## 61. SOCKS Proxy Support
**Description**: Routes requests through SOCKS4 or SOCKS5 proxies using the `-x` flag.
**Input**:
```bash
curl -s -x socks5://localhost:9050 http://127.0.0.1:8080/get
```
**Output**:
(The request is routed through the SOCKS5 proxy.)

---

## 62. Proxy-Specific Authentication
**Description**: Provides credentials specifically for the proxy server using the `--proxy-user` flag, independent of the target server's authentication.
**Input**:
```bash
curl -s -x http://proxy:8080 --proxy-user puser:ppass http://127.0.0.1:8080/get
```
**Output**:
(Request is sent to the proxy with `Proxy-Authorization` header.)

---

## 63. IP Version Control (-4 / -6)
**Description**: Forces `curl` to use IPv4 or IPv6 specifically for address resolution and connection using the `-4` or `-6` flags.
**Input**:
```bash
curl -s -4 http://localhost:8080/get
```
**Output**:
(The connection is forced over IPv4.)

---

## 64. UNIX Domain Sockets
**Description**: Connects to a server via a UNIX domain socket instead of a network port using the `--unix-socket` flag.
**Input**:
```bash
curl -s --unix-socket /tmp/test.sock http://localhost/get
```
**Output**:
(The request is sent through the specified UNIX socket.)

---

## 65. DNS-over-HTTPS (DoH)
**Description**: Uses a custom DoH resolver for DNS lookups instead of the system default using the `--doh-url` flag.
**Input**:
```bash
curl -s --doh-url https://cloudflare-dns.com/dns-query http://example.com/get
```
**Output**:
(DNS lookup is performed via DoH before connecting to the server.)

---

## 66. Advanced Multipart Form Data (Metadata)
**Description**: Sends multiple multipart form fields with custom metadata like `type` and `filename` using the `-F` flag.
**Input**:
```bash
curl -s -F "file=@test.txt;type=text/plain;filename=remote.txt" http://127.0.0.1:8080/post
```
**Output**:
```json
{
  "files": {
    "file": {
      "filename": "remote.txt",
      "type": "text/plain",
      "content": "..."
    }
  }
}
```

---

## 67. Conditional GET
**Description**: Fetches a resource only if it has been modified after a specific time or if the ETag has changed, using the `-z` (or `--time-cond`) flag.
**Input**:
```bash
curl -s -z "Fri, 13 Mar 2026 12:00:00 GMT" http://127.0.0.1:8080/get
```
**Output**:
(Server returns `304 Not Modified` if the resource hasn't changed.)

---

## 68. Resuming with Fixed Offset
**Description**: Resumes a transfer starting from a manually specified byte offset using the `-C <offset>` flag.
**Input**:
```bash
curl -s -C 100 http://127.0.0.1:8080/range/1024
```
**Output**:
(The response starts from byte 100 of the requested resource.)

---

## 69. Expect 100-continue
**Description**: Verifies how the tool handles the `Expect: 100-continue` header, which is common in large POST requests.
**Input**:
```bash
curl -s -d "large data..." -H "Expect: 100-continue" http://127.0.0.1:8080/post
```
**Output**:
(Server responds with `100 Continue` before the client sends the data.)

---

## 70. URL Globbing with Brackets (Ranges)
**Description**: Fetches multiple resources using numeric or alphabetical ranges in the URL.
**Input**:
```bash
curl -s "http://127.0.0.1:8080/status/[200-201]"
```
**Output**:
(Requests for /status/200 and /status/201 are made.)

---

## 71. Comprehensive Write-out Variables
**Description**: Uses a wider set of variables with the `-w` flag to extract detailed request/response timing and metadata.
**Input**:
```bash
curl -s -o /dev/null -w "DNS: %{time_namelookup}, Connect: %{time_connect}, Size: %{size_download}, URL: %{url_effective}\n" http://127.0.0.1:8080/get
```
**Output**:
```text
DNS: 0.001, Connect: 0.002, Size: 253, URL: http://127.0.0.1:8080/get
```

---

## 72. Detailed Tracing
**Description**: Provides low-level protocol tracing for debugging using the `--trace` or `--trace-ascii` flags.
**Input**:
```bash
curl -s --trace-ascii trace.txt http://127.0.0.1:8080/get
```
**Output**:
(The file `trace.txt` contains the ASCII representation of the complete protocol exchange.)

---

### 73. Specific Redirect Handling (301, 308)
**Description**: Specifically tests permanent redirects (301 and 308) to ensure correct method preservation or conversion.
**Input**:
```bash
curl -s -L -d "data" http://127.0.0.1:8080/redirect-308
```
**Output**:
(The 308 redirect preserves the POST method and data in the subsequent request.)

---

### 74. Handling 204 No Content
**Description**: Verifies that the tool correctly handles responses with no body (204 No Content).
**Input**:
```bash
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/status/204
```
**Output**:
```text
204
```

---

### 75. Multiple Headers with Same Name (Server to Client)
**Description**: Tests how the tool handles receiving multiple headers with the same name from the server, such as multiple `Set-Cookie` or `Link` headers.
**Input**:
```bash
curl -s -i http://127.0.0.1:8080/multiple-headers
```
**Output**:
(Output includes multiple `Set-Cookie` and `Link` header lines.)

---

### 76. Chunked Transfer Encoding
**Description**: Verifies that the tool correctly handles and reassembles responses using `Transfer-Encoding: chunked`.
**Input**:
```bash
curl -s http://127.0.0.1:8080/chunked
```
**Output**:
(The reassembled content of all chunks.)

---

### 77. Decompression Body Verification
**Description**: Verifies that the tool correctly decompresses a gzipped response body when using the `--compressed` flag.
**Input**:
```bash
curl -s --compressed http://127.0.0.1:8080/decompressed
```
**Output**:
(The decompressed JSON body.)

---

### 78. 303 See Other Redirect
**Description**: Tests the `303 See Other` redirect, which should always convert the request method to `GET`.
**Input**:
```bash
curl -s -L -X POST -d "data" http://127.0.0.1:8080/redirect-303
```
**Output**:
(The response from the redirected URL, fetched via GET.)

---

### 79. Relative URL Redirects
**Description**: Verifies that the tool correctly handles a `Location` header that contains a relative path.
**Input**:
```bash
curl -s -L http://127.0.0.1:8080/redirect-relative
```
**Output**:
(The response from the target resource.)

---

### 80. Protocol Switching
**Description**: Tests redirects that move from `http://` to `https://`.
**Input**:
```bash
curl -s -L -k http://127.0.0.1:8080/redirect-to?url=https://127.0.0.1:8443/get
```
**Output**:
(The response from the HTTPS endpoint.)

---

### 81. --noproxy Support
**Description**: Tests the ability to bypass the proxy for specific domains using the `--noproxy` flag.
**Input**:
```bash
export http_proxy=http://invalid-proxy:9999
curl -s --noproxy 127.0.0.1 http://127.0.0.1:8080/get
```
**Output**:
(Successful response, bypassing the invalid proxy.)

---

### 82. Case-Insensitivity of Proxy Environment Variables
**Description**: Verifies that the tool respects proxy environment variables regardless of case (e.g., `all_proxy` vs `ALL_PROXY`). Note: On Linux, `HTTP_PROXY` may be ignored for security reasons, so `ALL_PROXY` is used for testing.
**Input**:
```bash
export ALL_PROXY=http://127.0.0.1:8080/proxy
curl -s http://example.com/get
```
**Output**:
(The request is routed through the proxy.)

---

### 83. HTTPS over HTTP Proxy (Tunneling)
**Description**: Tests `CONNECT` requests through a proxy to reach an HTTPS destination.
**Input**:
```bash
curl -s -k -x http://127.0.0.1:8081 https://127.0.0.1:8443/get
```
**Output**:
(Response from the HTTPS server delivered via the proxy tunnel.)

---

### 84. Exit Code Specificity
**Description**: Verifies that the tool returns specific exit codes for different types of failures (e.g., 6 for DNS failure).
**Input**:
```bash
curl -s http://non-existent-domain.invalid
```
**Output**:
(No stdout; exit code 6.)

---

### 85. Standard CLI Flags (--help, --version)
**Description**: Ensures the tool provides standard help and version information.
**Input**:
```bash
curl --help
curl --version
```
**Output**:
(Usage information and version details.)

---

### 86. Combining -i and -o
**Description**: Verifies behavior when including headers in output (`-i`) while saving to a file (`-o`).
**Input**:
```bash
curl -s -i -o response.txt http://127.0.0.1:8080/get
```
**Output**:
(Headers and body are saved to `response.txt`.)

---

### 87. Multiple -o flags for Multiple URLs
**Description**: Verifies that each URL can be saved to a specific file when fetching multiple URLs.
**Input**:
```bash
curl -s http://127.0.0.1:8080/get -o out1.txt http://127.0.0.1:8080/headers -o out2.txt
```
**Output**:
(Two files are created, each with the content of the respective URL.)

---

### 88. --data-raw Flag
**Description**: Sends data that starts with `@` as a literal string instead of a filename.
**Input**:
```bash
curl -s --data-raw "@literal" http://127.0.0.1:8080/post
```
**Output**:
(JSON response showing `@literal` in the data/form fields.)

---

### 89. Uploading from Stdin with -T -
**Description**: Tests uploading data from standard input using the `-T -` flag.
**Input**:
```bash
echo "upload data" | curl -s -T - http://127.0.0.1:8080/put
```
**Output**:
(JSON response reflecting the uploaded data.)

---

### 90. Multiple Headers with Same Name (Client to Server)
**Description**: Ensures that sending multiple `-H` flags with the same name results in all of them being sent.
**Input**:
```bash
curl -s -H "X-Multi: value1" -H "X-Multi: value2" http://127.0.0.1:8080/headers
```
**Output**:
(JSON response showing both values for the header.)

---

### 91. Cookie Domain and Path Scoping
**Description**: Verifies that cookies are only sent back if the request matches the cookie's domain and path.
**Input**:
```bash
curl -s -c cookies.txt http://127.0.0.1:8080/cookies/domain
curl -s -b cookies.txt http://127.0.0.1:8080/cookies
```
**Output**:
(JSON response showing the cookie was sent back if it matched.)

---

### 92. Cookie Expiration
**Description**: Verifies that the tool respects cookie expiration.
**Input**:
```bash
curl -s -c cookies.txt http://127.0.0.1:8080/cookies/expire
curl -s -b cookies.txt http://127.0.0.1:8080/cookies
```
**Output**:
(JSON response showing only non-expired cookies.)

---

### 93. Directory Management (`--create-dirs`)
**Description**: Automatically creates the local directory structure specified in the `-o` path if it doesn't exist.
**Input**:
```bash
curl -s --create-dirs -o nested/dir/file.txt http://127.0.0.1:8080/get
```
**Output**:
(The directory `nested/dir/` is created, and the file `file.txt` is saved inside.)

---

### 94. Output Directory (`--output-dir`)
**Description**: Specifies a base directory for all output files (useful with `-O`).
**Input**:
```bash
mkdir my_downloads
curl -s --output-dir my_downloads -O http://127.0.0.1:8080/get
```
**Output**:
(The file `get` is saved in `my_downloads/get`.)

---

### 95. Remote Filename from Header (`-J`)
**Description**: Uses the server-provided filename from the `Content-Disposition` header when combined with `-O`.
**Input**:
```bash
curl -s -O -J http://127.0.0.1:8080/content-disposition
```
**Output**:
(A file named `remote-file.txt` is created with the response content.)

---

### 96. Remote Time Synchronization (`-R`)
**Description**: Synchronizes the local file's timestamp with the server's `Last-Modified` time.
**Input**:
```bash
curl -s -R -o local_file.txt http://127.0.0.1:8080/remote-time
```
**Output**:
(The local file `local_file.txt` has its modification time set to the date provided by the server.)

---

### 97. POST to GET conversion control (`--post301`)
**Description**: Prevents `curl` from converting a POST request to GET when following a 301 redirect.
**Input**:
```bash
curl -s -L --post301 -d "data=123" http://127.0.0.1:8080/redirect-301-post
```
**Output**:
(The subsequent request is a POST to the new location.)

---

### 98. POST to GET conversion control (`--post302`)
**Description**: Prevents `curl` from converting a POST request to GET when following a 302 redirect.
**Input**:
```bash
curl -s -L --post302 -d "data=123" http://127.0.0.1:8080/redirect-302-post
```
**Output**:
(The subsequent request is a POST to the new location.)

---

### 99. POST to GET conversion control (`--post303`)
**Description**: Prevents `curl` from converting a POST request to GET when following a 303 redirect.
**Input**:
```bash
curl -s -L --post303 -d "data=123" http://127.0.0.1:8080/redirect-303-post
```
**Output**:
(The subsequent request is a POST to the new location.)

---

### 100. Location Trusted Credentials (`--location-trusted`)
**Description**: Passes credentials (from `-u`) to redirected hosts even when the hostname changes.
**Input**:
```bash
curl -s -L -u user:password --location-trusted http://127.0.0.1:8080/redirect-to?url=http://localhost:8080/basic-auth-check
```
**Output**:
(The credentials are sent to the second host.)

---

### 101. Retry on Connection Refused (`--retry-connrefused`)
**Description**: Retries the request even if the initial connection is refused by the server.
**Input**:
```bash
curl -s --retry 1 --retry-connrefused http://127.0.0.1:59999
```
**Output**:
(Curl attempts to connect, fails, and retries once.)

---

### 102. Retry on All Errors (`--retry-all-errors`)
**Description**: Retries on any error, including 404s (which are normally not retried).
**Input**:
```bash
curl -s --retry 1 --retry-all-errors http://127.0.0.1:8080/status/404
```
**Output**:
(Curl retries once after receiving the 404.)

---

### 103. Abort on First Error (`--fail-early`)
**Description**: Stops the entire operation on the first error when multiple URLs are provided.
**Input**:
```bash
curl -s --fail-early http://127.0.0.1:1 http://127.0.0.1:8080/get
```
**Output**:
(Curl exits immediately after the first URL fails and does not attempt the second.)

---

### 104. IPv6 Forcing (`-6`)
**Description**: Forces address resolution and connectivity over IPv6.
**Input**:
```bash
curl -s -6 http://[::1]:8080/get
```
**Output**:
(Connection is established over IPv6.)

---

### 105. Interface Binding (`--interface`)
**Description**: Binds the request to a specific network interface or IP address.
**Input**:
```bash
curl -s --interface 127.0.0.1 http://127.0.0.1:8080/get
```
**Output**:
(Connection is initiated from the specified interface/IP.)

---

### 106. Resetting Options for Next URL (`--next`)
**Description**: Resets most options for the subsequent URL on the command line.
**Input**:
```bash
curl -s http://127.0.0.1:8080/get --next -d "data=next" http://127.0.0.1:8080/post
```
**Output**:
(First request is a GET, second is a POST with data.)

---

### 107. Multiple Config Files (`-K`)
**Description**: Passes multiple configuration files to merge options.
**Input**:
```bash
curl -s -K config1.txt -K config2.txt http://127.0.0.1:8080/headers
```
**Output**:
(Options from both files are applied to the request.)

---

### 108. Config from Stdin (`-K -`)
**Description**: Reads configuration parameters from standard input.
**Input**:
```bash
echo 'user-agent = "MyAgent"' | curl -s -K - http://127.0.0.1:8080/get
```
**Output**:
(Request is made using the User-Agent specified in the stdin config.)

---

### 109. Cookie Path Scoping
**Description**: Ensures that cookies are only sent back to paths matching the `path` attribute.
**Input**:
```bash
curl -s -c cookies.txt http://127.0.0.1:8080/cookies/path
curl -s -b cookies.txt http://127.0.0.1:8080/cookies/path/sub
```
**Output**:
(Only cookies matching the path are included in the second request.)

---

### 110. Literal Multipart Form String (`--form-string`)
**Description**: Sends multipart form data that starts with `@` as a literal string.
**Input**:
```bash
curl -s --form-string "field=@literal" http://127.0.0.1:8080/post-form-type
```
**Output**:
(Field is sent as the string "@literal" instead of trying to read from a file named "literal".)

---

### 111. Content-Type per Form Field
**Description**: Specifies a custom Content-Type for a multipart form field.
**Input**:
```bash
curl -s -F "field={\"a\":1};type=application/json" http://127.0.0.1:8080/post-form-type
```
**Output**:
(Field is sent with `Content-Type: application/json`.)

---

### 112. Maximum Filesize Limit (`--max-filesize`)
**Description**: Aborts the transfer if the server's `Content-Length` exceeds a specified limit.
**Input**:
```bash
curl -s --max-filesize 500000 http://127.0.0.1:8080/large-response
```
**Output**:
(Curl exits with error code 63.)

---

### 113. Speed Limit and Time (`--speed-limit` and `--speed-time`)
**Description**: Aborts transfers that fall below a certain speed for a specified duration.
**Input**:
```bash
curl -s --speed-limit 1000 --speed-time 2 http://127.0.0.1:8080/slow-response
```
**Output**:
(Curl exits with error code 28 after 2 seconds of slow transfer.)

---

### 114. CA Certificate Bundle (`--cacert`)
**Description**: Provides a specific CA certificate bundle for peer verification.
**Input**:
```bash
curl -s --cacert server.crt https://127.0.0.1:8443/get
```
**Output**:
(Successful connection after verifying the server's certificate against the provided CA cert.)

---

### 115. Pinned Public Key Verification (`--pinnedpubkey`)
**Description**: Verifies the server's public key against a provided hash or file.
**Input**:
```bash
curl -s -k --pinnedpubkey server.crt https://127.0.0.1:8443/get
```
**Output**:
(Successful connection if the server's public key matches the pinned key.)

---

### 116. OPTIONS Request
**Description**: Sends an `OPTIONS` request to check supported methods.
**Input**:
```bash
curl -s -X OPTIONS -i http://127.0.0.1:8080/get
```
**Output**:
(Returns 204 with `Allow` header containing supported methods.)

---

### 117. TRACE Request
**Description**: Sends a `TRACE` request which echoes the received request.
**Input**:
```bash
curl -s -X TRACE http://127.0.0.1:8080/get
```
**Output**:
(Returns the request headers echoed in the body.)

---

### 118. HEAD Request with Redirects
**Description**: Verifies that `HEAD` with `-L` follows redirects while remaining a `HEAD` request.
**Input**:
```bash
curl -s -I -L http://127.0.0.1:8080/redirect-to?url=/get
```
**Output**:
(Follows redirect and returns headers of the final resource.)

---

### 119. Authentication with Username Only (Interactive Prompt Simulation)
**Description**: Testing `curl -u "username:"`. Appending a colon tells `curl` that there is no password, preventing it from prompting the user interactively.
**Input**:
```bash
curl -s -u "user:" http://127.0.0.1:8080/basic-auth-check
```
**Output**:
(Returns basic auth header for user with empty password.)

---

### 120. Authentication with Colon in Credentials
**Description**: Testing passwords that contain colons.
**Input**:
```bash
curl -s -u "user:pass:word" http://127.0.0.1:8080/basic-auth-check
```
**Output**:
(Returns basic auth header for "user" with password "pass:word".)

---

### 121. Silent and Verbose Combined
**Description**: Testing `curl -s -v`. `-s` suppresses the progress meter, but `-v` still shows request/response details.
**Input**:
```bash
curl -s -v http://127.0.0.1:8080/get
```
**Output**:
(Shows verbose connection and protocol details while hiding progress.)

---

### 122. Include Headers with Output File
**Description**: Using `-i` with `-o` ensures headers are saved to the file.
**Input**:
```bash
curl -s -i -o output.txt http://127.0.0.1:8080/get
```
**Output**:
(The file `output.txt` contains both the response headers and the body.)

---

### 123. Mixed Source Data in POST
**Description**: Combining raw strings and file data in the same request.
**Input**:
```bash
echo "val2" > data.txt
curl -s -d "param1=val1" -d @data.txt http://127.0.0.1:8080/post
```
**Output**:
(The POST data contains concatenated parameters from both sources.)

---

### 124. Multiple @file Arguments in POST
**Description**: Multiple `-d @file` arguments are correctly concatenated.
**Input**:
```bash
echo "a=1" > file1.txt
echo "b=2" > file2.txt
curl -s -d @file1.txt -d @file2.txt http://127.0.0.1:8080/post
```
**Output**:
(The POST data contains concatenated parameters from all files.)

---

### 125. Multiple Files in One Form Field
**Description**: Testing the syntax for multiple files in a single form field using multiple `-F` flags.
**Input**:
```bash
curl -s -F "images=@img1.jpg" -F "images=@img2.jpg" http://127.0.0.1:8080/post
```
**Output**:
(The request contains multiple parts with the same field name `images`.)

---

### 126. Exit 3: Malformed URL
**Description**: Verifying exit code for malformed URL.
**Input**:
```bash
curl "http://[invalid-url]"
```
**Output**:
(Exit code 3)

---

### 127. Exit 7: Failed to Connect
**Description**: Verifying exit code for connection refusal.
**Input**:
```bash
curl http://127.0.0.1:1
```
**Output**:
(Exit code 7)

---

### 128. Environment Variable CURL_CA_BUNDLE
**Description**: Verifying the tool respects the `CURL_CA_BUNDLE` environment variable.
**Input**:
```bash
$env:CURL_CA_BUNDLE="nonexistent.pem"
curl https://127.0.0.1:8443/get
```
**Output**:
(Fails with exit code 77 or 60 due to invalid CA bundle.)

---

### 129. Resuming Already Complete Download
**Description**: Testing behavior when trying to resume a download that is already complete.
**Input**:
```bash
echo "full content" > download.txt
curl -s -C - -o download.txt http://127.0.0.1:8080/range-test
```
**Output**:
(Success, no extra data appended or error depending on implementation.)
