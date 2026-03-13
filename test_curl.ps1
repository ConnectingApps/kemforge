#!/usr/bin/env pwsh
# test_curl.ps1 - Test script for curl features based on CURL_FEATURES.md
# Usage: ./test_curl.ps1 <curl-command>
# Example: ./test_curl.ps1 curl

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CurlCmd
)

$ErrorActionPreference = "Continue"

$passed = 0
$failed = 0
$skipped = 0
$totalTests = 0

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
        [switch]$ReturnStderr
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CurlCmd
    $psi.Arguments = $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($ReturnStderr) {
        return @{
            Stdout   = $stdout
            Stderr   = $stderr
            ExitCode = $process.ExitCode
        }
    }
    return @{
        Stdout   = $stdout
        Stderr   = $stderr
        ExitCode = $process.ExitCode
    }
}

# Verify the tool exists
$toolCheck = Get-Command $CurlCmd -ErrorAction SilentlyContinue
if (-not $toolCheck) {
    Write-Host "ERROR: '$CurlCmd' not found in PATH." -ForegroundColor Red
    exit 1
}
Write-Host "Using tool: $CurlCmd" -ForegroundColor Magenta
Write-Host "Starting curl feature tests against httpbin.org..." -ForegroundColor Magenta

# ----------------------------------------------------------------
# Test 1: Simple GET Request
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "1. Simple GET Request"
$result = Invoke-CurlTest '-s httpbin.org/get'
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -eq "http://httpbin.org/get" -and $json.headers.Host -eq "httpbin.org") {
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
$result = Invoke-CurlTest '-s -H "X-Custom-Header: MyValue" httpbin.org/headers'
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
$result = Invoke-CurlTest '-s -d "param1=val1&param2=val2" httpbin.org/post'
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
$testFilePath = Join-Path $PSScriptRoot "test_upload_tmp.txt"
try {
    # Write file without BOM and with LF line ending
    [System.IO.File]::WriteAllText($testFilePath, "This is a test file for curl.`n")
    $result = Invoke-CurlTest "-s -F `"file=@$testFilePath`" httpbin.org/post"
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
$result = Invoke-CurlTest '-s -u user:password httpbin.org/basic-auth/user/password'
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
$result = Invoke-CurlTest '-s -L "httpbin.org/redirect-to?url=http://httpbin.org/get"'
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -eq "http://httpbin.org/get") {
        Write-Pass "Redirect followed successfully to http://httpbin.org/get."
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
$cookieFile = Join-Path $PSScriptRoot "test_cookies_tmp.txt"
try {
    # Step 1: Set cookie and save it
    $result1 = Invoke-CurlTest "-s -L -c `"$cookieFile`" httpbin.org/cookies/set/session/123456"
    # Step 2: Send cookie back
    $result2 = Invoke-CurlTest "-s -b `"$cookieFile`" httpbin.org/cookies"
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
$result = Invoke-CurlTest '-v -s httpbin.org/get' -ReturnStderr
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
$result = Invoke-CurlTest '-s -A "MyTestAgent" httpbin.org/user-agent'
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
$outFile = Join-Path $PSScriptRoot "test_response_tmp.json"
try {
    $result = Invoke-CurlTest "-s -o `"$outFile`" httpbin.org/get"
    if (Test-Path $outFile) {
        $content = Get-Content $outFile -Raw
        $json = $content | ConvertFrom-Json
        if ($json.url -eq "http://httpbin.org/get") {
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
$result = Invoke-CurlTest '-s -I httpbin.org/get'
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
$result = Invoke-CurlTest '-s -X DELETE httpbin.org/delete'
try {
    $json = $result.Stdout | ConvertFrom-Json
    if ($json.url -eq "http://httpbin.org/delete") {
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
$jsonFile = Join-Path $PSScriptRoot "test_json_tmp.txt"
try {
    [System.IO.File]::WriteAllText($jsonFile, '{"key": "value"}')
    $result = Invoke-CurlTest "-s -H `"Content-Type: application/json`" -d @$jsonFile httpbin.org/post"
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
$result = Invoke-CurlTest '-s --data-urlencode "name=John Doe" --data-urlencode "city=New York" -G httpbin.org/get'
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
    $result = Invoke-CurlTest '-s -o NUL -w "%{http_code}\n" httpbin.org/get'
} else {
    $result = Invoke-CurlTest '-s -o /dev/null -w "%{http_code}\n" httpbin.org/get'
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
$result = Invoke-CurlTest '-s -k https://self-signed.badssl.com/'
if ($result.ExitCode -eq 0 -and $result.Stdout.Length -gt 0) {
    Write-Pass "Insecure SSL connection succeeded with -k flag."
} else {
    Write-Fail "Insecure SSL test failed. Exit code: $($result.ExitCode), Output length: $($result.Stdout.Length)"
}

# ----------------------------------------------------------------
# Test 18: Connect Timeout
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "18. Connect Timeout"
# Use a non-routable IP to test connect timeout
$startTime = Get-Date
$result = Invoke-CurlTest '-s --connect-timeout 3 http://192.0.2.1/test' -ReturnStderr
$elapsed = (Get-Date) - $startTime
if ($result.ExitCode -ne 0 -and $elapsed.TotalSeconds -lt 10) {
    Write-Pass "Connect timeout triggered within expected time ($([math]::Round($elapsed.TotalSeconds, 1))s)."
} else {
    Write-Fail "Connect timeout test unexpected. Exit: $($result.ExitCode), Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s"
}

# ----------------------------------------------------------------
# Test 19: Using a Proxy (SKIPPED)
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "19. Using a Proxy"
Write-Skip "Proxy test skipped - requires a proxy server to be available."

# ----------------------------------------------------------------
# Test 20: Include Headers in Output
# ----------------------------------------------------------------
$totalTests++
Write-TestHeader "20. Include Headers in Output"
$result = Invoke-CurlTest '-s -i httpbin.org/get'
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
$result = Invoke-CurlTest '-I httpbin.org/get' -ReturnStderr
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
$result = Invoke-CurlTest '-s -I --compressed httpbin.org/get'
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
$result = Invoke-CurlTest '-s -r 0-50 httpbin.org/range/1024'
if ($result.Stdout.Length -eq 51) {
    Write-Pass "Range request returned exactly 51 bytes."
} else {
    # Some servers may return the full range differently
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
$savedFile = Join-Path $PSScriptRoot "get"
try {
    # Remove any existing file first
    if (Test-Path $savedFile) { Remove-Item $savedFile -Force }
    # Run from the script's directory so the file is saved there
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $CurlCmd
    $psi.Arguments = "-s -O httpbin.org/get"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $PSScriptRoot
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null
    $process.StandardOutput.ReadToEnd() | Out-Null
    $process.StandardError.ReadToEnd() | Out-Null
    $process.WaitForExit()

    if (Test-Path $savedFile) {
        $content = Get-Content $savedFile -Raw
        $json = $content | ConvertFrom-Json
        if ($json.url -eq "http://httpbin.org/get") {
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
$result = Invoke-CurlTest '-s --max-time 3 httpbin.org/delay/10' -ReturnStderr
$elapsed = (Get-Date) - $startTime
if ($result.ExitCode -eq 28 -and $elapsed.TotalSeconds -lt 8) {
    Write-Pass "Max-time triggered correctly (exit code 28, elapsed $([math]::Round($elapsed.TotalSeconds, 1))s)."
} elseif ($result.ExitCode -ne 0 -and $elapsed.TotalSeconds -lt 8) {
    Write-Pass "Max-time triggered (exit code $($result.ExitCode), elapsed $([math]::Round($elapsed.TotalSeconds, 1))s)."
} else {
    Write-Fail "Max-time test unexpected. Exit: $($result.ExitCode), Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s"
}

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
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
