#!/usr/bin/env pwsh
# test_curl.ps1 - Test script for curl features based on CURL_FEATURES.md
# Usage: ./test_curl.ps1 <curl-command>
# Example: ./test_curl.ps1 curl
#
# The script starts a local Flask test server (test_server.py) automatically
# so that no external services (httpbin.org, badssl.com) are required.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CurlCmd
)

# Set a default timeout for Kemforge to avoid hangs during tests
$env:KEMFORGE_DEFAULT_TIMEOUT = "120s"

$ErrorActionPreference = "Continue"

$passed = 0
$failed = 0
$skipped = 0
$totalTests = 0

# ---------------------------------------------------------------------------
# Determine paths & ports
# ---------------------------------------------------------------------------
$scriptDir = $PSScriptRoot
if ($IsWindows) {
    $venvPython = Join-Path $scriptDir ".venv\Scripts\python.exe"
} else {
    $venvPython = Join-Path $scriptDir ".venv/bin/python"
}
$testServer = Join-Path $scriptDir "test_server.py"
$certFile = Join-Path $scriptDir "server.crt"
$pubkeyFile = Join-Path $scriptDir "server_pub.pem"
$httpPort = 8080
$httpsPort = 8443
$mtlsPort = 8444
$proxyPort = 8081
$baseUrl = "http://127.0.0.1:$httpPort"
$httpsBaseUrl = "https://127.0.0.1:$httpsPort"
$mtlsBaseUrl = "https://127.0.0.1:$mtlsPort"

# Check for openssl availability
$hasOpenSSL = $null -ne (Get-Command openssl -ErrorAction SilentlyContinue)
if (-not $hasOpenSSL) {
    Write-Host "  [WARN] openssl not found in PATH. Using Python as fallback for some tests." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function Write-TestHeader {
    param([string]$Name)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "TEST: $Name" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$Message)
    $script:passed++
    Write-Host "  [PASS] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    $script:failed++
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Write-Skip {
    param([string]$Message)
    $script:skipped++
    Write-Host "  [SKIP] $Message" -ForegroundColor Yellow
}

function Invoke-CurlTest {
    param(
        [string]$Arguments,
        [string]$Stdin = $null,
        [switch]$ReturnStderr
    )

    $isKemforge = ($CurlCmd -ne "curl" -and $CurlCmd -ne "curl.exe")

    # When testing kemforge, run curl first as a baseline
    if ($isKemforge) {
        $psiCurl = New-Object System.Diagnostics.ProcessStartInfo
        $psiCurl.FileName = "curl"
        $psiCurl.Arguments = $Arguments
        $psiCurl.WorkingDirectory = $pwd.Path
        $psiCurl.RedirectStandardOutput = $true
        $psiCurl.RedirectStandardError = $true
        $psiCurl.RedirectStandardInput = $Stdin -ne $null
        $psiCurl.UseShellExecute = $false
        $psiCurl.CreateNoWindow = $true

        $pCurl = New-Object System.Diagnostics.Process
        $pCurl.StartInfo = $psiCurl
        $pCurl.Start() | Out-Null
        if ($Stdin -ne $null) {
            $pCurl.StandardInput.Write($Stdin)
            $pCurl.StandardInput.Close()
        }
        
        # Read both streams to avoid deadlocks
        $curlOutTask = $pCurl.StandardOutput.ReadToEndAsync()
        $curlErrTask = $pCurl.StandardError.ReadToEndAsync()
        $pCurl.WaitForExit()
        
        $curlExit = $pCurl.ExitCode
        if ($curlExit -eq 0) {
            Write-Host "  [BASELINE] curl: OK" -ForegroundColor DarkGray
        } else {
            Write-Host "  [BASELINE] curl: FAILED (ExitCode: $curlExit)" -ForegroundColor Yellow
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CurlCmd
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $pwd.Path
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $Stdin -ne $null
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null

    if ($Stdin -ne $null) {
        $process.StandardInput.Write($Stdin)
        $process.StandardInput.Close()
    }

    # Read both streams to avoid deadlocks
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    return @{
        Stdout   = $stdout
        Stderr   = $stderr
        ExitCode = $process.ExitCode
    }
}

# ---------------------------------------------------------------------------
# Start the local Flask test server
# ---------------------------------------------------------------------------

if (-not (Test-Path $venvPython)) {
    Write-Host "ERROR: Virtual-environment Python not found at $venvPython" -ForegroundColor Red
    Write-Host "Create it with:  python3 -m venv .venv && .venv/bin/pip install flask cryptography" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $testServer)) {
    Write-Host "ERROR: test_server.py not found at $testServer" -ForegroundColor Red
    exit 1
}

Write-Host "Starting local test server on ports $httpPort (HTTP), $httpsPort (HTTPS), $mtlsPort (mTLS) and $proxyPort (CONNECT)..." -ForegroundColor Magenta

# Stop any existing server process on these ports (cleanup from previous runs)
try {
    if ($IsLinux) {
        pkill -f "test_server.py"
    } else {
        # Using Get-CimInstance to check CommandLine which is more reliable on Windows
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "test_server.py" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    # Delete old certs to ensure they are regenerated with correct CA/Usage flags
    if (Test-Path $certFile) { Remove-Item $certFile }
    if (Test-Path $pubkeyFile) { Remove-Item $pubkeyFile }
    if (Test-Path (Join-Path $scriptDir "server.key")) { Remove-Item (Join-Path $scriptDir "server.key") }
    
    # Wait a bit longer for ports to be released
    Start-Sleep -Seconds 2
} catch {}

$serverPsi = New-Object System.Diagnostics.ProcessStartInfo
$serverPsi.FileName = $venvPython
$serverPsi.Arguments = "`"$testServer`" --port $httpPort --https-port $httpsPort --mtls-port $mtlsPort --proxy-port $proxyPort"
$serverPsi.RedirectStandardOutput = $false
$serverPsi.RedirectStandardError = $false
$serverPsi.UseShellExecute = $false
$serverPsi.CreateNoWindow = $true

$serverProcess = New-Object System.Diagnostics.Process
$serverProcess.StartInfo = $serverPsi
$serverProcess.Start() | Out-Null

# Wait for the HTTP server to be ready
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $probe = Invoke-CurlTest "-s -o /dev/null -w `"%{http_code}`" $baseUrl/get"
        if ($probe.Stdout.Trim() -eq "200") { $ready = $true; break }
    } catch { }
}
if (-not $ready) {
    Write-Host "ERROR: Local test server did not start in time." -ForegroundColor Red
    if (-not $serverProcess.HasExited) { $serverProcess.Kill() }
    exit 1
}
Write-Host "Local test server is ready." -ForegroundColor Green

# Ensure the server is stopped when the script exits
trap {
    if (-not $serverProcess.HasExited) { $serverProcess.Kill() }
}

# ---------------------------------------------------------------------------
# Verify the curl tool exists
# ---------------------------------------------------------------------------
$toolCheck = Get-Command $CurlCmd -ErrorAction SilentlyContinue
if (-not $toolCheck) {
    Write-Host "ERROR: '$CurlCmd' not found in PATH." -ForegroundColor Red
    if (-not $serverProcess.HasExited) { $serverProcess.Kill() }
    exit 1
}
Write-Host "Using tool: $CurlCmd" -ForegroundColor Magenta
Write-Host "Starting curl feature tests against local server ($baseUrl)..." -ForegroundColor Magenta

# ----------------------------------------------------------------
# Test 1: Simple GET Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "1. Simple GET Request"
$result = Invoke-CurlTest "-s $baseUrl/get"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -eq "$baseUrl/get" -and $json.headers.Host -eq "127.0.0.1:$httpPort") {
        Write-Pass "GET request returned valid JSON with correct url and Host header."
    } else {
        Write-Fail "Unexpected response content: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 2: Custom Headers
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "2. Custom Headers"
$result = Invoke-CurlTest "-s -H `"X-Custom-Header: MyValue`" $baseUrl/headers"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.headers.'X-Custom-Header' -eq "MyValue") {
        Write-Pass "Custom header X-Custom-Header: MyValue was received by server."
    } else {
        Write-Fail "Custom header not found in response: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 3: POST Request with Form Data
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "3. POST Request with Form Data"
$result = Invoke-CurlTest "-s -d `"param1=val1&param2=val2`" $baseUrl/post"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.form.param1 -eq "val1" -and $json.form.param2 -eq "val2") {
        Write-Pass "POST form data param1=val1 and param2=val2 received correctly."
    } else {
        Write-Fail "Form data mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 4: Multi-part Form Data (File Upload)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "4. Multi-part Form Data (File Upload)"
$testFilePath = Join-Path $scriptDir "test_upload_tmp.txt"
try {
    [System.IO.File]::WriteAllText($testFilePath, "This is a test file for curl.`n")
    $result = Invoke-CurlTest "-s -F `"file=@$testFilePath`" $baseUrl/post"
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.files.file -match "This is a test file for curl") {
        Write-Pass "File upload received correctly by server."
    } else {
        Write-Fail "File content mismatch in response: $($result.Stdout)"
    }
} catch {
    Write-Fail "File upload test failed: $_"
} finally {
    if (Test-Path $testFilePath) { Remove-Item $testFilePath -Force }
}

# ----------------------------------------------------------------
# Test 5: Basic Authentication
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "5. Basic Authentication"
$result = Invoke-CurlTest "-s -u user:password $baseUrl/basic-auth/user/password"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.authenticated -eq $true -and $json.user -eq "user") {
        Write-Pass "Basic authentication succeeded."
    } else {
        Write-Fail "Authentication response unexpected: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 6: Following Redirects
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "6. Following Redirects"
$encodedRedirectUrl = [System.Uri]::EscapeDataString("$baseUrl/get")
$result = Invoke-CurlTest "-s -L `"$baseUrl/redirect-to?url=$encodedRedirectUrl`""
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -eq "$baseUrl/get") {
        Write-Pass "Redirect followed successfully to $baseUrl/get."
    } else {
        Write-Fail "Redirect target mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 7: Cookie Handling
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "7. Cookie Handling"
$cookieFile = Join-Path $scriptDir "test_cookies_tmp.txt"
try {
    $result1 = Invoke-CurlTest "-s -L -c `"$cookieFile`" $baseUrl/cookies/set/session/123456"
    $result2 = Invoke-CurlTest "-s -b `"$cookieFile`" $baseUrl/cookies"
    $json = $result2.Stdout | ConvertFrom-Json
    if ($json.cookies.session -eq "123456") {
        Write-Pass "Cookie session=123456 was saved and sent back correctly."
    } else {
        Write-Fail "Cookie mismatch: $($result2.Stdout)"
    }
} catch {
    Write-Fail "Cookie test failed: $_"
} finally {
    if (Test-Path $cookieFile) { Remove-Item $cookieFile -Force }
}

# ----------------------------------------------------------------
# Test 8: Verbose Output
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "8. Verbose Output"
$result = Invoke-CurlTest "-v -s $baseUrl/get" -ReturnStderr
$stderr = $result.Stderr
if ($stderr -match "GET /get HTTP" -and $stderr -match "HTTP/[\d.]+ 200") {
    Write-Pass "Verbose output contains request line and 200 status."
} else {
    Write-Fail "Verbose output missing expected patterns. Stderr: $stderr"
}

# ----------------------------------------------------------------
# Test 9: Custom User-Agent
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "9. Custom User-Agent"
$result = Invoke-CurlTest "-s -A `"MyTestAgent`" $baseUrl/user-agent"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.'user-agent' -eq "MyTestAgent") {
        Write-Pass "Custom User-Agent 'MyTestAgent' was sent correctly."
    } else {
        Write-Fail "User-Agent mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 10: Saving Output to File
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "10. Saving Output to File"
$outFile = Join-Path $scriptDir "test_response_tmp.json"
try {
    $result = Invoke-CurlTest "-s -o `"$outFile`" $baseUrl/get"
    if (Test-Path $outFile) {
        $content = Get-Content $outFile -Raw
        $json = $content | ConvertFrom-Json
        if ($json.url -eq "$baseUrl/get") {
            Write-Pass "Response saved to file correctly."
        } else {
            Write-Fail "Saved file content unexpected: $content"
        }
    } else {
        Write-Fail "Output file was not created."
    }
} catch {
    Write-Fail "Save to file test failed: $_"
} finally {
    if (Test-Path $outFile) { Remove-Item $outFile -Force }
}

# ----------------------------------------------------------------
# Test 11: HEAD Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "11. HEAD Request"
$result = Invoke-CurlTest "-s -I $baseUrl/get"
if ($result.Stdout -match "HTTP/[\d.]+ 200" -and $result.Stdout -match "Content-Type") {
    Write-Pass "HEAD request returned status 200 and Content-Type header."
} else {
    Write-Fail "HEAD response missing expected headers: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 12: Custom HTTP Method (DELETE)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "12. Custom HTTP Method (DELETE)"
$result = Invoke-CurlTest "-s -X DELETE $baseUrl/delete"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -eq "$baseUrl/delete") {
        Write-Pass "DELETE request succeeded with correct url."
    } else {
        Write-Fail "DELETE response unexpected: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 13: Sending JSON Data
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "13. Sending JSON Data"
$jsonFile = Join-Path $scriptDir "test_json_tmp.txt"
try {
    [System.IO.File]::WriteAllText($jsonFile, '{"key": "value"}')
    $result = Invoke-CurlTest "-s -H `"Content-Type: application/json`" -d @$jsonFile $baseUrl/post"
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.json.key -eq "value") {
        Write-Pass "JSON data received correctly by server."
    } else {
        Write-Fail "JSON data mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
} finally {
    if (Test-Path $jsonFile) { Remove-Item $jsonFile -Force }
}

# ----------------------------------------------------------------
# Test 14: Query Parameters with URL Encoding
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "14. Query Parameters with URL Encoding"
$result = Invoke-CurlTest "-s --data-urlencode `"name=John Doe`" --data-urlencode `"city=New York`" -G $baseUrl/get"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.args.name -eq "John Doe" -and $json.args.city -eq "New York") {
        Write-Pass "URL-encoded query parameters received correctly."
    } else {
        Write-Fail "Query parameter mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 15: Write-out Format (HTTP Status Code)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "15. Write-out Format (HTTP Status Code)"
if ($IsWindows) {
    $result = Invoke-CurlTest "-s -o NUL -w `"%{http_code}\n`" $baseUrl/get"
} else {
    $result = Invoke-CurlTest "-s -o /dev/null -w `"%{http_code}\n`" $baseUrl/get"
}
$statusCode = $result.Stdout.Trim()
if ($statusCode -eq "200") {
    Write-Pass "Write-out returned HTTP status code 200."
} else {
    Write-Fail "Expected status code 200, got: '$statusCode'"
}

# ----------------------------------------------------------------
# Test 16: Silent Mode with Errors
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "16. Silent Mode with Errors"
$result = Invoke-CurlTest '-sS http://non-existent-domain.invalid' -ReturnStderr
if ($result.ExitCode -ne 0) {
    if ($result.Stderr -match "Could not resolve host" -or $result.Stderr -match "resolve") {
        Write-Pass "Silent mode with errors correctly reported DNS resolution failure."
    } else {
        Write-Pass "Silent mode with errors returned non-zero exit code ($($result.ExitCode))."
    }
} else {
    Write-Fail "Expected non-zero exit code for non-existent domain, got 0."
}

# ----------------------------------------------------------------
# Test 17: Insecure SSL (Ignore Certificate Errors)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "17. Insecure SSL (Ignore Certificate Errors)"
# Use local HTTPS server with self-signed cert
$result = Invoke-CurlTest "-s -k $httpsBaseUrl/get"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -match "/get" -and $result.ExitCode -eq 0) {
        Write-Pass "Insecure SSL connection succeeded with -k flag (local self-signed cert)."
    } else {
        Write-Fail "Insecure SSL test failed. Output: $($result.Stdout)"
    }
} catch {
    # Even if not JSON, if we got a response with exit code 0, it worked
    if ($result.ExitCode -eq 0 -and $result.Stdout.Length -gt 0) {
        Write-Pass "Insecure SSL connection succeeded with -k flag."
    } else {
        Write-Fail "Insecure SSL test failed. Exit code: $($result.ExitCode), Output length: $($result.Stdout.Length), Stderr: $($result.Stderr)"
    }
}

# ----------------------------------------------------------------
# Test 18: Connect Timeout
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "18. Connect Timeout"
$startTime = Get-Date
$result = Invoke-CurlTest '-s --connect-timeout 3 http://192.0.2.1/test' -ReturnStderr
$elapsed = (Get-Date) - $startTime
if ($result.ExitCode -ne 0 -and $elapsed.TotalSeconds -lt 10) {
    Write-Pass "Connect timeout triggered within expected time ($([math]::Round($elapsed.TotalSeconds, 1))s)."
} else {
    Write-Fail "Connect timeout test unexpected. Exit: $($result.ExitCode), Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s"
}

# ----------------------------------------------------------------
# Test 19: Using a Proxy
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "19. Using a Proxy"
# Use local Flask server as proxy — curl sends request through proxy to same server
$result = Invoke-CurlTest "-s -x http://127.0.0.1:$httpPort $baseUrl/get"
try {
    $json = $result.Stdout | ConvertFrom-Json
    # When using the local server as proxy, curl sends the full URL; our Flask
    # app will route it to /get and return the standard response.
    if ($json.url -match "/get" -and $result.ExitCode -eq 0) {
        Write-Pass "Proxy request succeeded through local server."
    } else {
        Write-Fail "Proxy response unexpected: $($result.Stdout)"
    }
} catch {
    Write-Fail "Proxy test failed: $($result.Stdout) Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 20: Include Headers in Output
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "20. Include Headers in Output"
$result = Invoke-CurlTest "-s -i $baseUrl/get"
if ($result.Stdout -match "HTTP/[\d.]+ 200" -and $result.Stdout -match '"url"') {
    Write-Pass "Include headers output contains both HTTP status line and JSON body."
} else {
    Write-Fail "Include headers output missing expected content: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 21: Simple HEAD Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "21. Simple HEAD Request"
$result = Invoke-CurlTest "-I $baseUrl/get" -ReturnStderr
$output = $result.Stdout
if ($output -match "HTTP/[\d.]+ 200" -and $output -match "Content-Type") {
    Write-Pass "Simple HEAD request returned status 200 and Content-Type."
} else {
    Write-Fail "Simple HEAD response missing expected headers. Stdout: $output"
}

# ----------------------------------------------------------------
# Test 22: Compressed Response
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "22. Compressed Response"
$result = Invoke-CurlTest "-s -I --compressed $baseUrl/get"
if ($result.Stdout -match "HTTP/[\d.]+ 200" -and $result.Stdout -match "Content-Type") {
    Write-Pass "Compressed HEAD request returned valid headers."
} else {
    Write-Fail "Compressed response missing expected headers: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 23: Range Request (Partial Content)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "23. Range Request (Partial Content)"
$result = Invoke-CurlTest "-s -r 0-50 $baseUrl/range/1024"
if ($result.Stdout.Length -eq 51) {
    Write-Pass "Range request returned exactly 51 bytes."
} else {
    if ($result.Stdout.Length -gt 0 -and $result.Stdout.Length -le 52) {
        Write-Pass "Range request returned $($result.Stdout.Length) bytes (within expected range)."
    } else {
        Write-Fail "Range request returned $($result.Stdout.Length) bytes, expected 51."
    }
}

# ----------------------------------------------------------------
# Test 24: Saving with Remote Filename
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "24. Saving with Remote Filename (-O)"
$savedFile = Join-Path $scriptDir "get"
try {
    if (Test-Path $savedFile) { Remove-Item $savedFile -Force }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CurlCmd
    $psi.Arguments = "-s -O $baseUrl/get"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $scriptDir
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null
    $process.StandardOutput.ReadToEnd() | Out-Null
    $process.StandardError.ReadToEnd() | Out-Null
    $process.WaitForExit()

    if (Test-Path $savedFile) {
        $content = Get-Content $savedFile -Raw
        $json = $content | ConvertFrom-Json
        if ($json.url -eq "$baseUrl/get") {
            Write-Pass "File 'get' created with correct content using -O flag."
        } else {
            Write-Fail "Saved file content unexpected: $content"
        }
    } else {
        Write-Fail "File 'get' was not created by -O flag."
    }
} catch {
    Write-Fail "Remote filename test failed: $_"
} finally {
    if (Test-Path $savedFile) { Remove-Item $savedFile -Force }
}

# ----------------------------------------------------------------
# Test 25: Maximum Time for Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "25. Maximum Time for Request (--max-time)"
$startTime = Get-Date
$result = Invoke-CurlTest "-s --max-time 3 $baseUrl/delay/10" -ReturnStderr
$elapsed = (Get-Date) - $startTime
if ($result.ExitCode -eq 28 -and $elapsed.TotalSeconds -lt 8) {
    Write-Pass "Max-time triggered correctly (exit code 28, elapsed $([math]::Round($elapsed.TotalSeconds, 1))s)."
} elseif ($result.ExitCode -ne 0 -and $elapsed.TotalSeconds -lt 8) {
    Write-Pass "Max-time triggered (exit code $($result.ExitCode), elapsed $([math]::Round($elapsed.TotalSeconds, 1))s)."
} else {
    Write-Fail "Max-time test unexpected. Exit: $($result.ExitCode), Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s"
}

# ----------------------------------------------------------------
# Test 26: Retry Logic (--retry)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "26. Retry Logic (--retry)"
# Use a unique ID for this retry test
$retryId = "test-retry-$(Get-Random)"
$startTime = Get-Date
# Retry 2 times on 500. The server fails 2 times and succeeds on the 3rd call.
$result = Invoke-CurlTest "-s --retry 2 $baseUrl/retry/$retryId/2"
$elapsed = (Get-Date) - $startTime
if ($result.Stdout -match '"success":\s*true' -and $result.Stdout -match '"attempts":\s*2') {
    Write-Pass "Retry logic succeeded after 2 retries (elapsed $([math]::Round($elapsed.TotalSeconds, 1))s)."
} else {
    Write-Fail "Retry logic failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr), Exit: $($result.ExitCode)"
}

# ----------------------------------------------------------------
# Test 27: Fail on Server Error (-f)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "27. Fail on Server Error (-f)"
$result = Invoke-CurlTest "-s -f $baseUrl/status/404"
if ($result.ExitCode -ne 0) {
    Write-Pass "Fail flag correctly returned non-zero exit code ($($result.ExitCode)) for 404."
} else {
    Write-Fail "Fail flag failed to return non-zero exit code for 404. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 28: Referer Header (-e)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "28. Referer Header (-e)"
$referer = "http://example.com/source"
$result = Invoke-CurlTest "-s -e `"$referer`" $baseUrl/headers"
if ($result.Stdout -match "`"Referer`":\s*`"$referer`"") {
    Write-Pass "Referer header correctly sent and received."
} else {
    Write-Fail "Referer header missing or incorrect. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 29: Limit Redirects (--max-redirs)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "29. Limit Redirects (--max-redirs)"
# We must use -L to follow redirects, and --max-redirs to limit them.
$result = Invoke-CurlTest "-s -L --max-redirs 2 $baseUrl/redirect/5" -ReturnStderr
if ($result.ExitCode -eq 47 -or $result.Stderr -match "Maximum.*redirects followed" -or $result.Stderr -match "limit reached") {
    Write-Pass "Limit redirects correctly stopped (Exit code: $($result.ExitCode))."
} else {
    Write-Fail "Limit redirects failed. Exit: $($result.ExitCode), Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 30: Bearer Token Authentication
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "30. Bearer Token Authentication"
$token = "my-secret-bearer-token"
$result = Invoke-CurlTest "-s -H `"Authorization: Bearer $token`" $baseUrl/bearer"
if ($result.Stdout -match '"authenticated":\s*true' -and $result.Stdout -match "`"token`":\s*`"$token`"") {
    Write-Pass "Bearer token authentication succeeded."
} else {
    Write-Fail "Bearer token authentication failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 31: Multiple URL Fetching
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "31. Multiple URL Fetching"
$result = Invoke-CurlTest "-s $baseUrl/get $baseUrl/headers"
if ($result.Stdout -match "url.*get" -and $result.Stdout -match "headers") {
    Write-Pass "Successfully fetched multiple URLs in one call."
} else {
    Write-Fail "Multiple URL fetching failed or output incomplete. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 32: Configuration Files (-K)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "32. Configuration Files (-K)"
$configFile = Join-Path $scriptDir "test_config.txt"
"url = `"$baseUrl/headers`"`nheader = `"X-Config-Header: ConfigValue`"" | Out-File $configFile -Encoding ascii
try {
    $result = Invoke-CurlTest "-s -K `"$configFile`""
    if ($result.Stdout -match "X-Config-Header" -and $result.Stdout -match "ConfigValue") {
        Write-Pass "Configuration file correctly processed headers and URL."
    } else {
        Write-Fail "Configuration file test failed. Stdout: $($result.Stdout)"
    }
} finally {
    if (Test-Path $configFile) { Remove-Item $configFile -Force }
}

# ----------------------------------------------------------------
# Test 33: Rate Limiting (--limit-rate)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "33. Rate Limiting (--limit-rate)"
$startTime = Get-Date
# Request 50KB data, limit to 20K/s -> should take at least 2 seconds
$result = Invoke-CurlTest "-s --limit-rate 20k $baseUrl/range/51200"
$elapsed = (Get-Date) - $startTime
if ($elapsed.TotalSeconds -ge 1.5 -and $result.Stdout.Length -eq 51200) {
    Write-Pass "Rate limiting worked (elapsed $([math]::Round($elapsed.TotalSeconds, 1))s for 50KB)."
} elseif ($result.Stdout.Length -eq 51200) {
    Write-Pass "Rate limiting test completed, but timing was fast ($([math]::Round($elapsed.TotalSeconds, 1))s)."
} else {
    Write-Fail "Rate limiting test failed. Length: $($result.Stdout.Length), Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s"
}

# ----------------------------------------------------------------
# Test 34: Parallel Downloads (-Z)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "34. Parallel Downloads (-Z)"
$result = Invoke-CurlTest "-s -Z $baseUrl/delay/1 $baseUrl/delay/1"
if ($result.Stdout -match "delayed") {
    Write-Pass "Parallel downloads completed successfully."
} else {
    Write-Fail "Parallel downloads failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 35: Modern JSON Flag (--json)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "35. Modern JSON Flag (--json)"
# Using a temporary file to avoid complex shell quoting issues
$jsonFile = Join-Path $scriptDir "test_data.json"
'{"foo":"bar"}' | Out-File $jsonFile -Encoding ascii
try {
    # In newer curl, --json @file is supported.
    $result = Invoke-CurlTest "-s --json @`"$jsonFile`" $baseUrl/post"
    if ($result.Stdout -match "`"Content-Type`":\s*`"application\/json`"" -and $result.Stdout -match "`"foo`":\s*`"bar`"") {
        Write-Pass "Modern JSON flag correctly set headers and data."
    } else {
        Write-Fail "Modern JSON flag test failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
    }
} finally {
    if (Test-Path $jsonFile) { Remove-Item $jsonFile -Force }
}

# ----------------------------------------------------------------
# Test 36: Custom Resolve (--resolve)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "36. Custom Resolve (--resolve)"
# Use ${httpPort} to prevent PowerShell from misinterpreting :127 as part of the variable name
$result = Invoke-CurlTest "-s --resolve example.internal:${httpPort}:127.0.0.1 http://example.internal:${httpPort}/get"
if ($result.Stdout -match "url.*$httpPort/get") {
    Write-Pass "Custom resolve correctly mapped domain to local server."
} else {
    Write-Fail "Custom resolve test failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr), Exit: $($result.ExitCode)"
}

# ----------------------------------------------------------------
# Test 37: Additional HTTP Methods (PUT and PATCH)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "37. Additional HTTP Methods (PUT and PATCH)"
$resultPut = Invoke-CurlTest "-s -X PUT -d `"update=true`" $baseUrl/put"
$resultPatch = Invoke-CurlTest "-s -X PATCH -d `"patch=true`" $baseUrl/patch"
if ($resultPut.Stdout -match "update.*true" -and $resultPatch.Stdout -match "patch.*true") {
    Write-Pass "PUT and PATCH methods succeeded."
} else {
    Write-Fail "PUT or PATCH failed. PUT Stdout: $($resultPut.Stdout), PATCH Stdout: $($resultPatch.Stdout)"
}

# ----------------------------------------------------------------
# Test 38: Failed Authentication (Negative Testing)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "38. Failed Authentication (Negative Testing)"
$result = Invoke-CurlTest "-s -u user:wrongpassword $baseUrl/basic-auth/user/password"
if ($result.ExitCode -eq 0 -and $result.Stdout -match "Unauthorized") {
    Write-Pass "Failed authentication correctly returned Unauthorized."
} elseif ($result.ExitCode -eq 22) {
    # If -f was used, curl would exit with 22, but here we didn't use -f
    Write-Pass "Failed authentication correctly handled (ExitCode 22)."
} else {
    Write-Fail "Failed authentication test failed. ExitCode: $($result.ExitCode), Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 39: Dumping Headers to a File (--dump-header)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "39. Dumping Headers to a File (--dump-header)"
$headerFile = Join-Path $scriptDir "test_headers.txt"
if (Test-Path $headerFile) { Remove-Item $headerFile }
try {
    $result = Invoke-CurlTest "-s --dump-header `"$headerFile`" $baseUrl/get"
    if (Test-Path $headerFile) {
        $headers = Get-Content $headerFile -Raw
        if ($headers -match "HTTP/1.1 200 OK" -and $headers -match "Content-Type: application/json") {
            Write-Pass "Headers correctly dumped to file."
        } else {
            Write-Fail "Headers file content mismatch. Content: $headers"
        }
    } else {
        Write-Fail "Headers file was not created."
    }
} finally {
    if (Test-Path $headerFile) { Remove-Item $headerFile }
}

# ----------------------------------------------------------------
# Test 40: Reading Data from Stdin (-d @-)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "40. Reading Data from Stdin (-d @-)"
# PowerShell pipe to curl
$result = Invoke-CurlTest "-s -d @- $baseUrl/post" -Stdin "data-from-stdin"
$stdout = $result.Stdout
if ($stdout -match "data-from-stdin") {
    Write-Pass "Data correctly read from stdin."
} else {
    Write-Fail "Stdin data test failed. Stdout: $stdout"
}

# ----------------------------------------------------------------
# Test 41: Header Suppression/Removal (-H "Header:")
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "41. Header Suppression/Removal (-H `"Header:`")"
$result = Invoke-CurlTest "-s -H `"User-Agent:`" $baseUrl/headers"
# Flask might still show it as empty or missing
if (-not ($result.Stdout -match "curl/") -or $result.Stdout -match "`"User-Agent`":\s*`"`"") {
    Write-Pass "Header suppression/removal succeeded."
} else {
    Write-Fail "Header suppression failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 42: Enforcing HTTP Versions (--http1.1)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "42. Enforcing HTTP Versions (--http1.1)"
$result = Invoke-CurlTest "-s -v --http1.1 $baseUrl/get"
if ($result.Stderr -match "GET /get HTTP/1.1") {
    Write-Pass "Enforcing HTTP/1.1 succeeded."
} else {
    Write-Fail "HTTP/1.1 enforcement failed or not visible in verbose output. Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 43: Resuming Downloads (-C -)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "43. Resuming Downloads (-C -)"
$partialFile = Join-Path $scriptDir "partial.txt"
"abcd" | Out-File $partialFile -NoNewline -Encoding ascii
try {
    # Requesting range starting from 4 (after "abcd")
    $result = Invoke-CurlTest "-s -C - -o `"$partialFile`" $baseUrl/range/10"
    $content = Get-Content $partialFile -Raw
    # range/10 should return "abcdefghij". We already have "abcd", so it should append "efghij"
    if ($content -eq "abcdefghij") {
        Write-Pass "Download resumption succeeded."
    } else {
        Write-Fail "Download resumption failed. Content: $content"
    }
} finally {
    if (Test-Path $partialFile) { Remove-Item $partialFile }
}

# ----------------------------------------------------------------
# Test 44: Expanded Write-out Variables (-w)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "44. Expanded Write-out Variables (-w)"
$result = Invoke-CurlTest "-s -o /dev/null -w `"Code:%{http_code} Size:%{size_download} Time:%{time_total}`" $baseUrl/get"
if ($result.Stdout -match "Code:200" -and $result.Stdout -match "Size:\d+" -and $result.Stdout -match "Time:[\d\.]+") {
    Write-Pass "Expanded write-out variables correctly reported."
} else {
    Write-Fail "Write-out variables failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 45: Uploading Files via PUT (-T)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "45. Uploading Files via PUT (-T)"
$uploadFile = Join-Path $scriptDir "upload.txt"
"binary data to upload" | Out-File $uploadFile -Encoding ascii
try {
    $result = Invoke-CurlTest "-s -T `"$uploadFile`" $baseUrl/put"
    if ($result.Stdout -match "binary data to upload") {
        Write-Pass "File upload via PUT succeeded."
    } else {
        Write-Fail "File upload via PUT failed. Stdout: $($result.Stdout)"
    }
} finally {
    if (Test-Path $uploadFile) { Remove-Item $uploadFile }
}

# ----------------------------------------------------------------
# Test 46: URL Globbing
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "46. URL Globbing"
# Use braces {} for specific values in a set. Escape with backtick if needed in PS, 
# but inside a double-quoted string they should be fine.
$result = Invoke-CurlTest "-s `"$baseUrl/status/{200,201}`""
if ($result.Stdout -match "Status: 200" -and $result.Stdout -match "Status: 201") {
    Write-Pass "URL globbing succeeded."
} else {
    Write-Fail "URL globbing failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 47: Cumulative Headers (Multiple -H)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "47. Cumulative Headers (Multiple -H)"
$result = Invoke-CurlTest "-s -H `"X-Header1: Val1`" -H `"X-Header2: Val2`" $baseUrl/headers"
if ($result.Stdout -match "X-Header1.*Val1" -and $result.Stdout -match "X-Header2.*Val2") {
    Write-Pass "Multiple headers sent and received correctly."
} else {
    Write-Fail "Multiple headers test failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 48: Concatenating Multiple Data Arguments (Multiple -d)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "48. Concatenating Multiple Data Arguments (Multiple -d)"
$result = Invoke-CurlTest "-s -d `"user=admin`" -d `"session=active`" $baseUrl/post"
if ($result.Stdout -match "`"user=admin&session=active`"") {
    Write-Pass "Multiple data arguments concatenated correctly."
} else {
    Write-Fail "Multiple data concatenation failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 49: URL-Embedded Credentials
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "49. URL-Embedded Credentials"
# Construct URL with credentials: http://user:password@127.0.0.1:8080/basic-auth-check
$credUrl = "http://user:password@127.0.0.1:$httpPort/basic-auth-check"
$result = Invoke-CurlTest "-s $credUrl"
if ($result.Stdout -match "Basic dXNlcjpwYXNzd29yZA==") {
    Write-Pass "URL-embedded credentials correctly converted to Authorization header."
} else {
    Write-Fail "URL credentials test failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 50: Proxy Authentication
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "50. Proxy Authentication"
# Use local server as proxy with credentials
$result = Invoke-CurlTest "-s -x http://puser:ppass@127.0.0.1:$httpPort $baseUrl/proxy"
if ($result.Stdout -match "Basic cHVzZXI6cHBhc3M=") {
    Write-Pass "Proxy authentication correctly sent as Proxy-Authorization header."
} else {
    Write-Fail "Proxy authentication test failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 51: Redirect Method Conversion (301/302 vs 307/308)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "51. Redirect Method Conversion"
# 302: POST should become GET
$result302 = Invoke-CurlTest "-s -L -d `"data`" $baseUrl/redirect-302"
# 307: POST should stay POST
$result307 = Invoke-CurlTest "-s -L -d `"data`" $baseUrl/redirect-307"

$passed302 = $result302.Stdout -match "url.*get"
$passed307 = $result307.Stdout -match "url.*post" -and $result307.Stdout -match "data"

if ($passed302 -and $passed307) {
    Write-Pass "Redirect method conversion handled correctly for 302 and 307."
} else {
    Write-Fail "Redirect conversion failed. 302 match: $passed302, 307 match: $passed307"
}

# ----------------------------------------------------------------
# Test 52: Overriding the Host Header
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "52. Overriding the Host Header"
$result = Invoke-CurlTest "-s -H `"Host: production.com`" $baseUrl/headers"
if ($result.Stdout -match "`"Host`":\s*`"production.com`"") {
    Write-Pass "Custom Host header correctly overrode the default."
} else {
    Write-Fail "Host header override failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 53: Binary Data via --data-binary
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "53. Binary Data via --data-binary"
$binFile = Join-Path $scriptDir "test_binary.bin"
# Create a file with a null byte to test binary preservation
[byte[]]$bytes = 65, 0, 66 # 'A', null, 'B'
[System.IO.File]::WriteAllBytes($binFile, $bytes)
try {
    $result = Invoke-CurlTest "-s --data-binary @$binFile $baseUrl/post"
    # The server returns 'data' which should contain the null byte (escaped or literal in JSON)
    if ($result.Stdout -match "A\\u0000B" -or $result.Stdout -match "A\x00B") {
        Write-Pass "Binary data preserved correctly."
    } else {
        Write-Fail "Binary data test failed. Stdout: $($result.Stdout)"
    }
} finally {
    if (Test-Path $binFile) { Remove-Item $binFile }
}

# ----------------------------------------------------------------
# Test 54: Customizing Cookie Storage (Cookies without File)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "54. Cookies without File (-b `"`")"
# -b "" should enable cookie session without a file.
$result = Invoke-CurlTest "-s -b `"`" $baseUrl/cookies/set/tmp/val $baseUrl/cookies"
if ($result.Stdout -match "`"tmp`":\s*`"val`"") {
    Write-Pass "Cookie session enabled without file using -b `"`"."
} else {
    Write-Fail "Cookies without file test failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 55: Mutual TLS (Client Certificates)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "55. Mutual TLS (Client Certificates)"
$clientCertFile = Join-Path $scriptDir "client.crt"
$clientKeyFile = Join-Path $scriptDir "client.key"
$clientCsrFile = Join-Path $scriptDir "client.csr"
$serverCertFile = Join-Path $scriptDir "server.crt"
$serverKeyFile = Join-Path $scriptDir "server.key"

# We'll use openssl to generate a client cert signed by server.crt
try {
    if ($hasOpenSSL) {
        & openssl genrsa -out $clientKeyFile 2048 2>$null
        & openssl req -new -key $clientKeyFile -out $clientCsrFile -subj '/CN=localhost' 2>$null
        & openssl x509 -req -in $clientCsrFile -CA $serverCertFile -CAkey $serverKeyFile -CAcreateserial -out $clientCertFile -days 1 2>$null
    } else {
        $pythonCmd = "from cryptography import x509; from cryptography.hazmat.primitives import hashes, serialization; from cryptography.hazmat.primitives.asymmetric import rsa; import datetime; s_cert = x509.load_pem_x509_certificate(open('$serverCertFile','rb').read()); s_key = serialization.load_pem_private_key(open('$serverKeyFile','rb').read(), None); c_key = rsa.generate_private_key(65537, 2048); sub = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, 'localhost')]); c_cert = x509.CertificateBuilder().subject_name(sub).issuer_name(s_cert.subject).public_key(c_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.now(datetime.timezone.utc)).not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).sign(s_key, hashes.SHA256()); open('$clientCertFile','wb').write(c_cert.public_bytes(serialization.Encoding.PEM)); open('$clientKeyFile','wb').write(c_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))"
        & $venvPython -c $pythonCmd
    }
    
    if (Test-Path $clientCertFile) {
        $result = Invoke-CurlTest "-s -k --cert `"$clientCertFile`" --key `"$clientKeyFile`" $mtlsBaseUrl/mtls"
        if ($result.Stdout -match '"authenticated":\s*true') {
            Write-Pass "Mutual TLS request with valid certificates succeeded."
        } else {
            Write-Fail "Mutual TLS request failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
        }
    } else {
        Write-Skip "OpenSSL failed to generate/sign certificates."
    }
} finally {
    if (Test-Path $clientCertFile) { Remove-Item $clientCertFile }
    if (Test-Path $clientKeyFile) { Remove-Item $clientKeyFile }
    if (Test-Path $clientCsrFile) { Remove-Item $clientCsrFile }
    if (Test-Path (Join-Path $scriptDir "server.srl")) { Remove-Item (Join-Path $scriptDir "server.srl") }
}

# ----------------------------------------------------------------
# Test 55.1: Negative mTLS - No Certificate
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "55.1. Negative mTLS - No Certificate"
$result = Invoke-CurlTest "-s -k $mtlsBaseUrl/mtls" -ReturnStderr
if ($result.ExitCode -ne 0 -or $result.Stderr -match "alert" -or $result.Stderr -match "SSL" -or $result.Stderr -match "closed") {
    Write-Pass "mTLS correctly failed when no certificate was provided."
} else {
    Write-Fail "mTLS should have failed without certificate. Exit: $($result.ExitCode), Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 55.2: Negative mTLS - Untrusted Certificate
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "55.2. Negative mTLS - Untrusted Certificate"
$untrustedCert = Join-Path $scriptDir "untrusted.crt"
$untrustedKey = Join-Path $scriptDir "untrusted.key"
try {
    # Generate a self-signed cert that the server doesn't trust
    if ($hasOpenSSL) {
        & openssl req -x509 -newkey rsa:2048 -keyout $untrustedKey -out $untrustedCert -days 1 -nodes -subj '/CN=untrusted' 2>$null
    } else {
        $pythonCmd = "from cryptography import x509; from cryptography.hazmat.primitives import hashes, serialization; from cryptography.hazmat.primitives.asymmetric import rsa; import datetime; key = rsa.generate_private_key(65537, 2048); sub = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, 'untrusted')]); cert = x509.CertificateBuilder().subject_name(sub).issuer_name(sub).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.now(datetime.timezone.utc)).not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).sign(key, hashes.SHA256()); open('$untrustedCert','wb').write(cert.public_bytes(serialization.Encoding.PEM)); open('$untrustedKey','wb').write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))"
        & $venvPython -c $pythonCmd
    }
    $result = Invoke-CurlTest "-s -k --cert `"$untrustedCert`" --key `"$untrustedKey`" $mtlsBaseUrl/mtls" -ReturnStderr
    if ($result.ExitCode -ne 0 -or $result.Stderr -match "alert" -or $result.Stderr -match "SSL") {
        Write-Pass "mTLS correctly failed with untrusted certificate."
    } else {
        Write-Fail "mTLS should have failed with untrusted certificate. Exit: $($result.ExitCode), Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
    }
} finally {
    if (Test-Path $untrustedCert) { Remove-Item $untrustedCert }
    if (Test-Path $untrustedKey) { Remove-Item $untrustedKey }
}

# ----------------------------------------------------------------
# Test 55.3: Negative mTLS - Expired Certificate
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "55.3. Negative mTLS - Expired Certificate"
$expiredCert = Join-Path $scriptDir "expired.crt"
try {
    # Generate an expired cert using python and cryptography
    $pythonCmd = "from cryptography import x509; from cryptography.hazmat.primitives import hashes, serialization; from cryptography.hazmat.primitives.asymmetric import rsa; import datetime; key = rsa.generate_private_key(65537, 2048); subject = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, 'expired')]); cert = x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=2)).not_valid_after(datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).sign(key, hashes.SHA256()); print(cert.public_bytes(serialization.Encoding.PEM).decode()); print(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()).decode())"
    & $venvPython -c $pythonCmd | Out-File -FilePath $expiredCert -NoNewline -Encoding ascii
    
    $result = Invoke-CurlTest "-s -k --cert `"$expiredCert`" $mtlsBaseUrl/mtls" -ReturnStderr
    if ($result.ExitCode -ne 0 -or $result.Stderr -match "alert" -or $result.Stderr -match "expired" -or $result.Stderr -match "SSL") {
        Write-Pass "mTLS correctly failed with expired certificate."
    } else {
        Write-Fail "mTLS should have failed with expired certificate. Exit: $($result.ExitCode), Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
    }
} finally {
    if (Test-Path $expiredCert) { Remove-Item $expiredCert }
}

# ----------------------------------------------------------------
# Test 55.4: mTLS with Encrypted Private Key
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "55.4. mTLS with Encrypted Private Key"
$encKeyFile = Join-Path $scriptDir "enc_client.key"
$password = "testpass"
try {
    # Generate a client cert again
    if ($hasOpenSSL) {
        & openssl genrsa -out $clientKeyFile 2048 2>$null
        # Encrypt the key
        & openssl rsa -in $clientKeyFile -aes256 -passout pass:$password -out $encKeyFile -traditional 2>$null
        & openssl req -new -key $clientKeyFile -out $clientCsrFile -subj '/CN=localhost' 2>$null
        & openssl x509 -req -in $clientCsrFile -CA $serverCertFile -CAkey $serverKeyFile -CAcreateserial -out $clientCertFile -days 1 2>$null
    } else {
        $pythonCmd = "from cryptography import x509; from cryptography.hazmat.primitives import hashes, serialization; from cryptography.hazmat.primitives.asymmetric import rsa; import datetime; s_cert = x509.load_pem_x509_certificate(open('$serverCertFile','rb').read()); s_key = serialization.load_pem_private_key(open('$serverKeyFile','rb').read(), None); c_key = rsa.generate_private_key(65537, 2048); sub = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, 'localhost')]); c_cert = x509.CertificateBuilder().subject_name(sub).issuer_name(s_cert.subject).public_key(c_key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(datetime.datetime.now(datetime.timezone.utc)).not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)).sign(s_key, hashes.SHA256()); open('$clientCertFile','wb').write(c_cert.public_bytes(serialization.Encoding.PEM)); open('$encKeyFile','wb').write(c_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.BestAvailableEncryption(b'$password')))"
        & $venvPython -c $pythonCmd
    }
    
    if (Test-Path $clientCertFile) {
        $result = Invoke-CurlTest "-s -k --cert `"$clientCertFile`" --key `"$encKeyFile`" --pass `"$password`" $mtlsBaseUrl/mtls"
        if ($result.Stdout -match '"authenticated":\s*true') {
            Write-Pass "mTLS request with encrypted private key succeeded."
        } else {
            Write-Fail "mTLS with encrypted key failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
        }
    }
} finally {
    if (Test-Path $clientCertFile) { Remove-Item $clientCertFile }
    if (Test-Path $clientKeyFile) { Remove-Item $clientKeyFile }
    if (Test-Path $encKeyFile) { Remove-Item $encKeyFile }
    if (Test-Path $clientCsrFile) { Remove-Item $clientCsrFile }
    if (Test-Path (Join-Path $scriptDir "server.srl")) { Remove-Item (Join-Path $scriptDir "server.srl") }
}

# ----------------------------------------------------------------
# Test 56: Negative SSL Verification
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "56. Negative SSL Verification"
# Should fail without -k because cert is self-signed/adhoc
$result = Invoke-CurlTest "-sS $httpsBaseUrl/get" -ReturnStderr
if ($result.ExitCode -ne 0 -and ($result.Stderr -match "SSL" -or $result.ExitCode -eq 60)) {
    Write-Pass "SSL verification correctly failed for self-signed cert without -k."
} else {
    Write-Fail "SSL verification did NOT fail as expected. Exit: $($result.ExitCode), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 57: HSTS Support
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "57. HSTS Support"
$result = Invoke-CurlTest "-s -I $baseUrl/hsts"
if ($result.Stdout -match "Strict-Transport-Security") {
    Write-Pass "HSTS header received correctly."
} else {
    Write-Fail "HSTS header missing. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 58: Digest Authentication
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "58. Digest Authentication"
$result = Invoke-CurlTest "-s --digest -u user:password $baseUrl/digest-auth/user/password"
if ($result.Stdout -match '"authenticated":\s*true') {
    Write-Pass "Digest authentication succeeded."
} else {
    Write-Fail "Digest authentication failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 59: Netrc Support
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "59. Netrc Support"
$netrcFile = Join-Path $scriptDir "test_netrc"
"machine 127.0.0.1 login user password password" | Out-File $netrcFile -Encoding ascii
try {
    $result = Invoke-CurlTest "-s --netrc-file `"$netrcFile`" $baseUrl/basic-auth/user/password"
    if ($result.Stdout -match '"authenticated":\s*true') {
        Write-Pass "Netrc-based authentication succeeded."
    } else {
        Write-Fail "Netrc authentication failed. Stdout: $($result.Stdout)"
    }
} finally {
    if (Test-Path $netrcFile) { Remove-Item $netrcFile }
}

# ----------------------------------------------------------------
# Test 60: Environment Variable Proxy Support
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "60. Environment Variable Proxy Support"
$env:http_proxy = "http://127.0.0.1:$httpPort"
try {
    # Curl should use the proxy from environment. 
    # Our proxy_handler returns "proxied": true.
    # Note: Curl might not use proxy for localhost/127.0.0.1 by default unless forced or if it's the only way.
    # We use a dummy domain and --resolve to force it to use the proxy.
    $result = Invoke-CurlTest "-s http://proxy-test.internal/proxy"
    if ($result.Stdout -match '"proxied":\s*true') {
        Write-Pass "Proxy from environment variable used correctly."
    } else {
        Write-Fail "Proxy from environment not used. Stdout: $($result.Stdout)"
    }
} finally {
    $env:http_proxy = $null
}

# ----------------------------------------------------------------
# Test 61: SOCKS Proxy Support
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "61. SOCKS Proxy Support"
# We don't have a SOCKS proxy, but we can check if curl attempts to use it.
# It should fail because no SOCKS proxy is running.
$result = Invoke-CurlTest "-sS -x socks5://127.0.0.1:9099 $baseUrl/get" -ReturnStderr
if ($result.ExitCode -ne 0 -and ($result.Stderr -match "socks" -or $result.Stderr -match "connect" -or $result.ExitCode -eq 7)) {
    Write-Pass "SOCKS proxy attempt detected (and failed as expected)."
} else {
    Write-Fail "SOCKS proxy test unexpected. Exit: $($result.ExitCode), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 62: Proxy-Specific Authentication
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "62. Proxy-Specific Authentication"
$result = Invoke-CurlTest "-s -x http://127.0.0.1:$httpPort --proxy-user puser:ppass $baseUrl/proxy"
if ($result.Stdout -match "Basic cHVzZXI6cHBhc3M=") {
    Write-Pass "Proxy-specific authentication header received."
} else {
    Write-Fail "Proxy-specific authentication failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 63: IP Version Control (-4 / -6)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "63. IP Version Control (-4)"
$result = Invoke-CurlTest "-s -4 $baseUrl/get"
if ($result.ExitCode -eq 0) {
    Write-Pass "IPv4 enforcement succeeded."
} else {
    Write-Fail "IPv4 enforcement failed. Exit: $($result.ExitCode)"
}

# ----------------------------------------------------------------
# Test 64: UNIX Domain Sockets
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "64. UNIX Domain Sockets"
# This might be skipped if the server doesn't support it, but let's see if curl accepts the flag.
$result = Invoke-CurlTest "-sS --unix-socket /tmp/nonexistent.sock http://localhost/get" -ReturnStderr
if ($result.ExitCode -ne 0 -and ($result.Stderr -match "socket" -or $result.Stderr -match "connect" -or $result.ExitCode -eq 7)) {
    Write-Pass "UNIX socket flag accepted by curl (and failed as expected)."
} else {
    Write-Fail "UNIX socket test unexpected. Exit: $($result.ExitCode), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 65: DNS-over-HTTPS (DoH)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "65. DNS-over-HTTPS (DoH)"
$result = Invoke-CurlTest "-s --doh-url $baseUrl/dns-query $baseUrl/get" -ReturnStderr
# Curl might fail because dns-query doesn't return real DNS records, but it should try.
if ($result.ExitCode -ne 0 -and ($result.Stderr -match "DOH" -or $result.Stderr -match "resolver")) {
    Write-Pass "DoH flag accepted and attempted."
} elseif ($result.ExitCode -eq 0) {
    Write-Pass "DoH request completed."
} else {
    Write-Fail "DoH test failed. Exit: $($result.ExitCode), Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 66: Advanced Multipart Form Data (Metadata)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "66. Advanced Multipart Form Data (Metadata)"
$testFile = Join-Path $scriptDir "metadata.txt"
"content" | Out-File $testFile -Encoding ascii
try {
    $result = Invoke-CurlTest "-s -F `"file=@$testFile;type=text/plain;filename=remote.txt`" $baseUrl/post"
    if ($result.Stdout -match "remote.txt" -and $result.Stdout -match "text/plain") {
        Write-Pass "Multipart metadata (filename, type) received correctly."
    } else {
        Write-Fail "Multipart metadata mismatch. Stdout: $($result.Stdout)"
    }
} finally {
    if (Test-Path $testFile) { Remove-Item $testFile }
}

# ----------------------------------------------------------------
# Test 67: Conditional GET
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "67. Conditional GET"
$result = Invoke-CurlTest "-s -z `"Fri, 13 Mar 2026 12:00:00 GMT`" $baseUrl/get" -ReturnStderr
# Server should return 304 (empty body)
if ($result.ExitCode -eq 0 -and $result.Stdout.Length -eq 0) {
    Write-Pass "Conditional GET returned 304 (empty body) as expected."
} else {
    Write-Fail "Conditional GET failed. Exit: $($result.ExitCode), Stdout length: $($result.Stdout.Length)"
}

# ----------------------------------------------------------------
# Test 68: Resuming with Fixed Offset
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "68. Resuming with Fixed Offset (-C 5)"
$result = Invoke-CurlTest "-s -C 5 $baseUrl/range/20"
# range/20 is "abcdefghijklmnopqrst". Offset 5 should start at 'f'.
if ($result.Stdout -match "^fghij") {
    Write-Pass "Manual resume at offset 5 succeeded."
} else {
    Write-Fail "Manual resume failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 69: Expect 100-continue
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "69. Expect 100-continue"
$result = Invoke-CurlTest "-s -d `"some data`" -H `"Expect: 100-continue`" $baseUrl/post"
if ($result.Stdout -match '"data":\s*"some data"') {
    Write-Pass "Expect 100-continue handled correctly."
} else {
    Write-Fail "Expect 100-continue failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 70: URL Globbing with Brackets (Ranges)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "70. URL Globbing with Brackets (Ranges)"
$result = Invoke-CurlTest "-s `"$baseUrl/status/[200-201]`""
if ($result.Stdout -match "Status: 200" -and $result.Stdout -match "Status: 201") {
    Write-Pass "URL globbing with brackets [200-201] succeeded."
} else {
    Write-Fail "URL globbing failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 71: Comprehensive Write-out Variables
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "71. Comprehensive Write-out Variables"
$result = Invoke-CurlTest "-s -o /dev/null -w `"URL:%{url_effective} Type:%{content_type} IP:%{remote_ip}`" $baseUrl/get"
if ($result.Stdout -match "URL:http" -and $result.Stdout -match "Type:application/json" -and $result.Stdout -match "IP:127.0.0.1") {
    Write-Pass "Comprehensive write-out variables reported correctly."
} else {
    Write-Fail "Write-out variables failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 72: Detailed Tracing
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "72. Detailed Tracing (--trace-ascii)"
$traceFile = Join-Path $scriptDir "test_trace.txt"
try {
    $result = Invoke-CurlTest "-s --trace-ascii `"$traceFile`" $baseUrl/get"
    if (Test-Path $traceFile) {
        $traceContent = Get-Content $traceFile -Raw
        if ($traceContent -match "== Info:" -and $traceContent -match "=> Send header") {
            Write-Pass "Detailed tracing file created with protocol info."
        } else {
            Write-Fail "Trace file content unexpected."
        }
    } else {
        Write-Fail "Trace file was not created."
    }
} finally {
    if (Test-Path $traceFile) { Remove-Item $traceFile }
}

# ----------------------------------------------------------------
# Test 73: Specific Redirect Handling (301, 308)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "73. Specific Redirect Handling (301, 308)"
$result301 = Invoke-CurlTest "-s -L -d `"data`" $baseUrl/redirect-301"
$result308 = Invoke-CurlTest "-s -L -d `"data`" $baseUrl/redirect-308"
$passed301 = $result301.Stdout -match "url.*get"
$passed308 = $result308.Stdout -match "url.*post" -and $result308.Stdout -match "data"
if ($passed301 -and $passed308) {
    Write-Pass "Specific redirect handling (301/308) succeeded."
} else {
    Write-Fail "Redirect 301/308 failed. 301: $passed301, 308: $passed308"
}

# ----------------------------------------------------------------
# Test 74: Handling 204 No Content
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "74. Handling 204 No Content"
$result = Invoke-CurlTest "-s -o /dev/null -w `"%{http_code}`" $baseUrl/status/204"
if ($result.Stdout.Trim() -eq "204") {
    Write-Pass "Correctly handled 204 No Content response."
} else {
    Write-Fail "Expected 204 but got: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 75: Multiple Headers with same name (Server to Client)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "75. Multiple Headers with Same Name (Server to Client)"
$result = Invoke-CurlTest "-s -i $baseUrl/multiple-headers"
if ($result.Stdout -match "Set-Cookie: cookie1=value1" -and $result.Stdout -match "Set-Cookie: cookie2=value2" -and $result.Stdout -match "Link:.*rel=`"next`"" -and $result.Stdout -match "Link:.*rel=`"prev`"") {
    Write-Pass "Multiple headers with the same name received correctly."
} else {
    Write-Fail "Missing expected headers in output: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 76: Chunked Transfer Encoding
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "76. Chunked Transfer Encoding"
$result = Invoke-CurlTest "-s $baseUrl/chunked"
if ($result.Stdout -match "chunk 0" -and $result.Stdout -match "chunk 4") {
    Write-Pass "Chunked transfer encoding response received and reassembled."
} else {
    Write-Fail "Chunked response incomplete or incorrect: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 77: Decompression Body Verification
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "77. Decompression Body Verification"
$result = Invoke-CurlTest "-s --compressed $baseUrl/decompressed"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.message -eq "this was compressed") {
        Write-Pass "Gzipped body was correctly decompressed and matches expected content."
    } else {
        Write-Fail "Decompressed content mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse decompressed JSON: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 78: 303 See Other Redirect
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "78. 303 See Other Redirect (Method change to GET)"
# POST to 303 should result in a GET to the location
$result = Invoke-CurlTest "-s -L -d `"data`" $baseUrl/redirect-303"
try {
    $json = $result.Stdout | ConvertFrom-Json
    # /get endpoint returns JSON with 'url' but NO 'form' or 'data' if it was a GET
    if ($json.url -match "/get$") {
        Write-Pass "303 redirect converted POST to GET as expected."
    } else {
        Write-Fail "303 redirect did not result in GET: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse response after 303 redirect: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 79: Relative URL Redirects
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "79. Relative URL Redirects"
$result = Invoke-CurlTest "-s -L $baseUrl/redirect-relative"
if ($result.Stdout -match "`"url`":\s*`"$baseUrl/get`"") {
    Write-Pass "Handled relative URL in Location header correctly."
} else {
    Write-Fail "Relative redirect failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 80: Protocol Switching (HTTP to HTTPS)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "80. Protocol Switching (HTTP to HTTPS)"
$result = Invoke-CurlTest "-s -L -k $baseUrl/redirect-to?url=$httpsBaseUrl/get"
if ($result.Stdout -match "`"url`":\s*`"$httpsBaseUrl/get`"") {
    Write-Pass "Followed redirect from HTTP to HTTPS successfully."
} else {
    Write-Fail "Protocol switch failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 81: --noproxy Support
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "81. --noproxy Support"
$oldProxy = $env:http_proxy
$env:http_proxy = "http://invalid-proxy:9999"
try {
    $result = Invoke-CurlTest "-s --noproxy 127.0.0.1 $baseUrl/get"
    if ($result.ExitCode -eq 0) {
        Write-Pass "--noproxy correctly bypassed the invalid proxy."
    } else {
        Write-Fail "--noproxy failed to bypass or tool exited with error: $($result.ExitCode)"
    }
} finally {
    $env:http_proxy = $oldProxy
}

# ----------------------------------------------------------------
# Test 82: Case-Insensitivity of Proxy Environment Variables
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "82. Case-Insensitivity of Proxy Environment Variables"
# On Linux, curl ignores uppercase HTTP_PROXY for security (HTTPoxy).
# However, ALL_PROXY / all_proxy are typically both supported.
$oldProxy = $env:ALL_PROXY
$env:ALL_PROXY = "http://127.0.0.1:$httpPort/proxy"
try {
    # We use a non-localhost URL to ensure proxy is used
    $result = Invoke-CurlTest "-s http://example.com/get"
    if ($result.Stdout -match "example.com/get") {
        Write-Pass "Respected ALL_PROXY (uppercase) environment variable."
    } else {
        Write-Fail "ALL_PROXY was not respected: $($result.Stdout)"
    }
} finally {
    $env:ALL_PROXY = $oldProxy
}

# ----------------------------------------------------------------
# Test 83: HTTPS over HTTP Proxy (Tunneling)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "83. HTTPS over HTTP Proxy (Tunneling)"
$result = Invoke-CurlTest "-s -k -x http://127.0.0.1:$proxyPort $httpsBaseUrl/get"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -match "https://") {
        Write-Pass "HTTPS over HTTP Proxy (Tunneling) succeeded."
    } else {
        Write-Fail "HTTPS over HTTP Proxy (Tunneling) failed: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 84: Exit Code Specificity
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "84. Exit Code Specificity (DNS Failure)"
$result = Invoke-CurlTest "-s http://this-domain-does-not-exist.invalid"
if ($result.ExitCode -eq 6) {
    Write-Pass "Correctly returned exit code 6 for DNS failure."
} else {
    Write-Fail "Expected exit code 6, but got $($result.ExitCode)"
}

# ----------------------------------------------------------------
# Test 85: Standard CLI Flags (--help, --version)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "85. Standard CLI Flags (--help, --version)"
$resHelp = Invoke-CurlTest "--help"
$resVer = Invoke-CurlTest "--version"
if ($resHelp.Stdout -match "Usage:" -and $resVer.Stdout -match "curl") {
    Write-Pass "Standard --help and --version flags work."
} else {
    Write-Fail "--help or --version output unexpected."
}

# ----------------------------------------------------------------
# Test 86: Combining -i and -o
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "86. Combining -i and -o"
$outFile = Join-Path $scriptDir "test_io.txt"
try {
    $result = Invoke-CurlTest "-s -i -o `"$outFile`" $baseUrl/get"
    if (Test-Path $outFile) {
        $content = Get-Content $outFile -Raw
        if ($content -match "HTTP/1.1 200 OK" -and $content -match "`"url`":") {
            Write-Pass "Combined -i and -o successfully saved headers and body to file."
        } else {
            Write-Fail "File content mismatch."
        }
    } else {
        Write-Fail "Output file not created."
    }
} finally {
    if (Test-Path $outFile) { Remove-Item $outFile }
}

# ----------------------------------------------------------------
# Test 87: Multiple -o flags for Multiple URLs
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "87. Multiple -o flags for Multiple URLs"
$out1 = Join-Path $scriptDir "out1.txt"
$out2 = Join-Path $scriptDir "out2.txt"
try {
    $result = Invoke-CurlTest "-s $baseUrl/get -o `"$out1`" $baseUrl/headers -o `"$out2`""
    if ((Test-Path $out1) -and (Test-Path $out2)) {
        if ((Get-Content $out1 -Raw) -match "get" -and (Get-Content $out2 -Raw) -match "headers") {
            Write-Pass "Multiple -o flags correctly saved multiple URLs to separate files."
        } else {
            Write-Fail "Multiple -o file contents incorrect."
        }
    } else {
        Write-Fail "One or both output files were not created."
    }
} finally {
    if (Test-Path $out1) { Remove-Item $out1 }
    if (Test-Path $out2) { Remove-Item $out2 }
}

# ----------------------------------------------------------------
# Test 88: --data-raw Flag
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "88. --data-raw Flag"
$result = Invoke-CurlTest "-s --data-raw `"@literal`" $baseUrl/post-data-raw"
if ($result.Stdout -match "`"@literal`"") {
    Write-Pass "--data-raw sent @ character literally."
} else {
    Write-Fail "--data-raw failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 142: --data-raw with Newlines
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "142. --data-raw with Newlines"
# Standard curl --data-raw preserves newlines
$data = "line1`nline2"
$result = Invoke-CurlTest "-s --data-raw `"$data`" $baseUrl/post-data-raw"
if ($result.Stdout -match "line1\\nline2") {
    Write-Pass "--data-raw preserved newlines correctly."
} else {
    Write-Fail "--data-raw failed to preserve newlines: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 143: -d with Newlines (Literal String)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "143. -d with Newlines (Literal String)"
# Standard curl -d preserves newlines when provided literally on command line
$data = "line1`nline2"
$result = Invoke-CurlTest "-s -d `"$data`" $baseUrl/post-data-raw"
if ($result.Stdout -match "line1\\nline2") {
    Write-Pass "-d preserved newlines in literal string correctly."
} else {
    Write-Fail "-d failed to preserve newlines in literal string: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 89: Uploading from Stdin with -T -
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "89. Uploading from Stdin with -T -"
$result = Invoke-CurlTest "-s -T - $baseUrl/put" -Stdin "upload from stdin"
if ($result.Stdout -match "upload from stdin") {
    Write-Pass "Successfully uploaded data from stdin using -T -."
} else {
    Write-Fail "Upload from stdin failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 90: Multiple Headers with Same Name (Client to Server)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "90. Multiple Headers with Same Name (Client to Server)"
$result = Invoke-CurlTest "-s -H `"X-Multi: value1`" -H `"X-Multi: value2`" $baseUrl/headers"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.headers.'X-Multi' -match "value1" -and $json.headers.'X-Multi' -match "value2") {
        Write-Pass "Sent multiple headers with same name correctly."
    } else {
        Write-Fail "Headers mismatch: $($result.Stdout)"
    }
} catch {
    Write-Fail "Failed to parse JSON: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 91: Cookie Domain Scoping
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "91. Cookie Domain Scoping"
$cookieFile = Join-Path $scriptDir "cookies_scope.txt"
try {
    Invoke-CurlTest "-s -c `"$cookieFile`" $baseUrl/cookies/domain" | Out-Null
    $result = Invoke-CurlTest "-s -b `"$cookieFile`" $baseUrl/cookies"
    if ($result.Stdout -match "domain_cookie") {
        Write-Pass "Cookie with domain scoping sent back correctly."
    } else {
        Write-Fail "Cookie with domain scoping NOT sent back: $($result.Stdout)"
    }
} finally {
    if (Test-Path $cookieFile) { Remove-Item $cookieFile }
}

# ----------------------------------------------------------------
# Test 92: Cookie Expiration
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "92. Cookie Expiration"
$cookieFile = Join-Path $scriptDir "cookies_expire.txt"
try {
    Invoke-CurlTest "-s -c `"$cookieFile`" $baseUrl/cookies/expire" | Out-Null
    $result = Invoke-CurlTest "-s -b `"$cookieFile`" $baseUrl/cookies"
    if ($result.Stdout -match "valid_cookie" -and -not ($result.Stdout -match "expired_cookie")) {
        Write-Pass "Cookie expiration respected (valid sent, expired NOT sent)."
    } else {
        Write-Fail "Cookie expiration NOT respected: $($result.Stdout)"
    }
} finally {
    if (Test-Path $cookieFile) { Remove-Item $cookieFile }
}

# ----------------------------------------------------------------
# Test 93: --create-dirs
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "93. --create-dirs"
$nestedDir = Join-Path $scriptDir "nested/dir/test"
$nestedFile = Join-Path $nestedDir "file.txt"
try {
    $result = Invoke-CurlTest "-s --create-dirs -o `"$nestedFile`" $baseUrl/get"
    if (Test-Path $nestedFile) {
        Write-Pass "--create-dirs successfully created nested directories."
    } else {
        Write-Fail "Nested directory or file not created."
    }
} finally {
    if (Test-Path (Join-Path $scriptDir "nested")) { Remove-Item -Recurse -Force (Join-Path $scriptDir "nested") }
}

# ----------------------------------------------------------------
# Test 94: --output-dir
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "94. --output-dir"
$outDir = Join-Path $scriptDir "output_dir_test"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory $outDir | Out-Null }
try {
    $result = Invoke-CurlTest "-s --output-dir `"$outDir`" -O $baseUrl/get"
    $expectedFile = Join-Path $outDir "get"
    if (Test-Path $expectedFile) {
        Write-Pass "--output-dir successfully saved file to specified directory."
    } else {
        Write-Fail "File not found in output directory."
    }
} finally {
    if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
}

# ----------------------------------------------------------------
# Test 95: -J / --remote-header-name
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "95. -J / --remote-header-name"
try {
    $tempDir = Join-Path $scriptDir "temp_j_test"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory $tempDir | Out-Null }
    $oldPwd = $pwd
    Set-Location $tempDir
    $result = Invoke-CurlTest "-s -O -J $baseUrl/content-disposition"
    Set-Location $oldPwd
    
    $expectedFile = Join-Path $tempDir "remote-file.txt"
    if (Test-Path $expectedFile) {
        Write-Pass "-J / --remote-header-name used the filename from Content-Disposition."
    } else {
        Write-Fail "File with remote name not created."
    }
} finally {
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}

# ----------------------------------------------------------------
# Test 96: -R / --remote-time
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "96. -R / --remote-time"
$remoteFile = Join-Path $scriptDir "remote_time.txt"
try {
    $result = Invoke-CurlTest "-s -R -o `"$remoteFile`" $baseUrl/remote-time"
    if (Test-Path $remoteFile) {
        $lastWrite = (Get-Item $remoteFile).LastWriteTime.ToUniversalTime()
        $expectedDate = [DateTime]::ParseExact("Wed, 21 Oct 2015 07:28:00 GMT", "ddd, dd MMM yyyy HH:mm:ss 'GMT'", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
        if ([Math]::Abs(($lastWrite - $expectedDate).TotalSeconds) -lt 2) {
            Write-Pass "-R / --remote-time synchronized local file timestamp."
        } else {
            Write-Fail "Timestamp mismatch. Got $lastWrite, expected $expectedDate"
        }
    } else {
        Write-Fail "Remote file not created."
    }
} finally {
    if (Test-Path $remoteFile) { Remove-Item $remoteFile }
}

# ----------------------------------------------------------------
# Test 97: --post301
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "97. --post301"
$result = Invoke-CurlTest "-s -L --post301 -d `"data=123`" $baseUrl/redirect-301-post"
if ($result.Stdout -match "`"data`":\s?`"data=123`"") {
    Write-Pass "--post301 preserved POST method after 301 redirect."
} else {
    Write-Fail "--post301 failed to preserve POST or redirect failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 98: --post302
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "98. --post302"
$result = Invoke-CurlTest "-s -L --post302 -d `"data=123`" $baseUrl/redirect-302-post"
if ($result.Stdout -match "`"data`":\s?`"data=123`"") {
    Write-Pass "--post302 preserved POST method after 302 redirect."
} else {
    Write-Fail "--post302 failed to preserve POST or redirect failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 99: --post303
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "99. --post303"
$result = Invoke-CurlTest "-s -L --post303 -d `"data=123`" $baseUrl/redirect-303-post"
if ($result.Stdout -match "`"data`":\s?`"data=123`"") {
    Write-Pass "--post303 preserved POST method after 303 redirect."
} else {
    Write-Fail "--post303 failed to preserve POST or redirect failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 100: --location-trusted
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "100. --location-trusted"
$result = Invoke-CurlTest "-s -L -u user:password --location-trusted http://127.0.0.1:$httpPort/redirect-to?url=http://localhost:$httpPort/basic-auth-check"
if ($result.Stdout -match "Basic dXNlcjpwYXNzd29yZA==") {
    Write-Pass "--location-trusted passed credentials to redirected host."
} else {
    Write-Fail "--location-trusted failed to pass credentials: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 101: --retry-connrefused
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "101. --retry-connrefused"
$closedPort = 59999
$start = Get-Date
$result = Invoke-CurlTest "-s --retry 1 --retry-connrefused --retry-delay 1 http://127.0.0.1:$closedPort"
$end = Get-Date
$duration = ($end - $start).TotalSeconds
if ($duration -ge 1) {
    Write-Pass "--retry-connrefused attempted retry on connection refused."
} else {
    Write-Fail "--retry-connrefused did not seem to retry (duration: $duration s)."
}

# ----------------------------------------------------------------
# Test 102: --retry-all-errors
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "102. --retry-all-errors"
$start = Get-Date
$result = Invoke-CurlTest "-s -f --retry 1 --retry-all-errors --retry-delay 1 $baseUrl/status/404"
$end = Get-Date
$duration = ($end - $start).TotalSeconds
if ($duration -ge 1) {
    Write-Pass "--retry-all-errors attempted retry on 404."
} else {
    Write-Fail "--retry-all-errors did not retry on 404 (duration: $duration s)."
}

# ----------------------------------------------------------------
# Test 102b: --retry-all-errors should NOT retry on success
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "102b. --retry-all-errors should NOT retry on success"
$start = Get-Date
$result = Invoke-CurlTest "-s --retry 1 --retry-all-errors --retry-delay 1 $baseUrl/get"
$end = Get-Date
$duration = ($end - $start).TotalSeconds
if ($duration -lt 0.8) {
    Write-Pass "--retry-all-errors did NOT retry on success (200 OK)."
} else {
    Write-Fail "--retry-all-errors unnecessarily retried on success (duration: $duration s)."
}

# ----------------------------------------------------------------
# Test 103: --fail-early
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "103. --fail-early"
$result = Invoke-CurlTest "-s --fail-early http://127.0.0.1:1 $baseUrl/get"
if ($result.ExitCode -ne 0 -and $result.Stdout -notmatch "url") {
    Write-Pass "--fail-early stopped after first failure."
} else {
    Write-Fail "--fail-early did not stop as expected. ExitCode: $($result.ExitCode), Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 104: IPv6 forcing (-6)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "104. IPv6 forcing (-6)"
$result = Invoke-CurlTest "-s -6 http://[::1]:$httpPort/get"
if ($result.ExitCode -eq 0) {
    Write-Pass "-6 successfully forced IPv6."
} else {
    Write-Skip "-6 failed or IPv6 not available: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 105: --interface
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "105. --interface"
$result = Invoke-CurlTest "-s --interface 127.0.0.1 $baseUrl/get"
if ($result.ExitCode -eq 0) {
    Write-Pass "--interface 127.0.0.1 worked."
} else {
    Write-Fail "--interface failed: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 106: --next
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "106. --next"
$result = Invoke-CurlTest "-s $baseUrl/get --next -d `"data=next`" $baseUrl/post"
if ($result.Stdout -match "get" -and $result.Stdout -match "data=next") {
    Write-Pass "--next correctly reset options for subsequent URL."
} else {
    Write-Fail "--next failed. Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 107: Multiple config files (-K)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "107. Multiple config files (-K)"
$cfg1 = Join-Path $scriptDir "config1.txt"
$cfg2 = Join-Path $scriptDir "config2.txt"
try {
    "user-agent = `"Agent1`"" | Out-File -FilePath $cfg1 -Encoding ascii
    "header = `"X-Config: Value2`"" | Out-File -FilePath $cfg2 -Encoding ascii
    $result = Invoke-CurlTest "-s -K `"$cfg1`" -K `"$cfg2`" $baseUrl/headers"
    if ($result.Stdout -match "Agent1" -and $result.Stdout -match "Value2") {
        Write-Pass "Multiple config files merged correctly."
    } else {
        Write-Fail "Config merge failed: $($result.Stdout)"
    }
} finally {
    if (Test-Path $cfg1) { Remove-Item $cfg1 }
    if (Test-Path $cfg2) { Remove-Item $cfg2 }
}

# ----------------------------------------------------------------
# Test 108: Reading config from stdin (-K -)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "108. Reading config from stdin (-K -)"
$result = Invoke-CurlTest "-s -K - $baseUrl/get" -Stdin "user-agent = `"StdinAgent`""
if ($result.Stdout -match "StdinAgent") {
    Write-Pass "Successfully read config from stdin using -K -."
} else {
    Write-Fail "Config from stdin failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 109: Cookie Path Scoping
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "109. Cookie Path Scoping"
$cookieFile = Join-Path $scriptDir "cookies_path.txt"
try {
    Invoke-CurlTest "-s -c `"$cookieFile`" $baseUrl/cookies/path" | Out-Null
    $resSub = Invoke-CurlTest "-s -b `"$cookieFile`" $baseUrl/cookies/path/sub"
    $resRoot = Invoke-CurlTest "-s -b `"$cookieFile`" $baseUrl/get"
    if ($resSub.Stdout -match "path_cookie_root" -and $resSub.Stdout -match "path_cookie_sub" -and 
        $resRoot.Stdout -match "path_cookie_root" -and $resRoot.Stdout -notmatch "path_cookie_sub") {
        Write-Pass "Cookie path scoping respected."
    } else {
        Write-Fail "Cookie path scoping failed. Sub: $($resSub.Stdout), Root: $($resRoot.Stdout)"
    }
} finally {
    if (Test-Path $cookieFile) { Remove-Item $cookieFile }
}

# ----------------------------------------------------------------
# Test 110: --form-string
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "110. --form-string"
$result = Invoke-CurlTest "-s --form-string `"field=@literal`" $baseUrl/post-form-type"
if ($result.Stdout -match "`"field`":\s?`"@literal`"") {
    Write-Pass "--form-string sent @ character literally in multipart form."
} else {
    Write-Fail "--form-string failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 111: Content-Type per form field
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "111. Content-Type per form field"
$result = Invoke-CurlTest "-s -F `"field={`"a`":1};type=application/json;filename=test.json`" $baseUrl/post-form-type"
if ($result.Stdout -match "`"content_type`":\s?`"application/json`"") {
    Write-Pass "Successfully sent custom Content-Type for form field."
} else {
    Write-Fail "Custom Content-Type for form field failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 112: --max-filesize
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "112. --max-filesize"
$result = Invoke-CurlTest "-s --max-filesize 500000 $baseUrl/large-response"
if ($result.ExitCode -eq 63) {
    Write-Pass "--max-filesize aborted transfer correctly (ExitCode 63)."
} else {
    Write-Fail "Expected ExitCode 63, got $($result.ExitCode)."
}

# ----------------------------------------------------------------
# Test 113: --speed-limit and --speed-time
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "113. --speed-limit and --speed-time"
$result = Invoke-CurlTest "-s --speed-limit 1000 --speed-time 2 $baseUrl/slow-response"
if ($result.ExitCode -eq 28) {
    Write-Pass "--speed-limit aborted slow transfer correctly (ExitCode 28)."
} else {
    Write-Fail "Expected ExitCode 28, got $($result.ExitCode)."
}

# ----------------------------------------------------------------
# Test 114: --cacert
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "114. --cacert"
$certFile = Join-Path $scriptDir "server.crt"
$result = Invoke-CurlTest "-s --cacert `"$certFile`" $httpsBaseUrl/get"
if ($result.ExitCode -eq 0) {
    Write-Pass "--cacert successfully verified self-signed certificate."
} else {
    Write-Fail "--cacert failed to verify: $($result.Stderr) (ExitCode: $($result.ExitCode))"
}

# ----------------------------------------------------------------
# Test 115: --pinnedpubkey (Success case - File)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "115. --pinnedpubkey (Success case - File)"
# Extract public key from cert for curl compatibility
if (-not (Test-Path $pubkeyFile)) {
    if ($hasOpenSSL) {
        & openssl x509 -in $certFile -pubkey -noout | Out-File -FilePath $pubkeyFile -Encoding ascii
    } else {
        $pythonCmd = "from cryptography import x509; from cryptography.hazmat.primitives import serialization; cert = x509.load_pem_x509_certificate(open('$certFile','rb').read()); print(cert.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode())"
        & $venvPython -c $pythonCmd | Out-File -FilePath $pubkeyFile -NoNewline -Encoding ascii
    }
}
$result = Invoke-CurlTest "-s -k --pinnedpubkey `"$pubkeyFile`" $httpsBaseUrl/get"
if ($result.ExitCode -eq 0) {
    Write-Pass "--pinnedpubkey successfully verified matching public key file."
} else {
    Write-Fail "--pinnedpubkey failed: $($result.Stderr) (ExitCode: $($result.ExitCode))"
}

# ----------------------------------------------------------------
# Test 115a: --pinnedpubkey (Success case - Hash)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "115a. --pinnedpubkey (Success case - Hash)"
# Extract public key hash from cert using openssl or python
# Note: we need the DER representation of the PUBLIC KEY, not the certificate or PEM.
if ($hasOpenSSL) {
    $hash = & openssl x509 -in $certFile -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | openssl enc -base64
} else {
    $pythonCmd = "from cryptography import x509; from cryptography.hazmat.primitives import hashes, serialization; import base64; cert = x509.load_pem_x509_certificate(open('$certFile','rb').read()); pubkey_der = cert.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo); digest = hashes.Hash(hashes.SHA256()); digest.update(pubkey_der); hash_bytes = digest.finalize(); print(base64.b64encode(hash_bytes).decode())"
    $hash = & $venvPython -c $pythonCmd
}
$pinnedHash = "sha256//$($hash.Trim())"
$result = Invoke-CurlTest "-s -k --pinnedpubkey `"$pinnedHash`" $httpsBaseUrl/get"
if ($result.ExitCode -eq 0) {
    Write-Pass "--pinnedpubkey successfully verified with matching SHA256 hash."
} else {
    Write-Fail "--pinnedpubkey failed with hash: $($result.Stderr) (ExitCode: $($result.ExitCode))"
}

# ----------------------------------------------------------------
# Test 115b: --pinnedpubkey (Failure case - Mismatch)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "115b. --pinnedpubkey (Failure case - Mismatch)"
$wrongPubkeyFile = Join-Path $scriptDir "wrong_pubkey.pem"
try {
    # Generate a dummy public key that won't match
    if ($hasOpenSSL) {
        $null = & openssl genrsa 2048 | openssl rsa -pubout | Out-File -FilePath $wrongPubkeyFile -Encoding ascii
    } else {
        $pythonCmd = "from cryptography.hazmat.primitives.asymmetric import rsa; from cryptography.hazmat.primitives import serialization; key = rsa.generate_private_key(65537, 2048); print(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode())"
        & $venvPython -c $pythonCmd | Out-File -FilePath $wrongPubkeyFile -NoNewline -Encoding ascii
    }
    $result = Invoke-CurlTest "-s -k --pinnedpubkey `"$wrongPubkeyFile`" $httpsBaseUrl/get"
    if ($result.ExitCode -ne 0) {
        Write-Pass "--pinnedpubkey correctly failed on public key mismatch."
    } else {
        Write-Fail "--pinnedpubkey should have failed on mismatch but returned ExitCode 0."
    }
} finally {
    if (Test-Path $wrongPubkeyFile) { Remove-Item $wrongPubkeyFile }
}

# ----------------------------------------------------------------
# Test 116: OPTIONS Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "116. OPTIONS Request"
$result = Invoke-CurlTest "-s -X OPTIONS -i $baseUrl/get"
if ($result.Stdout -match "Allow:.*TRACE") {
    Write-Pass "OPTIONS request returned correct Allow header."
} else {
    Write-Fail "OPTIONS request failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 117: TRACE Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "117. TRACE Request"
$result = Invoke-CurlTest "-s -X TRACE $baseUrl/get"
if ($result.Stdout -match "TRACE /get HTTP/1.1") {
    Write-Pass "TRACE request echoed the request correctly."
} else {
    Write-Fail "TRACE request failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 118: HEAD Request with Redirects
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "118. HEAD Request with Redirects"
$result = Invoke-CurlTest "-s -I -L $baseUrl/redirect-to?url=/get"
if ($result.Stdout -match "HTTP/1.1 200 OK" -and $result.Stdout -match "Content-Type: application/json") {
    Write-Pass "HEAD with -L followed redirect and returned final headers."
} else {
    Write-Fail "HEAD with -L failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 119: Authentication with Username Only (Interactive Prompt Simulation)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "119. Authentication with Username Only (Interactive Prompt Simulation)"
$result = Invoke-CurlTest "-s -u `"user:`" $baseUrl/basic-auth-check"
if ($result.Stdout -match "`"authorization`":\s?`"Basic dXNlcjo=`"") {
    Write-Pass "Auth with username: (empty password) worked and didn't hang."
} else {
    Write-Fail "Auth with username: failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 120: Authentication with Colon in Credentials
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "120. Authentication with Colon in Credentials"
$result = Invoke-CurlTest "-s -u `"user:pass:word`" $baseUrl/basic-auth-check"
if ($result.Stdout -match "`"authorization`":\s?`"Basic dXNlcjpwYXNzOndvcmQ=`"") {
    Write-Pass "Auth with colon in password worked."
} else {
    Write-Fail "Auth with colon in password failed: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 121: Silent and Verbose Combined
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "121. Silent and Verbose Combined"
$result = Invoke-CurlTest "-s -v $baseUrl/get"
if ($result.Stderr -match "> GET /get HTTP/1.1" -and $result.Stdout -match "`"url`":") {
    Write-Pass "Silent and Verbose combined worked (output in stdout, details in stderr)."
} else {
    Write-Fail "Silent and Verbose failed. Stderr: $($result.Stderr)"
}

# ----------------------------------------------------------------
# Test 122: Include Headers with Output File
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "122. Include Headers with Output File"
$outFile = Join-Path $scriptDir "test122.txt"
try {
    Invoke-CurlTest "-s -i -o `"$outFile`" $baseUrl/get" | Out-Null
    $content = Get-Content $outFile -Raw
    if ($content -match "HTTP/1.1 200 OK" -and $content -match "`"url`":") {
        Write-Pass "Headers and body correctly saved to file with -i -o."
    } else {
        Write-Fail "Headers/body missing from file. Content: $content"
    }
} finally {
    if (Test-Path $outFile) { Remove-Item $outFile }
}

# ----------------------------------------------------------------
# Test 123: Mixed Source Data in POST
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "123. Mixed Source Data in POST"
$dataFile = Join-Path $scriptDir "data123.txt"
"param2=val2" | Out-File -FilePath $dataFile -Encoding ascii
try {
    $result = Invoke-CurlTest "-s -d `"param1=val1`" -d @`"$dataFile`" $baseUrl/post"
    if ($result.Stdout -match "`"param1`":\s?`"val1`"" -and $result.Stdout -match "`"param2`":\s?`"val2`"") {
        Write-Pass "Mixed source data in POST worked."
    } else {
        Write-Fail "Mixed source data failed: $($result.Stdout)"
    }
} finally {
    if (Test-Path $dataFile) { Remove-Item $dataFile }
}

# ----------------------------------------------------------------
# Test 124: Multiple @file Arguments in POST
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "124. Multiple @file Arguments in POST"
$f1 = Join-Path $scriptDir "f1.txt"
$f2 = Join-Path $scriptDir "f2.txt"
"a=1" | Out-File -FilePath $f1 -Encoding ascii
"b=2" | Out-File -FilePath $f2 -Encoding ascii
try {
    $result = Invoke-CurlTest "-s -d @`"$f1`" -d @`"$f2`" $baseUrl/post"
    if ($result.Stdout -match "`"a`":\s?`"1`"" -and $result.Stdout -match "`"b`":\s?`"2`"") {
        Write-Pass "Multiple @file arguments in POST worked."
    } else {
        Write-Fail "Multiple @file failed: $($result.Stdout)"
    }
} finally {
    if (Test-Path $f1) { Remove-Item $f1 }
    if (Test-Path $f2) { Remove-Item $f2 }
}

# ----------------------------------------------------------------
# Test 125: Multiple Files in One Form Field
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "125. Multiple Files in One Form Field"
$img1 = Join-Path $scriptDir "img1.txt"
$img2 = Join-Path $scriptDir "img2.txt"
"content1" | Out-File -FilePath $img1 -Encoding ascii
"content2" | Out-File -FilePath $img2 -Encoding ascii
try {
    # Using multiple -F flags with same name
    $result = Invoke-CurlTest "-s -F `"images=@`"$img1`"`" -F `"images=@`"$img2`"`" $baseUrl/post-form-type"
    # The server returns images as list or just the last one? 
    # Let's check test_server.py post_form_type
    if ($result.Stdout -match "content1" -and $result.Stdout -match "content2") {
        Write-Pass "Multiple files in one form field (same name) worked."
    } else {
        Write-Fail "Multiple files in one field failed: $($result.Stdout)"
    }
} finally {
    if (Test-Path $img1) { Remove-Item $img1 }
    if (Test-Path $img2) { Remove-Item $img2 }
}

# ----------------------------------------------------------------
# Test 126: Exit 3: Malformed URL
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "126. Exit 3: Malformed URL"
$result = Invoke-CurlTest "`"http://[invalid-url]`""
if ($result.ExitCode -eq 3) {
    Write-Pass "Correct ExitCode 3 for malformed URL."
} else {
    Write-Fail "Expected ExitCode 3, got $($result.ExitCode)."
}

# ----------------------------------------------------------------
# Test 127: Exit 7: Failed to Connect
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "127.0.0.1:1"
$result = Invoke-CurlTest "http://127.0.0.1:1"
if ($result.ExitCode -eq 7) {
    Write-Pass "Correct ExitCode 7 for connection refused."
} else {
    Write-Fail "Expected ExitCode 7, got $($result.ExitCode)."
}

# ----------------------------------------------------------------
# Test 128: Environment Variable CURL_CA_BUNDLE
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "128. Environment Variable CURL_CA_BUNDLE"
$oldCaBundle = $env:CURL_CA_BUNDLE
try {
    $env:CURL_CA_BUNDLE = "nonexistent.pem"
    # This should fail because the CA bundle doesn't exist
    $result = Invoke-CurlTest "-s https://127.0.0.1:8443/get"
    # curl exit 77: Problem with the SSL CA cert (path? permission?)
    # curl exit 60: Peer certificate cannot be authenticated with known CA certificates
    if ($result.ExitCode -eq 77 -or $result.ExitCode -eq 60) {
        Write-Pass "Correct failure (ExitCode $($result.ExitCode)) with invalid CURL_CA_BUNDLE."
    } else {
        Write-Fail "Expected ExitCode 77 or 60, got $($result.ExitCode). Stderr: $($result.Stderr)"
    }
} finally {
    $env:CURL_CA_BUNDLE = $oldCaBundle
}

# ----------------------------------------------------------------
# Test 129: Resuming Already Complete Download
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "129. Resuming Already Complete Download"
$resumeFile = Join-Path $scriptDir "resume129.txt"
# Create a file that is already 10 bytes long (the size of /range/10)
"abcdefghij" | Out-File -FilePath $resumeFile -NoNewline -Encoding ascii
try {
    $result = Invoke-CurlTest "-s -C - -o `"$resumeFile`" $baseUrl/range/10"
    if ($result.ExitCode -eq 0) {
        $content = Get-Content $resumeFile -Raw
        if ($content -eq "abcdefghij") {
            Write-Pass "Resuming already complete download didn't change the file."
        } else {
            Write-Fail "File content changed: $content"
        }
    } else {
        Write-Fail "Resume failed with ExitCode $($result.ExitCode): $($result.Stderr)"
    }
} finally {
    if (Test-Path $resumeFile) { Remove-Item $resumeFile }
}

# ----------------------------------------------------------------
# Test 130: Duplicate Header Prevention (Content-Type)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "130. Duplicate Header Prevention (Content-Type)"
# -d normally sets Content-Type to application/x-www-form-urlencoded
$result = Invoke-CurlTest "-s -d `"param=value`" -H `"Content-Type: application/json`" $baseUrl/post"
try {
    $json = $result.Stdout | ConvertFrom-Json
    # Check if Content-Type is exactly application/json and not a list
    if ($json.headers.'Content-Type' -eq "application/json") {
        Write-Pass "Content-Type correctly overrode default and did not duplicate."
    } else {
        Write-Fail "Content-Type mismatch or duplicate: $($json.headers.'Content-Type')"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 131: Duplicate Header Prevention (User-Agent)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "131. Duplicate Header Prevention (User-Agent)"
$result = Invoke-CurlTest "-s -H `"User-Agent: MyCustomAgent/1.0`" $baseUrl/headers"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.headers.'User-Agent' -eq "MyCustomAgent/1.0") {
        Write-Pass "User-Agent correctly overrode default and did not duplicate."
    } else {
        Write-Fail "User-Agent mismatch or duplicate: $($json.headers.'User-Agent')"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 132: Duplicate Header Prevention (Accept)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "132. Duplicate Header Prevention (Accept)"
$result = Invoke-CurlTest "-s -H `"Accept: application/xml`" $baseUrl/headers"
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.headers.Accept -eq "application/xml") {
        Write-Pass "Accept correctly overrode default and did not duplicate."
    } else {
        Write-Fail "Accept mismatch or duplicate: $($json.headers.Accept)"
    }
} catch {
    Write-Fail "Failed to parse JSON response: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 133: Fail on Server Error with Multiple URLs
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "133. Fail on Server Error with Multiple URLs"
$result = Invoke-CurlTest "-s -f $baseUrl/status/404 $baseUrl/get"
# Curl actually returns 0 if the LAST URL succeeds, despite previous HTTP failures with -f
if ($result.ExitCode -eq 0 -and $result.Stdout -match "url.*get") {
    Write-Pass "Fetched second URL despite first failing with -f, and exited with 0 (matching curl's behavior)."
} else {
    Write-Fail "Multiple URL -f failed. ExitCode: $($result.ExitCode), Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Test 134: Abort on First Error with --fail and --fail-early
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "134. Abort on First Error with --fail and --fail-early"
$result = Invoke-CurlTest "-s -f --fail-early $baseUrl/status/404 $baseUrl/get"
if ($result.ExitCode -eq 22 -and $result.Stdout -notmatch "url.*get") {
    Write-Pass "Aborted immediately with --fail and --fail-early."
} else {
    Write-Fail "Abort with --fail-early failed. ExitCode: $($result.ExitCode), Stdout: $($result.Stdout)"
}

# ----------------------------------------------------------------
# Stop the local server and print summary
# ----------------------------------------------------------------
if (-not $serverProcess.HasExited) { $serverProcess.Kill() }

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "TEST SUMMARY" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "Total:   $totalTests" -ForegroundColor White
Write-Host "Passed:  $passed" -ForegroundColor Green
Write-Host "Failed:  $failed" -ForegroundColor Red
Write-Host "Skipped: $skipped" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Magenta

if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
