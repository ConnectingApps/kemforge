package main

import (
	"encoding/base64"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path"
	"strings"
)

// NewHTTPRequest builds a fully configured *http.Request from the parsed options for a specific URL.
func NewHTTPRequest(opts Options, targetURL string) *http.Request {

	// Ensure URL has scheme
	if !strings.Contains(targetURL, "://") {
		targetURL = "http://" + targetURL
	}

	// Handle -G (GET with data as query params)
	if opts.GetMode && len(opts.URLEncodeArgs) > 0 {
		u, err := url.Parse(targetURL)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: URL parse error: %v\n", err)
			os.Exit(1)
		}
		q := u.Query()
		for _, arg := range opts.URLEncodeArgs {
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
	method := opts.Method
	if method == "" {
		if opts.HeadReq {
			method = "HEAD"
		} else if len(opts.DataArgs) > 0 || len(opts.FormArgs) > 0 || opts.JSONData != "" {
			method = "POST"
		} else if opts.UploadFile != "" {
			method = "PUT"
		} else {
			method = "GET"
		}
	}

	// Build request body
	body, contentType := buildRequestBody(opts)

	// Override content type if user set it via -H
	for _, h := range opts.Headers {
		parts := strings.SplitN(h, ":", 2)
		if len(parts) == 2 && strings.EqualFold(strings.TrimSpace(parts[0]), "content-type") {
			contentType = strings.TrimSpace(parts[1])
		}
	}

	// Build HTTP request
	req, err := http.NewRequest(method, targetURL, body)
	if err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: %v\n", err)
		os.Exit(1)
	}

	// Set user agent
	req.Header.Set("User-Agent", opts.UserAgent)

	// Set referer
	if opts.Referer != "" {
		req.Header.Set("Referer", opts.Referer)
	}

	// Set Accept
	if opts.JSONData != "" {
		req.Header.Set("Accept", "application/json")
	} else {
		req.Header.Set("Accept", "*/*")
	}

	// Set content type
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}

	// Set custom headers
	for _, h := range opts.Headers {
		parts := strings.SplitN(h, ":", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			if val == "" {
				req.Header.Del(key)
			} else {
				req.Header.Set(key, val)
			}
		}
	}

	// Set basic auth
	if opts.BasicAuth != "" {
		parts := strings.SplitN(opts.BasicAuth, ":", 2)
		if len(parts) == 2 {
			req.Header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(opts.BasicAuth)))
		}
	}

	// Set range header
	if opts.RangeHeader != "" {
		req.Header.Set("Range", "bytes="+opts.RangeHeader)
	} else if opts.AutoResume && opts.OutputFile != "" {
		if info, err := os.Stat(opts.OutputFile); err == nil {
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-", info.Size()))
		}
	} else if opts.ResumeOffset > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", opts.ResumeOffset))
	}

	// Set compressed header
	if opts.Compressed {
		req.Header.Set("Accept-Encoding", "gzip, deflate")
	}

	return req
}

// buildRequestBody creates the request body and content type from the options.
func buildRequestBody(opts Options) (io.Reader, string) {
	if opts.UploadFile != "" {
		f, err := os.Open(opts.UploadFile)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", opts.UploadFile, err)
			os.Exit(1)
		}
		return f, ""
	}

	if opts.JSONData != "" {
		data := opts.JSONData
		if strings.HasPrefix(data, "@") {
			filePath := data[1:]
			content, err := os.ReadFile(filePath)
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", filePath, err)
				os.Exit(1)
			}
			data = string(content)
		}
		return strings.NewReader(data), "application/json"
	}

	if len(opts.FormArgs) > 0 {
		// Multipart form
		var buf strings.Builder
		w := multipart.NewWriter(&buf)
		for _, f := range opts.FormArgs {
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
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", filePath, err)
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
		return strings.NewReader(buf.String()), w.FormDataContentType()
	}

	if len(opts.DataArgs) > 0 {
		// Check for @file syntax
		var allData []string
		for _, d := range opts.DataArgs {
			if strings.HasPrefix(d, "@") {
				filePath := d[1:]
				var data []byte
				var err error
				if filePath == "-" {
					data, err = io.ReadAll(os.Stdin)
				} else {
					data, err = os.ReadFile(filePath)
				}
				if err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", filePath, err)
					os.Exit(1)
				}
				allData = append(allData, string(data))
			} else {
				allData = append(allData, d)
			}
		}
		combined := strings.Join(allData, "&")
		return strings.NewReader(combined), "application/x-www-form-urlencoded"
	}

	return nil, ""
}
