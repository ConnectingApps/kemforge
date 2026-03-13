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
	"time"
)

// LogVerboseRequest prints request details to stderr when -v is set.
func LogVerboseRequest(req *http.Request, method string) {
	_, _ = fmt.Fprintf(os.Stderr, "> %s %s HTTP/1.1\r\n", method, req.URL.RequestURI())
	host := req.Host
	if host == "" {
		host = req.URL.Host
	}
	_, _ = fmt.Fprintf(os.Stderr, "> Host: %s\r\n", host)
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
func WriteResponse(resp *http.Response, req *http.Request, opts Options, startTime time.Time) {
	var sizeDownload int64
	// Dump headers if --dump-header specified
	if opts.DumpHeader != "" {
		df, err := os.Create(opts.DumpHeader)
		if err == nil {
			_, _ = fmt.Fprintf(df, "HTTP/%d.%d %s\r\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
			for k, vals := range resp.Header {
				for _, v := range vals {
					_, _ = fmt.Fprintf(df, "%s: %s\r\n", k, v)
				}
			}
			_, _ = fmt.Fprintf(df, "\r\n")
			_ = df.Close()
		}
	}

	// Determine output writer
	var output io.Writer = os.Stdout
	if opts.OutputFile != "" {
		if opts.OutputFile == "/dev/null" || opts.OutputFile == "NUL" {
			output = io.Discard
		} else {
			flags := os.O_CREATE | os.O_WRONLY
			if opts.AutoResume || opts.ResumeOffset > 0 {
				flags |= os.O_APPEND
			} else {
				flags |= os.O_TRUNC
			}
			f, err := os.OpenFile(opts.OutputFile, flags, 0644)
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

		if opts.LimitRate > 0 {
			bodyReader = &rateLimitedReader{r: bodyReader, bytesPerSec: opts.LimitRate}
		}

		n, _ := io.Copy(output, bodyReader)
		sizeDownload = n
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
		wout = strings.ReplaceAll(wout, "%{size_download}", fmt.Sprintf("%d", sizeDownload))
		wout = strings.ReplaceAll(wout, "%{time_total}", fmt.Sprintf("%.3f", time.Since(startTime).Seconds()))
		wout = strings.ReplaceAll(wout, "%{url_effective}", req.URL.String())
		wout = strings.ReplaceAll(wout, "%{content_type}", resp.Header.Get("Content-Type"))
		wout = strings.ReplaceAll(wout, "%{remote_ip}", req.URL.Hostname()) // Simplified
		wout = strings.ReplaceAll(wout, "\\n", "\n")
		_, _ = fmt.Fprint(os.Stdout, wout)
	}

	// Handle trace-ascii
	if opts.TraceAscii != "" {
		tf, err := os.Create(opts.TraceAscii)
		if err == nil {
			_, _ = fmt.Fprintf(tf, "== Info: Connected to %s\n", req.URL.Host)
			_, _ = fmt.Fprintf(tf, "=> Send header, %d bytes\n", 0) // Simplified
			_, _ = fmt.Fprintf(tf, "> %s %s HTTP/1.1\n", req.Method, req.URL.RequestURI())
			for k, vals := range req.Header {
				for _, v := range vals {
					_, _ = fmt.Fprintf(tf, "> %s: %s\n", k, v)
				}
			}
			_, _ = fmt.Fprintf(tf, "\n")
			_, _ = fmt.Fprintf(tf, "<= Recv header, %d bytes\n", 0) // Simplified
			_, _ = fmt.Fprintf(tf, "< HTTP/%d.%d %s\n", resp.ProtoMajor, resp.ProtoMinor, resp.Status)
			for k, vals := range resp.Header {
				for _, v := range vals {
					_, _ = fmt.Fprintf(tf, "< %s: %s\n", k, v)
				}
			}
			_, _ = fmt.Fprintf(tf, "\n")
			_ = tf.Close()
		}
	}
}

type rateLimitedReader struct {
	r           io.Reader
	bytesPerSec int64
}

func (l *rateLimitedReader) Read(p []byte) (int, error) {
	// Small buffer for better precision
	chunkSize := len(p)
	if int64(chunkSize) > l.bytesPerSec/10 {
		chunkSize = int(l.bytesPerSec / 10)
		if chunkSize < 1 {
			chunkSize = 1
		}
	}

	n, err := l.r.Read(p[:chunkSize])
	if n > 0 {
		sleepDuration := time.Duration(n) * time.Second / time.Duration(l.bytesPerSec)
		time.Sleep(sleepDuration)
	}
	return n, err
}
