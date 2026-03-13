package main

import (
	"context"
	"fmt"
	"os"
	"time"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	opts := ParseArgs(args)
	req := NewHTTPRequest(opts)
	client, jar := BuildClient(opts)

	// Load cookies from file into jar
	if opts.CookieFile != "" && jar != nil {
		loadCookiesIntoJar(jar, opts.CookieFile, req.URL)
	}

	// Set max time via context
	var cancel context.CancelFunc
	ctx := req.Context()
	if opts.MaxTime > 0 {
		ctx, cancel = context.WithTimeout(ctx, time.Duration(opts.MaxTime*float64(time.Second)))
		defer cancel()
		req = req.WithContext(ctx)
	}

	// Verbose: print request info
	if opts.Verbose {
		LogVerboseRequest(req, req.Method)
	}

	// Execute request
	resp, err := client.Do(req)
	if err != nil {
		HandleRequestError(err, req, ctx, opts)
	}
	defer func() { _ = resp.Body.Close() }()

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
