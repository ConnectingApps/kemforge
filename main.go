package main

import (
	"compress/gzip"
	"compress/zlib"
	"context"
	"crypto/tls"
	"encoding/base64"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/url"
	"os"
	"path"
	"strings"
	"sync"
	"time"
)

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	// Parse flags
	var (
		silent        bool
		showErrors    bool
		verbose       bool
		headReq       bool
		includeHdr    bool
		followRedirs  bool
		insecure      bool
		compressed    bool
		getMode       bool // -G: append data as query params
		remoteOut     bool // -O
		method        string
		userAgent     string
		outputFile    string
		writeOut      string
		cookieJar     string // -c
		cookieFile    string // -b
		basicAuth     string // -u user:pass
		proxyURL      string // -x
		connectTmout  float64
		maxTime       float64
		rangeHeader   string // -r
		headers       []string
		dataArgs      []string // -d
		formArgs      []string // -F
		urlEncodeArgs []string // --data-urlencode
		targetURL     string
	)

	userAgent = "kemforge/1.0"

	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-s":
			silent = true
		case a == "-S":
			showErrors = true
		case a == "-sS" || a == "-Ss":
			silent = true
			showErrors = true
		case a == "-v":
			verbose = true
		case a == "-I":
			headReq = true
		case a == "-i":
			includeHdr = true
		case a == "-L":
			followRedirs = true
		case a == "-k" || a == "--insecure":
			insecure = true
		case a == "--compressed":
			compressed = true
		case a == "-G":
			getMode = true
		case a == "-O":
			remoteOut = true
		case a == "-X":
			i++
			if i < len(args) {
				method = args[i]
			}
		case a == "-A":
			i++
			if i < len(args) {
				userAgent = args[i]
			}
		case a == "-H":
			i++
			if i < len(args) {
				headers = append(headers, args[i])
			}
		case a == "-o":
			i++
			if i < len(args) {
				outputFile = args[i]
			}
		case a == "-w":
			i++
			if i < len(args) {
				writeOut = args[i]
			}
		case a == "-c":
			i++
			if i < len(args) {
				cookieJar = args[i]
			}
		case a == "-b":
			i++
			if i < len(args) {
				cookieFile = args[i]
			}
		case a == "-u":
			i++
			if i < len(args) {
				basicAuth = args[i]
			}
		case a == "-x":
			i++
			if i < len(args) {
				proxyURL = args[i]
			}
		case a == "-d":
			i++
			if i < len(args) {
				dataArgs = append(dataArgs, args[i])
			}
		case a == "-F":
			i++
			if i < len(args) {
				formArgs = append(formArgs, args[i])
			}
		case a == "--data-urlencode":
			i++
			if i < len(args) {
				urlEncodeArgs = append(urlEncodeArgs, args[i])
			}
		case a == "--connect-timeout":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%f", &connectTmout)
			}
		case a == "--max-time" || a == "-m":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%f", &maxTime)
			}
		case a == "-r" || a == "--range":
			i++
			if i < len(args) {
				rangeHeader = args[i]
			}
		case strings.HasPrefix(a, "-"):
			// Unknown flag, ignore
		default:
			targetURL = a
		}
	}

	if targetURL == "" {
		fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	// Ensure URL has scheme
	if !strings.Contains(targetURL, "://") {
		targetURL = "http://" + targetURL
	}

	// Handle -G (GET with data as query params)
	if getMode && len(urlEncodeArgs) > 0 {
		u, err := url.Parse(targetURL)
		if err != nil {
			fmt.Fprintf(os.Stderr, "kemforge: URL parse error: %v\n", err)
			os.Exit(1)
		}
		q := u.Query()
		for _, arg := range urlEncodeArgs {
			parts := strings.SplitN(arg, "=", 2)
			if len(parts) == 2 {
				q.Set(parts[0], parts[1])
			} else {
				q.Set(arg, "")
			}
		}
		u.RawQuery = q.Encode()
		targetURL = u.String()
	}

	// Determine method
	if method == "" {
		if headReq {
			method = "HEAD"
		} else if len(dataArgs) > 0 || len(formArgs) > 0 {
			method = "POST"
		} else {
			method = "GET"
		}
	}

	// Build request body
	var body io.Reader
	var contentType string

	if len(formArgs) > 0 {
		// Multipart form
		var buf strings.Builder
		w := multipart.NewWriter(&buf)
		for _, f := range formArgs {
			parts := strings.SplitN(f, "=", 2)
			if len(parts) != 2 {
				continue
			}
			name := parts[0]
			val := parts[1]
			if strings.HasPrefix(val, "@") {
				// File upload
				filePath := val[1:]
				data, err := os.ReadFile(filePath)
				if err != nil {
					fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", filePath, err)
					os.Exit(1)
				}
				pw, _ := w.CreateFormFile(name, path.Base(filePath))
				_, _ = pw.Write(data)
			} else {
				pw, _ := w.CreateFormField(name)
				_, _ = pw.Write([]byte(val))
			}
		}
		_ = w.Close()
		contentType = w.FormDataContentType()
		body = strings.NewReader(buf.String())
	} else if len(dataArgs) > 0 {
		// Check for @file syntax
		var allData []string
		for _, d := range dataArgs {
			if strings.HasPrefix(d, "@") {
				filePath := d[1:]
				data, err := os.ReadFile(filePath)
				if err != nil {
					fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", filePath, err)
					os.Exit(1)
				}
				allData = append(allData, string(data))
			} else {
				allData = append(allData, d)
			}
		}
		combined := strings.Join(allData, "&")
		body = strings.NewReader(combined)
		// Default content type for -d
		contentType = "application/x-www-form-urlencoded"
	}

	// Override content type if user set it via -H
	for _, h := range headers {
		parts := strings.SplitN(h, ":", 2)
		if len(parts) == 2 && strings.EqualFold(strings.TrimSpace(parts[0]), "content-type") {
			contentType = strings.TrimSpace(parts[1])
		}
	}

	// Build HTTP request
	req, err := http.NewRequest(method, targetURL, body)
	if err != nil {
		fmt.Fprintf(os.Stderr, "kemforge: %v\n", err)
		os.Exit(1)
	}

	// Set user agent
	req.Header.Set("User-Agent", userAgent)

	// Set Accept
	req.Header.Set("Accept", "*/*")

	// Set content type
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	// Set custom headers
	for _, h := range headers {
		parts := strings.SplitN(h, ":", 2)
		if len(parts) == 2 {
			req.Header.Set(strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1]))
		}
	}

	// Set basic auth
	if basicAuth != "" {
		parts := strings.SplitN(basicAuth, ":", 2)
		if len(parts) == 2 {
			req.Header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(basicAuth)))
		}
	}

	// Set range header
	if rangeHeader != "" {
		req.Header.Set("Range", "bytes="+rangeHeader)
	}

	// Set compressed header
	if compressed {
		req.Header.Set("Accept-Encoding", "gzip, deflate")
	}

	// Build transport and client
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: insecure,
		},
	}

	// Set proxy
	if proxyURL != "" {
		proxyU, err := url.Parse(proxyURL)
		if err != nil {
			fmt.Fprintf(os.Stderr, "kemforge: invalid proxy URL: %v\n", err)
			os.Exit(1)
		}
		transport.Proxy = http.ProxyURL(proxyU)
	}

	// Set connect timeout via custom dialer
	if connectTmout > 0 {
		transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			d := net.Dialer{Timeout: time.Duration(connectTmout * float64(time.Second))}
			return d.DialContext(ctx, network, addr)
		}
	}

	// Build client
	client := &http.Client{
		Transport: transport,
	}

	// Follow redirects or not
	var jar *simpleCookieJar
	if !followRedirs {
		client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		}
	}

	// Use a cookie jar when saving cookies with -c (needed for redirects)
	if cookieJar != "" || cookieFile != "" {
		jar = &simpleCookieJar{entries: make(map[string]map[string]*http.Cookie)}
		client.Jar = jar
	}

	// Load cookies from file into jar
	if cookieFile != "" && jar != nil {
		loadCookiesIntoJar(jar, cookieFile, req.URL)
	}

	// Set max time via context
	var cancel context.CancelFunc
	ctx := req.Context()
	if maxTime > 0 {
		ctx, cancel = context.WithTimeout(ctx, time.Duration(maxTime*float64(time.Second)))
		defer cancel()
		req = req.WithContext(ctx)
	}

	// Verbose: print request info
	if verbose {
		fmt.Fprintf(os.Stderr, "> %s %s HTTP/1.1\r\n", method, req.URL.RequestURI())
		fmt.Fprintf(os.Stderr, "> Host: %s\r\n", req.URL.Host)
		for k, vals := range req.Header {
			for _, v := range vals {
				fmt.Fprintf(os.Stderr, "> %s: %s\r\n", k, v)
			}
		}
		fmt.Fprintf(os.Stderr, "> \r\n")
	}

	// Execute request
	resp, err := client.Do(req)
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			if !silent || showErrors {
				fmt.Fprintf(os.Stderr, "kemforge: (28) Operation timed out\n")
			}
			os.Exit(28)
		}
		// Check for DNS errors
		if dnsErr, ok := err.(*net.OpError); ok {
			if _, ok2 := dnsErr.Err.(*net.DNSError); ok2 {
				if !silent || showErrors {
					fmt.Fprintf(os.Stderr, "kemforge: (6) Could not resolve host: %s\n", req.URL.Hostname())
				}
				os.Exit(6)
			}
		}
		// Check for URL error wrapping DNS
		if urlErr, ok := err.(*url.Error); ok {
			if opErr, ok2 := urlErr.Err.(*net.OpError); ok2 {
				if _, ok3 := opErr.Err.(*net.DNSError); ok3 {
					if !silent || showErrors {
						fmt.Fprintf(os.Stderr, "kemforge: (6) Could not resolve host: %s\n", req.URL.Hostname())
					}
					os.Exit(6)
				}
				// Connect timeout
				if opErr.Timeout() {
					if !silent || showErrors {
						fmt.Fprintf(os.Stderr, "kemforge: (28) Connection timed out\n")
					}
					os.Exit(28)
				}
			}
			// General timeout
			if urlErr.Timeout() {
				if !silent || showErrors {
					fmt.Fprintf(os.Stderr, "kemforge: (28) Operation timed out\n")
				}
				os.Exit(28)
			}
		}
		if !silent || showErrors {
			fmt.Fprintf(os.Stderr, "kemforge: %v\n", err)
		}
		os.Exit(1)
	}
	defer func() { _ = resp.Body.Close() }()

	// Verbose: print response headers
	if verbose {
		fmt.Fprintf(os.Stderr, "< HTTP/%d.%d %s\r\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
		for k, vals := range resp.Header {
			for _, v := range vals {
				fmt.Fprintf(os.Stderr, "< %s: %s\r\n", k, v)
			}
		}
		fmt.Fprintf(os.Stderr, "< \r\n")
	}

	// Save cookies if -c specified
	if cookieJar != "" && jar != nil {
		saveCookiesFromJar(jar, cookieJar)
	}

	// Determine output writer
	var output io.Writer = os.Stdout
	if outputFile != "" {
		if outputFile == "/dev/null" || outputFile == "NUL" {
			output = io.Discard
		} else {
			f, err := os.Create(outputFile)
			if err != nil {
				fmt.Fprintf(os.Stderr, "kemforge: can't open '%s': %v\n", outputFile, err)
				os.Exit(1)
			}
			defer func() { _ = f.Close() }()
			output = f
		}
	}

	// Remote filename output -O
	if remoteOut {
		remoteName := path.Base(req.URL.Path)
		if remoteName == "" || remoteName == "/" || remoteName == "." {
			remoteName = "index.html"
		}
		f, err := os.Create(remoteName)
		if err != nil {
			fmt.Fprintf(os.Stderr, "kemforge: can't create '%s': %v\n", remoteName, err)
			os.Exit(1)
		}
		defer func() { _ = f.Close() }()
		output = f
	}

	// Head request or -I: print headers
	if headReq || (method == "HEAD") {
		_, _ = fmt.Fprintf(output, "HTTP/%d.%d %s\r\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
		for k, vals := range resp.Header {
			for _, v := range vals {
				_, _ = fmt.Fprintf(output, "%s: %s\r\n", k, v)
			}
		}
		_, _ = fmt.Fprintf(output, "\r\n")
	} else {
		// Include headers if -i
		if includeHdr {
			_, _ = fmt.Fprintf(output, "HTTP/%d.%d %s\r\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
			for k, vals := range resp.Header {
				for _, v := range vals {
					_, _ = fmt.Fprintf(output, "%s: %s\r\n", k, v)
				}
			}
			_, _ = fmt.Fprintf(output, "\r\n")
		}

		// Read body, handle decompression if --compressed
		var bodyReader io.Reader = resp.Body
		if compressed {
			switch resp.Header.Get("Content-Encoding") {
			case "gzip":
				gr, err := gzip.NewReader(resp.Body)
				if err == nil {
					defer func() { _ = gr.Close() }()
					bodyReader = gr
				}
			case "deflate":
				zr, err := zlib.NewReader(resp.Body)
				if err == nil {
					defer func() { _ = zr.Close() }()
					bodyReader = zr
				}
			}
		}

		_, _ = io.Copy(output, bodyReader)
	}

	// Write-out format
	if writeOut != "" {
		wout := writeOut
		wout = strings.ReplaceAll(wout, "%{http_code}", fmt.Sprintf("%d", resp.StatusCode))
		wout = strings.ReplaceAll(wout, "\\n", "\n")
		_, _ = fmt.Fprint(os.Stdout, wout)
	}
}

// simpleCookieJar implements http.CookieJar to track cookies across redirects.
type simpleCookieJar struct {
	mu      sync.Mutex
	entries map[string]map[string]*http.Cookie // host -> name -> cookie
}

func (j *simpleCookieJar) SetCookies(u *url.URL, cookies []*http.Cookie) {
	j.mu.Lock()
	defer j.mu.Unlock()
	host := u.Hostname()
	if j.entries[host] == nil {
		j.entries[host] = make(map[string]*http.Cookie)
	}
	for _, c := range cookies {
		j.entries[host][c.Name] = c
	}
}

func (j *simpleCookieJar) Cookies(u *url.URL) []*http.Cookie {
	j.mu.Lock()
	defer j.mu.Unlock()
	host := u.Hostname()
	var result []*http.Cookie
	for _, c := range j.entries[host] {
		result = append(result, c)
	}
	return result
}

func (j *simpleCookieJar) AllCookies() []*http.Cookie {
	j.mu.Lock()
	defer j.mu.Unlock()
	var result []*http.Cookie
	for _, m := range j.entries {
		for _, c := range m {
			result = append(result, c)
		}
	}
	return result
}

// loadCookiesIntoJar reads a Netscape-format cookie file and loads cookies into the jar.
func loadCookiesIntoJar(jar *simpleCookieJar, filename string, reqURL *url.URL) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) >= 7 {
			c := &http.Cookie{
				Name:  fields[5],
				Value: fields[6],
			}
			host := fields[0]
			u := &url.URL{Scheme: reqURL.Scheme, Host: host}
			jar.SetCookies(u, []*http.Cookie{c})
		}
	}
}

// saveCookiesFromJar writes all cookies from the jar in Netscape cookie file format.
func saveCookiesFromJar(jar *simpleCookieJar, filename string) {
	f, err := os.Create(filename)
	if err != nil {
		return
	}
	defer func() { _ = f.Close() }()

	_, _ = fmt.Fprintln(f, "# Netscape HTTP Cookie File")
	jar.mu.Lock()
	defer jar.mu.Unlock()
	for host, cookies := range jar.entries {
		for _, c := range cookies {
			secure := "FALSE"
			if c.Secure {
				secure = "TRUE"
			}
			expires := "0"
			if !c.Expires.IsZero() {
				expires = fmt.Sprintf("%d", c.Expires.Unix())
			}
			cpath := "/"
			if c.Path != "" {
				cpath = c.Path
			}
			_, _ = fmt.Fprintf(f, "%s\tTRUE\t%s\t%s\t%s\t%s\t%s\n", host, cpath, secure, expires, c.Name, c.Value)
		}
	}
}
