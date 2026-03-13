package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"
	"os"
	"sync"
	"time"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	allOpts := ParseArgs(args)

	for _, opts := range allOpts {
		if opts.ShowHelp {
			fmt.Println("Usage: kemforge [options] <url>")
			fmt.Println("Options:")
			fmt.Println("  -o <file>          Write output to <file>")
			fmt.Println("  -H <header>        Pass custom header(s) to server")
			fmt.Println("  -d <data>          HTTP POST data")
			fmt.Println("  --data-raw <data>  HTTP POST data (no @ support)")
			fmt.Println("  -v                 Make the operation more talkative")
			fmt.Println("  -i                 Include protocol response headers in the output")
			fmt.Println("  -L                 Follow redirects")
			fmt.Println("  -k                 Allow insecure server connections when using SSL")
			fmt.Println("  -s                 Silent mode")
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
					executeRequest(currentOpts, client, jar, targetURL)
				})
			}
			wg.Wait()
		} else {
			for i, targetURL := range opts.TargetURLs {
				currentOpts := opts
				if i < len(opts.OutputFiles) {
					currentOpts.OutputFile = opts.OutputFiles[i]
				} else if len(opts.OutputFiles) > 0 {
					currentOpts.OutputFile = ""
				}
				executeRequest(currentOpts, client, jar, targetURL)
			}
		}
	}
}

func executeRequest(opts Options, client *http.Client, jar *simpleCookieJar, targetURL string) {
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
			// Check for retry on 5xx
			if opts.RetryCount > 0 && attempts < opts.RetryCount && resp.StatusCode >= 500 {
				attempts++
				_, _ = fmt.Fprintf(os.Stderr, "Retry attempt %d/%d - Failing with %d\n", attempts, opts.RetryCount, resp.StatusCode)
				_ = resp.Body.Close()
				time.Sleep(1 * time.Second) // Simple backoff
				continue
			}
			break
		}

		// Check for retry on network errors if needed, but for now just 5xx as per test
		if opts.RetryCount > 0 && attempts < opts.RetryCount {
			attempts++
			time.Sleep(1 * time.Second)
			continue
		}
		break
	}

	if err != nil {
		HandleRequestError(err, req, ctx, opts)
	}
	defer func() { _ = resp.Body.Close() }()

	// Fail on server error
	if opts.FailOnError && resp.StatusCode >= 400 {
		os.Exit(22)
	}

	// Verbose: print response headers and TLS info
	if opts.Verbose {
		LogVerboseResponse(resp)
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
			_, _ = fmt.Fprintf(os.Stderr, "* TLS DATA:\n")
			_, _ = fmt.Fprintf(os.Stderr, "* TlsVersion: %s\n", tlsVersion)
			_, _ = fmt.Fprintf(os.Stderr, "* Cipher:\t%s\n", tls.CipherSuiteName(resp.TLS.CipherSuite))
			_, _ = fmt.Fprintf(os.Stderr, "* KeyExchangeGroup: %s\n", resp.TLS.CurveID.String())
			_, _ = fmt.Fprintf(os.Stderr, "* \n")
		}
	}

	// Save cookies if -c specified
	if opts.CookieJar != "" && jar != nil {
		saveCookiesFromJar(jar, opts.CookieJar)
	}

	WriteResponse(resp, req, opts, startTime)
}
