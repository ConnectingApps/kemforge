package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"syscall"
)

// HandleRequestError inspects the error from client.Do() and returns
// the appropriate curl-compatible exit code (6 for DNS, 28 for timeout, 7 for refused, etc).
func HandleRequestError(err error, req *http.Request, ctx context.Context, opts Options) int {
	if ctx.Err() == context.DeadlineExceeded {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (28) Operation timed out\n")
		}
		return 28
	}

	// Check for DNS errors
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (6) Could not resolve host: %s\n", req.URL.Hostname())
		}
		return 6
	}

	// Check for Connection Refused (platform-agnostic via syscall.ECONNREFUSED)
	if errors.Is(err, syscall.ECONNREFUSED) ||
		strings.Contains(err.Error(), "connection refused") ||
		strings.Contains(err.Error(), "actively refused it") {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (7) Failed to connect to %s port %s: Connection refused\n", req.URL.Hostname(), req.URL.Port())
		}
		return 7
	}

	// Check for Timeout (net.Error includes Timeout() method)
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (28) Connection or operation timed out\n")
		}
		return 28
	}

	if strings.Contains(err.Error(), "redirects followed") {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: %v\n", err)
		}
		return 47
	}

	// SSL/TLS errors (keep string checks for broader coverage of various TLS error types)
	if strings.Contains(strings.ToLower(err.Error()), "tls") || strings.Contains(strings.ToLower(err.Error()), "certificate") {
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (60) SSL certificate problem: %v\n", err)
		}
		return 60
	}

	if !opts.Silent || opts.ShowErrors {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: %v\n", err)
	}
	return 1
}
