package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
)

// HandleRequestError inspects the error from client.Do() and exits
// with the appropriate curl-compatible exit code (6 for DNS, 28 for timeout, 1 for other).
func HandleRequestError(err error, req *http.Request, ctx context.Context, opts Options) {
	if ctx.Err() == context.DeadlineExceeded {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (28) Operation timed out\n")
		}
		os.Exit(28)
	}
	// Check for DNS errors
	if dnsErr, ok := err.(*net.OpError); ok {
		if _, ok2 := dnsErr.Err.(*net.DNSError); ok2 {
			if !opts.Silent || opts.ShowErrors {
				_, _ = fmt.Fprintf(os.Stderr, "kemforge: (6) Could not resolve host: %s\n", req.URL.Hostname())
			}
			os.Exit(6)
		}
	}
	// Check for URL error wrapping DNS
	if urlErr, ok := err.(*url.Error); ok {
		if opErr, ok2 := urlErr.Err.(*net.OpError); ok2 {
			if _, ok3 := opErr.Err.(*net.DNSError); ok3 {
				if !opts.Silent || opts.ShowErrors {
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: (6) Could not resolve host: %s\n", req.URL.Hostname())
				}
				os.Exit(6)
			}
			// Connect timeout
			if opErr.Timeout() {
				if !opts.Silent || opts.ShowErrors {
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: (28) Connection timed out\n")
				}
				os.Exit(28)
			}
		}
		// General timeout
		if urlErr.Timeout() {
			if !opts.Silent || opts.ShowErrors {
				_, _ = fmt.Fprintf(os.Stderr, "kemforge: (28) Operation timed out\n")
			}
			os.Exit(28)
		}
	}
	if !opts.Silent || opts.ShowErrors {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: %v\n", err)
	}
	os.Exit(1)
}
