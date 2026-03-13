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
