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
