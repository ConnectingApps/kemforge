package main

import (
	"context"
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

	opts := ParseArgs(args)
	client, jar := BuildClient(opts)

	if opts.Parallel {
		var wg sync.WaitGroup
		for _, targetURL := range opts.TargetURLs {
			wg.Go(func() {
				executeRequest(opts, client, jar, targetURL)
			})
		}
		wg.Wait()
	} else {
		for _, targetURL := range opts.TargetURLs {
			executeRequest(opts, client, jar, targetURL)
		}
	}
}

func executeRequest(opts Options, client *http.Client, jar *simpleCookieJar, targetURL string) {
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

	// Verbose: print response headers
	if opts.Verbose {
		LogVerboseResponse(resp)
	}

	// Save cookies if -c specified
	if opts.CookieJar != "" && jar != nil {
		saveCookiesFromJar(jar, opts.CookieJar)
	}

	WriteResponse(resp, req, opts)
}
