package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	allOpts := ParseArgs(args)
	var globalExitCode atomic.Int32

	for _, opts := range allOpts {
		if opts.ShowHelp {
			fmt.Println("Usage: kemforge [options] <url>")
			fmt.Println("Options:")
			fmt.Println("  -o <file>          Write output to <file>")
			fmt.Println("  -O                 Use the remote file name for output")
			fmt.Println("  -H <header>        Pass custom header(s) to server")
			fmt.Println("  -d <data>          HTTP POST data")
			fmt.Println("  --data-raw <data>  HTTP POST data (no @ support)")
			fmt.Println("  -v, --verbose      Make the operation more talkative")
			fmt.Println("  -i, --include      Include protocol response headers in the output")
			fmt.Println("  -I, --head         Show document info only")
			fmt.Println("  -L, --location     Follow redirects")
			fmt.Println("  -k, --insecure     Allow insecure server connections when using SSL")
			fmt.Println("  -s, --silent       Silent mode")
			fmt.Println("  -u <user:pass>     Server user and password")
			fmt.Println("  -x <proxy>         Use proxy on given port")
			fmt.Println("  -X <method>        Specify request method to use")
			fmt.Println("  -A <agent>         Send User-Agent <agent> to server")
			fmt.Println("  -e <referer>       Referrer URL")
			fmt.Println("  -f, --fail         Fail silently (no output at all) on HTTP errors")
			fmt.Println("  -Z, --parallel     Perform transfers in parallel")
			fmt.Println("  -b, --cookie <data> Send cookies from string/file")
			fmt.Println("  -c, --cookie-jar <file> Write cookies to <file> after operation")
			fmt.Println("  -T, --upload-file <file> Transfer <file> to REMOTE")
			fmt.Println("  -C, --continue-at <offset> Resumed transfer offset")
			fmt.Println("  -G, --get          Put the post data in the URL and use GET")
			fmt.Println("  -r, --range <range> Retrieve only the bytes within RANGE")
			fmt.Println("  -m, --max-time <seconds> Maximum time allowed for the transfer")
			fmt.Println("  --connect-timeout <seconds> Maximum time allowed for connection")
			fmt.Println("  --limit-rate <speed> Limit transfer speed to SPEED")
			fmt.Println("  --compressed       Request compressed response")
			fmt.Println("  --retry <num>      Retry request on transient errors")
			fmt.Println("  --retry-delay <s>  Wait <seconds> between retries")
			fmt.Println("  --retry-connrefused Retry on connection refused")
			fmt.Println("  --retry-all-errors  Retry on all errors")
			fmt.Println("  --fail-early       Fail on first transfer error, don't continue")
			fmt.Println("  --resolve <host:port:address> Resolve the host+port to this address")
			fmt.Println("  --json <data>      HTTP POST JSON data")
			fmt.Println("  --cacert <file>    CA certificate to verify peer against")
			fmt.Println("  --pinnedpubkey <hashes/file> FILE/HASHES Public key to verify peer against")
			fmt.Println("  --help             This help text")
			fmt.Println("  --version          Show version number and exit")
			continue
		}

		if opts.ShowVersion {
			fmt.Println("kemforge (curl-compatible) version 1.0.0")
			continue
		}

		client, jar := BuildClient(opts)

		if opts.Parallel {
			var wg sync.WaitGroup
			for i, targetURL := range opts.TargetURLs {
				i, targetURL := i, targetURL
				wg.Go(func() {
					// Each request might have its own output file if multiple -o were specified
					currentOpts := opts
					if i < len(opts.OutputFiles) {
						currentOpts.OutputFile = opts.OutputFiles[i]
					} else if len(opts.OutputFiles) > 0 {
						if i >= len(opts.OutputFiles) {
							currentOpts.OutputFile = ""
						}
					}
					exitCode := executeRequest(currentOpts, client, jar, targetURL)
					if exitCode != 0 {
						globalExitCode.Store(int32(exitCode))
						if opts.FailEarly {
							os.Exit(exitCode)
						}
					}
				})
			}
			wg.Wait()
		} else {
			var lastExitCode int
			for i, targetURL := range opts.TargetURLs {
				currentOpts := opts
				if i < len(opts.OutputFiles) {
					currentOpts.OutputFile = opts.OutputFiles[i]
				} else if len(opts.OutputFiles) > 0 {
					currentOpts.OutputFile = ""
				}
				lastExitCode = executeRequest(currentOpts, client, jar, targetURL)
				if lastExitCode != 0 && opts.FailEarly {
					os.Exit(lastExitCode)
				}
			}
			globalExitCode.Store(int32(lastExitCode))
		}
	}
	os.Exit(int(globalExitCode.Load()))
}

func executeRequest(opts Options, client *http.Client, jar *simpleCookieJar, targetURL string) int {
	startTime := time.Now()
	req := NewHTTPRequest(opts, targetURL)

	// Load cookies from file into jar
	if opts.CookieFile != "" && jar != nil {
		loadCookiesIntoJar(jar, opts.CookieFile, req.URL)
	}

	// Set max time via context
	var cancel context.CancelFunc
	ctx := context.Background()
	if opts.MaxTime > 0 {
		ctx, cancel = context.WithTimeout(ctx, time.Duration(opts.MaxTime*float64(time.Second)))
		defer cancel()
		req = req.WithContext(ctx)
	}

	// Verbose: print request info
	if opts.Verbose {
		LogVerboseRequest(req, req.Method)
	}

	// Execute request with retry logic
	var resp *http.Response
	var err error
	attempts := 0

	for {
		resp, err = client.Do(req)
		if err == nil {
			// Check for retry on 5xx, 408, 429 or all errors (>= 400) if --retry-all-errors
			isTransient := (resp.StatusCode >= 500) || (resp.StatusCode == 408) || (resp.StatusCode == 429)
			shouldRetry := isTransient || (opts.RetryAllErrors && resp.StatusCode >= 400)
			if opts.RetryCount > 0 && attempts < opts.RetryCount && shouldRetry {
				attempts++
				if !opts.Silent {
					_, _ = fmt.Fprintf(os.Stderr, "Retry attempt %d/%d - Failing with %d\n", attempts, opts.RetryCount, resp.StatusCode)
				}
				_ = resp.Body.Close()
				delay := time.Duration(1 * time.Second)
				if opts.RetryDelay > 0 {
					delay = time.Duration(opts.RetryDelay * float64(time.Second))
				}
				time.Sleep(delay)
				continue
			}
			break
		}

		// Check for retry on network errors
		isConnRefused := strings.Contains(err.Error(), "connection refused") ||
			strings.Contains(err.Error(), "actively refused it")
		shouldRetry := opts.RetryAllErrors || (isConnRefused && opts.RetryConnRefused) || (!isConnRefused && opts.RetryCount > 0)

		if opts.RetryCount > 0 && attempts < opts.RetryCount && shouldRetry {
			attempts++
			delay := time.Duration(1 * time.Second)
			if opts.RetryDelay > 0 {
				delay = time.Duration(opts.RetryDelay * float64(time.Second))
			}
			time.Sleep(delay)
			continue
		}
		break
	}

	if err != nil {
		return HandleRequestError(err, req, ctx, opts)
	}
	defer func() { _ = resp.Body.Close() }()

	// Fail on server error
	if opts.FailOnError && resp.StatusCode >= 400 {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (22) The requested URL returned error: %d\n", resp.StatusCode)
		}
		return 22
	}

	// Verbose: print response headers
	if opts.Verbose {
		LogVerboseResponse(resp)
	}

	// Print TLS information if available
	if resp.TLS != nil {
		tlsVersion := "unknown"
		switch resp.TLS.Version {
		case tls.VersionTLS10:
			tlsVersion = "1.0"
		case tls.VersionTLS11:
			tlsVersion = "1.1"
		case tls.VersionTLS12:
			tlsVersion = "1.2"
		case tls.VersionTLS13:
			tlsVersion = "1.3"
		}
		const colorYellow = "\033[33m"
		const colorGreen = "\033[32m"
		const colorRed = "\033[31m"
		const colorReset = "\033[0m"
		_, _ = fmt.Fprintf(os.Stderr, "%s* TLS DATA:\n", colorYellow)
		_, _ = fmt.Fprintf(os.Stderr, "* TlsVersion: %s\n", tlsVersion)
		_, _ = fmt.Fprintf(os.Stderr, "* Cipher:\t%s\n", tls.CipherSuiteName(resp.TLS.CipherSuite))
		keyExchangeGroup := resp.TLS.CurveID.String()
		_, _ = fmt.Fprintf(os.Stderr, "* KeyExchangeGroup: %s\n", keyExchangeGroup)
		if strings.Contains(strings.ToUpper(keyExchangeGroup), "MLKEM") {
			_, _ = fmt.Fprintf(os.Stderr, "%s* This server supports post quantum cryptography so the server has protection against quantum attacks.%s\n", colorGreen, colorReset)
		} else {
			_, _ = fmt.Fprintf(os.Stderr, "%s* This server is not protected against quantum attacks as the key exchange group does not contain MLKEM.%s\n", colorRed, colorReset)
		}
		_, _ = fmt.Fprintf(os.Stderr, "%s* %s\n", colorYellow, colorReset)
	}

	// Save cookies if -c specified
	if opts.CookieJar != "" && jar != nil {
		saveCookiesFromJar(jar, opts.CookieJar)
	}

	WriteResponse(resp, req, opts, startTime)
	return 0
}
