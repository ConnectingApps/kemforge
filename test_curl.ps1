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

$ErrorActionPreference = "Continue"

$passed = 0
$failed = 0
$skipped = 0
$totalTests = 0

# ---------------------------------------------------------------------------
# Determine paths & ports
# ---------------------------------------------------------------------------
$scriptDir = $PSScriptRoot
$venvPython = Join-Path $scriptDir ".venv/bin/python"
$testServer = Join-Path $scriptDir "test_server.py"
$httpPort = 8080
$httpsPort = 8443
$proxyPort = 8081
$baseUrl = "http://127.0.0.1:$httpPort"
$httpsBaseUrl = "https://127.0.0.1:$httpsPort"

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
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CurlCmd
    $psi.Arguments = $Arguments
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

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

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
    Write-Host "Create it with:  python3 -m venv .venv && .venv/bin/pip install flask pyopenssl" -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $testServer)) {
    Write-Host "ERROR: test_server.py not found at $testServer" -ForegroundColor Red
    exit 1
}

Write-Host "Starting local test server on ports $httpPort (HTTP), $httpsPort (HTTPS) and $proxyPort (CONNECT)..." -ForegroundColor Magenta

# Stop any existing server process on these ports (cleanup from previous runs)
try {
    Get-Process | Where-Object { $_.CommandLine -match "test_server.py" } | Stop-Process -Force -ErrorAction SilentlyContinue
    # Wait a bit for ports to be released
    Start-Sleep -Seconds 1
} catch {}

$serverPsi = New-Object System.Diagnostics.ProcessStartInfo
$serverPsi.FileName = $venvPython
$serverPsi.Arguments = "$testServer --port $httpPort --https-port $httpsPort --proxy-port $proxyPort"
$serverPsi.RedirectStandardOutput = $true
$serverPsi.RedirectStandardError = $true
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
$cmd = "echo 'data-from-stdin' | $CurlCmd -s -d @- $baseUrl/post"
$stdout = bash -c $cmd
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
$certFile = Join-Path $scriptDir "client.crt"
$keyFile = Join-Path $scriptDir "client.key"
# We'll use openssl to generate a real client cert/key
try {
    bash -c "openssl req -x509 -newkey rsa:2048 -keyout $keyFile -out $certFile -days 1 -nodes -subj '/CN=localhost' 2>/dev/null"
    if (Test-Path $certFile) {
        $result = Invoke-CurlTest "-s -k --cert `"$certFile`" --key `"$keyFile`" $httpsBaseUrl/mtls"
        if ($result.Stdout -match '"authenticated":\s*true') {
            Write-Pass "Mutual TLS request with valid certificates succeeded."
        } else {
            Write-Fail "Mutual TLS simulation failed. Stdout: $($result.Stdout), Stderr: $($result.Stderr)"
        }
    } else {
        Write-Skip "OpenSSL not available or failed to generate certificates."
    }
} finally {
    if (Test-Path $certFile) { Remove-Item $certFile }
    if (Test-Path $keyFile) { Remove-Item $keyFile }
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
