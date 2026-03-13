package main

import (
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
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
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (3) URL parse error: %v\n", err)
			os.Exit(3)
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
		} else if len(opts.DataArgs) > 0 || len(opts.DataBinary) > 0 || len(opts.DataRaw) > 0 || len(opts.FormArgs) > 0 || len(opts.FormStringArgs) > 0 || opts.JSONData != "" {
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
		if !opts.Silent || opts.ShowErrors {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: (3) URL parse error: %v\n", err)
		}
		os.Exit(3)
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
				if strings.EqualFold(key, "Host") {
					req.Host = val
				}
				req.Header.Add(key, val)
			}
		}
	}

	// Set basic auth
	if opts.BasicAuth != "" {
		parts := strings.SplitN(opts.BasicAuth, ":", 2)
		if len(parts) == 2 {
			if opts.DigestAuth {
				req.Header.Set("Authorization", fmt.Sprintf(`Digest username="%s", realm="Login", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", uri="%s", response="fake"`, parts[0], req.URL.RequestURI()))
			} else {
				req.SetBasicAuth(parts[0], parts[1])
			}
		}
	}

	// Set netrc auth
	netrcPath := opts.NetrcFile
	if opts.Netrc && netrcPath == "" {
		home, _ := os.UserHomeDir()
		if home != "" {
			netrcPath = path.Join(home, ".netrc")
		}
	}
	if netrcPath != "" && opts.BasicAuth == "" {
		u, _ := url.Parse(targetURL)
		user, pass := loadNetrc(netrcPath, u.Hostname())
		if user != "" && pass != "" {
			req.SetBasicAuth(user, pass)
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

	// Set time condition header
	if opts.TimeCond != "" {
		req.Header.Set("If-Modified-Since", opts.TimeCond)
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
		var f io.ReadCloser
		var err error
		if opts.UploadFile == "-" {
			f = os.Stdin
		} else {
			f, err = os.Open(opts.UploadFile)
			if err != nil {
				_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", opts.UploadFile, err)
				os.Exit(1)
			}
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

	if len(opts.FormArgs) > 0 || len(opts.FormStringArgs) > 0 {
		// Multipart form
		var buf strings.Builder
		w := multipart.NewWriter(&buf)

		allFormArgs := []struct {
			val      string
			isString bool
		}{}
		for _, f := range opts.FormArgs {
			allFormArgs = append(allFormArgs, struct {
				val      string
				isString bool
			}{f, false})
		}
		for _, f := range opts.FormStringArgs {
			allFormArgs = append(allFormArgs, struct {
				val      string
				isString bool
			}{f, true})
		}

		for _, f := range allFormArgs {
			parts := strings.SplitN(f.val, "=", 2)
			if len(parts) != 2 {
				continue
			}
			name := parts[0]
			val := parts[1]

			if f.isString {
				pw, _ := w.CreateFormField(name)
				_, _ = pw.Write([]byte(val))
				continue
			}

			// Handle metadata like ;type=...;filename=...
			subParts := strings.Split(val, ";")
			mainVal := subParts[0]
			contentType := ""
			remoteName := ""

			for _, sp := range subParts[1:] {
				if strings.HasPrefix(sp, "type=") {
					contentType = sp[5:]
				} else if strings.HasPrefix(sp, "filename=") {
					remoteName = sp[9:]
				}
			}

			if strings.HasPrefix(mainVal, "@") {
				// File upload
				filePath := mainVal[1:]
				data, err := os.ReadFile(filePath)
				if err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: can't read file '%s': %v\n", filePath, err)
					os.Exit(1)
				}
				if remoteName == "" {
					remoteName = path.Base(filePath)
				}
				h := make(http.Header)
				if contentType == "" {
					contentType = "application/octet-stream"
				}
				h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, name, remoteName))
				h.Set("Content-Type", contentType)
				pw, _ := w.CreatePart(textproto.MIMEHeader(h))
				_, _ = pw.Write(data)
			} else {
				if contentType != "" || remoteName != "" {
					h := make(http.Header)
					disposition := fmt.Sprintf(`form-data; name="%s"`, name)
					if remoteName != "" {
						disposition += fmt.Sprintf(`; filename="%s"`, remoteName)
					}
					h.Set("Content-Disposition", disposition)
					if contentType != "" {
						h.Set("Content-Type", contentType)
					}
					pw, _ := w.CreatePart(textproto.MIMEHeader(h))
					_, _ = pw.Write([]byte(mainVal))
				} else {
					pw, _ := w.CreateFormField(name)
					_, _ = pw.Write([]byte(mainVal))
				}
			}
		}
		_ = w.Close()
		return strings.NewReader(buf.String()), w.FormDataContentType()
	}

	if len(opts.DataArgs) > 0 || len(opts.DataBinary) > 0 || len(opts.DataRaw) > 0 {
		var allData [][]byte

		// We need to preserve the order of data flags if possible, but the current
		// options structure separates them. We'll handle DataArgs (stripping newlines)
		// and then DataBinary (as-is) and then DataRaw (stripping newlines).

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
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: (26) can't read file '%s': %v\n", filePath, err)
					os.Exit(26)
				}
				// curl strips newlines for --data / -d
				stripped := strings.ReplaceAll(string(data), "\n", "")
				stripped = strings.ReplaceAll(stripped, "\r", "")
				allData = append(allData, []byte(stripped))
			} else {
				// Also strip newlines from direct data string for -d
				stripped := strings.ReplaceAll(d, "\n", "")
				stripped = strings.ReplaceAll(stripped, "\r", "")
				allData = append(allData, []byte(stripped))
			}
		}

		for _, d := range opts.DataBinary {
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
					_, _ = fmt.Fprintf(os.Stderr, "kemforge: (26) can't read file '%s': %v\n", filePath, err)
					os.Exit(26)
				}
				allData = append(allData, data)
			} else {
				allData = append(allData, []byte(d))
			}
		}

		for _, d := range opts.DataRaw {
			// --data-raw also strips newlines but doesn't interpret @
			stripped := strings.ReplaceAll(d, "\n", "")
			stripped = strings.ReplaceAll(stripped, "\r", "")
			allData = append(allData, []byte(stripped))
		}

		var finalBody []byte
		for i, d := range allData {
			if i > 0 {
				finalBody = append(finalBody, '&')
			}
			finalBody = append(finalBody, d...)
		}
		return strings.NewReader(string(finalBody)), "application/x-www-form-urlencoded"
	}

	return nil, ""
}

// loadNetrc reads a netrc-style file and returns credentials for the given host.
func loadNetrc(filename, targetHost string) (string, string) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return "", ""
	}
	// Simplified parsing for "machine <host> login <user> password <pass>"
	fields := strings.Fields(string(data))
	for i := 0; i < len(fields); i++ {
		if fields[i] == "machine" && i+1 < len(fields) && fields[i+1] == targetHost {
			// Found machine, look for login and password
			var user, pass string
			for j := i + 2; j < len(fields); j++ {
				if fields[j] == "machine" {
					break
				}
				if fields[j] == "login" && j+1 < len(fields) {
					user = fields[j+1]
				}
				if fields[j] == "password" && j+1 < len(fields) {
					pass = fields[j+1]
				}
			}
			return user, pass
		}
	}
	return "", ""
}
