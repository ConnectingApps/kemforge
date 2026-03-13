package main

import (
	"compress/gzip"
	"compress/zlib"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
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
	var outPath string

	if opts.RemoteOut {
		remoteName := path.Base(req.URL.Path)
		if opts.RemoteHeaderName {
			if cd := resp.Header.Get("Content-Disposition"); cd != "" {
				if parts := strings.Split(cd, "filename="); len(parts) > 1 {
					remoteName = strings.Trim(strings.TrimSpace(parts[1]), "\"")
				}
			}
		}
		if remoteName == "" || remoteName == "/" || remoteName == "." {
			remoteName = "index.html"
		}
		outPath = remoteName
	}

	if opts.OutputFile != "" {
		outPath = opts.OutputFile
	}

	if outPath != "" {
		if outPath == "/dev/null" || outPath == "NUL" {
			output = io.Discard
		} else {
			if opts.OutputDir != "" {
				outPath = filepath.Join(opts.OutputDir, outPath)
			}

			if opts.CreateDirs {
				_ = os.MkdirAll(filepath.Dir(outPath), 0755)
			}

			flags := os.O_CREATE | os.O_WRONLY
			if opts.AutoResume || opts.ResumeOffset > 0 {
				flags |= os.O_APPEND
			} else {
				flags |= os.O_TRUNC
			}
			f, err := os.OpenFile(outPath, flags, 0644)
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't open '%s': %v\n", outPath, err)
				os.Exit(1)
			}
			defer func() {
				_ = f.Close()
				if opts.RemoteTime {
					if lm := resp.Header.Get("Last-Modified"); lm != "" {
						if t, err := http.ParseTime(lm); err == nil {
							_ = os.Chtimes(outPath, t, t)
						}
					}
				}
			}()
			output = f
		}
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

		if opts.SpeedLimit > 0 && opts.SpeedTime > 0 {
			bodyReader = &speedLimitedReader{r: bodyReader, limit: opts.SpeedLimit, time: opts.SpeedTime}
		}

		var n int64
		var err error
		if opts.MaxFileSize > 0 {
			cw := &countingWriter{w: output, limit: opts.MaxFileSize}
			n, err = io.Copy(cw, bodyReader)
			if (err == nil || err == io.EOF) && cw.count >= opts.MaxFileSize {
				// Check if there was more to read
				var buf [1]byte
				if nr, _ := bodyReader.Read(buf[:]); nr > 0 {
					os.Exit(63)
				}
			}
		} else {
			n, err = io.Copy(output, bodyReader)
		}
		sizeDownload = n

		if err != nil {
			if err.Error() == "speed limit exceeded" {
				os.Exit(28)
			}
		}
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
	n, err := l.r.Read(p)
	if n > 0 {
		sleepDuration := time.Duration(n) * time.Second / time.Duration(l.bytesPerSec)
		time.Sleep(sleepDuration)
	}
	return n, err
}

type countingWriter struct {
	w     io.Writer
	limit int64
	count int64
}

func (cw *countingWriter) Write(p []byte) (int, error) {
	if cw.count >= cw.limit {
		return 0, io.EOF
	}
	remaining := cw.limit - cw.count
	toWrite := int64(len(p))
	if toWrite > remaining {
		toWrite = remaining
	}
	n, err := cw.w.Write(p[:toWrite])
	cw.count += int64(n)
	if err == nil && int64(n) < int64(len(p)) {
		return n, io.EOF
	}
	return n, err
}

type speedLimitedReader struct {
	r     io.Reader
	limit int64
	time  float64
	start time.Time
	read  int64
}

func (l *speedLimitedReader) Read(p []byte) (int, error) {
	if l.start.IsZero() {
		l.start = time.Now()
	}
	n, err := l.r.Read(p)
	l.read += int64(n)
	elapsed := time.Since(l.start).Seconds()
	if elapsed >= l.time {
		speed := float64(l.read) / elapsed
		if speed < float64(l.limit) {
			return n, fmt.Errorf("speed limit exceeded")
		}
	}
	return n, err
}
