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
	var proxyURL *url.URL
	if opts.ProxyURL != "" {
		pU, err := url.Parse(opts.ProxyURL)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: invalid proxy URL: %v\n", err)
			os.Exit(1)
		}
		proxyURL = pU
		if opts.ProxyUser != "" {
			parts := strings.SplitN(opts.ProxyUser, ":", 2)
			if len(parts) == 2 {
				proxyURL.User = url.UserPassword(parts[0], parts[1])
			} else {
				proxyURL.User = url.User(opts.ProxyUser)
			}
		}
	} else if allProxy := os.Getenv("ALL_PROXY"); allProxy != "" {
		if pU, err := url.Parse(allProxy); err == nil {
			proxyURL = pU
		}
	}

	if proxyURL != nil || opts.NoProxy != "" {
		transport.Proxy = func(req *http.Request) (*url.URL, error) {
			// Get noProxy list
			noProxy := opts.NoProxy
			if noProxy == "" {
				noProxy = os.Getenv("NO_PROXY")
				if noProxy == "" {
					noProxy = os.Getenv("no_proxy")
				}
			}

			// Check if host is in noProxy
			host := req.URL.Hostname()
			for _, p := range strings.Split(noProxy, ",") {
				p = strings.TrimSpace(p)
				if p == "" {
					continue
				}
				if p == "*" || host == p || strings.HasSuffix(host, "."+p) {
					return nil, nil
				}
			}

			// If we have a specific proxy, return it
			if proxyURL != nil {
				return proxyURL, nil
			}

			// Otherwise fall back to environment (but we already checked NO_PROXY)
			return http.ProxyFromEnvironment(req)
		}
	} else {
		transport.Proxy = http.ProxyFromEnvironment
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
		if opts.UnixSocket != "" {
			return dialer.DialContext(ctx, "unix", opts.UnixSocket)
		}
		if opts.IPv4 {
			network = "tcp4"
		} else if opts.IPv6 {
			network = "tcp6"
		}
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

	// Set client certificates
	if opts.CertFile != "" && opts.KeyFile != "" {
		cert, err := tls.LoadX509KeyPair(opts.CertFile, opts.KeyFile)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: failed to load client cert/key: %v\n", err)
		} else {
			transport.TLSClientConfig.Certificates = []tls.Certificate{cert}
		}
	}

	// Use a cookie jar when saving cookies with -c or loading with -b
	var jar *simpleCookieJar
	if opts.CookieJar != "" || opts.CookieEnable {
		jar = &simpleCookieJar{entries: make(map[string]map[string]*http.Cookie)}
		client.Jar = jar
	}

	return client, jar
}
