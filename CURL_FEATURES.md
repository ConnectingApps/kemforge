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
