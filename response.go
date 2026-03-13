package main

import (
	"compress/gzip"
	"compress/zlib"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"strings"
)

// LogVerboseRequest prints request details to stderr when -v is set.
func LogVerboseRequest(req *http.Request, method string) {
	_, _ = fmt.Fprintf(os.Stderr, "> %s %s HTTP/1.1\r\n", method, req.URL.RequestURI())
	_, _ = fmt.Fprintf(os.Stderr, "> Host: %s\r\n", req.URL.Host)
	for k, vals := range req.Header {
		for _, v := range vals {
			_, _ = fmt.Fprintf(os.Stderr, "> %s: %s\r\n", k, v)
		}
	}
	_, _ = fmt.Fprintf(os.Stderr, "> \r\n")
}

// LogVerboseResponse prints response headers to stderr when -v is set.
func LogVerboseResponse(resp *http.Response) {
	_, _ = fmt.Fprintf(os.Stderr, "< HTTP/%d.%d %s\r\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
	for k, vals := range resp.Header {
		for _, v := range vals {
			_, _ = fmt.Fprintf(os.Stderr, "< %s: %s\r\n", k, v)
		}
	}
	_, _ = fmt.Fprintf(os.Stderr, "< \r\n")
}

// WriteResponse handles all output: file creation (-o, -O), HEAD headers (-I),
// include headers (-i), body decompression (--compressed), and write-out (-w).
func WriteResponse(resp *http.Response, req *http.Request, opts Options) {
	// Determine output writer
	var output io.Writer = os.Stdout
	if opts.OutputFile != "" {
		if opts.OutputFile == "/dev/null" || opts.OutputFile == "NUL" {
			output = io.Discard
		} else {
			f, err := os.Create(opts.OutputFile)
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't open '%s': %v\n", opts.OutputFile, err)
				os.Exit(1)
			}
			defer func() { _ = f.Close() }()
			output = f
		}
	}

	// Remote filename output -O
	if opts.RemoteOut {
		remoteName := path.Base(req.URL.Path)
		if remoteName == "" || remoteName == "/" || remoteName == "." {
			remoteName = "index.html"
		}
		f, err := os.Create(remoteName)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't create '%s': %v\n", remoteName, err)
			os.Exit(1)
		}
		defer func() { _ = f.Close() }()
		output = f
	}

	// Head request or -I: print headers
	if opts.HeadReq || (opts.Method == "HEAD") {
		_, _ = fmt.Fprintf(output, "HTTP/%d.%d %s\r\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
		for k, vals := range resp.Header {
			for _, v := range vals {
				_, _ = fmt.Fprintf(output, "%s: %s\r\n", k, v)
			}
		}
		_, _ = fmt.Fprintf(output, "\r\n")
	} else {
		// Include headers if -i
		if opts.IncludeHdr {
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
		if opts.Compressed {
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
		_, _ = fmt.Fprintf(output, "TLS DATA:\n")
		_, _ = fmt.Fprintf(output, "TlsVersion: %s\n", tlsVersion)
		_, _ = fmt.Fprintf(output, "Cipher:\t%s\n", tls.CipherSuiteName(resp.TLS.CipherSuite))
		_, _ = fmt.Fprintf(output, "KeyExchangeGroup: %s\n", resp.TLS.CurveID.String())
		_, _ = fmt.Fprintf(output, "\n")
	}

	// Write-out format
	if opts.WriteOut != "" {
		wout := opts.WriteOut
		wout = strings.ReplaceAll(wout, "%{http_code}", fmt.Sprintf("%d", resp.StatusCode))
		wout = strings.ReplaceAll(wout, "\\n", "\n")
		_, _ = fmt.Fprint(os.Stdout, wout)
	}
}
