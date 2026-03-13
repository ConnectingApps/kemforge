package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"time"
)

// BuildClient creates an *http.Client with the appropriate transport,
// proxy, TLS, timeout, redirect, and cookie jar settings.
func BuildClient(opts Options) (*http.Client, *simpleCookieJar) {
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: opts.Insecure,
		},
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
	if opts.ConnectTmout > 0 {
		transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			d := net.Dialer{Timeout: time.Duration(opts.ConnectTmout * float64(time.Second))}
			return d.DialContext(ctx, network, addr)
		}
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
	}

	// Use a cookie jar when saving cookies with -c or loading with -b
	var jar *simpleCookieJar
	if opts.CookieJar != "" || opts.CookieFile != "" {
		jar = &simpleCookieJar{entries: make(map[string]map[string]*http.Cookie)}
		client.Jar = jar
	}

	return client, jar
}
