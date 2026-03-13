package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"golang.org/x/net/http2"
)

// BuildClient creates an *http.Client with the appropriate transport,
// proxy, TLS, timeout, redirect, and cookie jar settings.
func BuildClient(opts Options) (*http.Client, *simpleCookieJar) {
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: opts.Insecure,
		},
	}

	// Enable HTTP/2 support on the custom transport unless --http1.1 is set
	if !opts.HTTP11 {
		if err := http2.ConfigureTransport(transport); err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: failed to configure HTTP/2: %v\n", err)
		}
	} else {
		transport.ForceAttemptHTTP2 = false
		transport.TLSNextProto = make(map[string]func(string, *tls.Conn) http.RoundTripper)
	}

	// Set proxy
	if opts.ProxyURL != "" {
		proxyU, err := url.Parse(opts.ProxyURL)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: invalid proxy URL: %v\n", err)
			os.Exit(1)
		}
		transport.Proxy = http.ProxyURL(proxyU)
	}

	// Set connect timeout via custom dialer
	dialer := &net.Dialer{
		Timeout: time.Duration(opts.ConnectTmout * float64(time.Second)),
	}

	// Set resolve overrides
	resolveMap := make(map[string]string)
	for _, r := range opts.ResolveArgs {
		parts := strings.SplitN(r, ":", 3)
		if len(parts) == 3 {
			hostPort := fmt.Sprintf("%s:%s", parts[0], parts[1])
			resolveMap[hostPort] = fmt.Sprintf("%s:%s", parts[2], parts[1])
		}
	}

	transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
		if target, ok := resolveMap[addr]; ok {
			addr = target
		}
		return dialer.DialContext(ctx, network, addr)
	}

	// Build client
	client := &http.Client{
		Transport: transport,
	}

	// Follow redirects or not
	if !opts.FollowRedirs {
		client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		}
	} else if opts.MaxRedirs > 0 {
		client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
			if len(via) >= opts.MaxRedirs {
				return fmt.Errorf("maximum (%d) redirects followed", opts.MaxRedirs)
			}
			return nil
		}
	}

	// Use a cookie jar when saving cookies with -c or loading with -b
	var jar *simpleCookieJar
	if opts.CookieJar != "" || opts.CookieFile != "" {
		jar = &simpleCookieJar{entries: make(map[string]map[string]*http.Cookie)}
		client.Jar = jar
	}

	return client, jar
}
