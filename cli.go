package main

import (
	"fmt"
	"io"
	"os"
	"strings"
)

// Options holds all CLI flags and arguments parsed from os.Args.
type Options struct {
	Silent        bool
	ShowErrors    bool
	Verbose       bool
	HeadReq       bool
	IncludeHdr    bool
	FollowRedirs  bool
	Insecure      bool
	Compressed    bool
	GetMode       bool // -G: append data as query params
	RemoteOut     bool // -O
	Method        string
	UserAgent     string
	OutputFile    string   // single -o
	OutputFiles   []string // multiple -o
	WriteOut      string
	CookieJar     string // -c
	CookieFile    string // -b
	BasicAuth     string // -u user:pass
	ProxyURL      string // -x
	ConnectTmout  float64
	MaxTime       float64
	RetryCount    int      // --retry
	MaxRedirs     int      // --max-redirs
	Referer       string   // -e
	FailOnError   bool     // -f
	JSONData      string   // --json
	DataBinary    []string // --data-binary
	ConfigPath    string   // -K
	NoProxy       string   // --noproxy
	LimitRate     int64    // --limit-rate (bytes per second)
	Parallel      bool     // -Z
	RangeHeader   string   // -r
	Headers       []string
	DataArgs      []string // -d
	FormArgs      []string // -F
	URLEncodeArgs []string // --data-urlencode
	ResolveArgs   []string // --resolve
	DataRaw       []string // --data-raw
	DumpHeader    string   // --dump-header
	UploadFile    string   // -T
	ResumeOffset  int64    // -C
	AutoResume    bool     // -C -
	HTTP11        bool     // --http1.1
	TargetURLs    []string
	CertFile      string // --cert
	KeyFile       string // --key
	Pass          string // --pass
	DigestAuth    bool   // --digest
	NetrcFile     string // --netrc-file
	UnixSocket    string // --unix-socket
	TimeCond      string // -z
	TraceAscii    string // --trace-ascii
	DohURL        string // --doh-url
	IPv4          bool   // -4
	IPv6          bool   // -6
	Netrc         bool   // -n
	CookieEnable  bool   // true if -b was specified
	ProxyUser     string // --proxy-user user:pass
	ShowHelp      bool   // --help
	ShowVersion   bool   // --version
	ShowManual    bool   // --manual

	// New fields
	CreateDirs       bool
	OutputDir        string
	RemoteHeaderName bool
	RemoteTime       bool
	Post301          bool
	Post302          bool
	Post303          bool
	LocationTrusted  bool
	Interface        string
	FormStringArgs   []string
	MaxFileSize      int64
	SpeedLimit       int64
	SpeedTime        float64
	CACert           string
	PinnedPubKey     string
	RetryDelay       float64
	RetryConnRefused bool
	RetryAllErrors   bool
	FailEarly        bool
}

// ParseArgs parses command-line arguments into an Options struct.
func ParseArgs(args []string) []Options {
	var allOpts []Options
	opts := Options{
		UserAgent: "kemforge/1.0",
	}

	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--next":
			allOpts = append(allOpts, opts)
			// Reset for next
			opts = Options{
				UserAgent: "kemforge/1.0",
			}
		case a == "-s" || a == "--silent":
			opts.Silent = true
		case a == "-S" || a == "--show-error":
			opts.ShowErrors = true
		case a == "-sS" || a == "-Ss":
			opts.Silent = true
			opts.ShowErrors = true
		case a == "-v" || a == "--verbose":
			opts.Verbose = true
		case a == "-I" || a == "--head":
			opts.HeadReq = true
		case a == "-i" || a == "--include":
			opts.IncludeHdr = true
		case a == "-L" || a == "--location":
			opts.FollowRedirs = true
		case a == "--max-redirs":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%d", &opts.MaxRedirs)
			}
		case a == "--create-dirs":
			opts.CreateDirs = true
		case a == "--output-dir":
			i++
			if i < len(args) {
				opts.OutputDir = args[i]
			}
		case a == "-J" || a == "--remote-header-name":
			opts.RemoteHeaderName = true
		case a == "-R" || a == "--remote-time":
			opts.RemoteTime = true
		case a == "--post301":
			opts.Post301 = true
		case a == "--post302":
			opts.Post302 = true
		case a == "--post303":
			opts.Post303 = true
		case a == "--location-trusted":
			opts.LocationTrusted = true
		case a == "--interface":
			i++
			if i < len(args) {
				opts.Interface = args[i]
			}
		case a == "--form-string":
			i++
			if i < len(args) {
				opts.FormStringArgs = append(opts.FormStringArgs, args[i])
			}
		case a == "--max-filesize":
			i++
			if i < len(args) {
				opts.MaxFileSize = parseRate(args[i])
			}
		case a == "--speed-limit":
			i++
			if i < len(args) {
				opts.SpeedLimit = parseRate(args[i])
			}
		case a == "--speed-time":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%f", &opts.SpeedTime)
			}
		case a == "--cacert":
			i++
			if i < len(args) {
				opts.CACert = args[i]
			}
		case a == "--pinnedpubkey":
			i++
			if i < len(args) {
				opts.PinnedPubKey = args[i]
			}
		case a == "-D" || a == "--dump-header":
			i++
			if i < len(args) {
				opts.DumpHeader = args[i]
			}
		case a == "-T" || a == "--upload-file":
			i++
			if i < len(args) {
				opts.UploadFile = args[i]
			}
		case a == "-C" || a == "--continue-at":
			i++
			if i < len(args) {
				if args[i] == "-" {
					opts.AutoResume = true
				} else {
					_, _ = fmt.Sscanf(args[i], "%d", &opts.ResumeOffset)
				}
			}
		case a == "--http1.1":
			opts.HTTP11 = true
		case a == "-k" || a == "--insecure":
			opts.Insecure = true
		case a == "--compressed":
			opts.Compressed = true
		case a == "-G" || a == "--get":
			opts.GetMode = true
		case a == "-Z" || a == "--parallel":
			opts.Parallel = true
		case a == "-O" || a == "--remote-name":
			opts.RemoteOut = true
		case a == "-X" || a == "--request":
			i++
			if i < len(args) {
				opts.Method = args[i]
			}
		case a == "-A" || a == "--user-agent":
			i++
			if i < len(args) {
				opts.UserAgent = args[i]
			}
		case a == "-H" || a == "--header":
			i++
			if i < len(args) {
				opts.Headers = append(opts.Headers, args[i])
			}
		case a == "-o" || a == "--output":
			i++
			if i < len(args) {
				opts.OutputFile = args[i]
				opts.OutputFiles = append(opts.OutputFiles, args[i])
			}
		case a == "-w":
			i++
			if i < len(args) {
				opts.WriteOut = args[i]
			}
		case a == "-c" || a == "--cookie-jar":
			i++
			if i < len(args) {
				opts.CookieJar = args[i]
			}
		case a == "-e" || a == "--referer":
			i++
			if i < len(args) {
				opts.Referer = args[i]
			}
		case a == "-f" || a == "--fail":
			opts.FailOnError = true
		case a == "-b" || a == "--cookie":
			opts.CookieEnable = true
			i++
			if i < len(args) {
				opts.CookieFile = args[i]
			}
		case a == "--data-binary":
			i++
			if i < len(args) {
				opts.DataBinary = append(opts.DataBinary, args[i])
			}
		case a == "--data-raw":
			i++
			if i < len(args) {
				opts.DataRaw = append(opts.DataRaw, args[i])
			}
		case a == "--noproxy":
			i++
			if i < len(args) {
				opts.NoProxy = args[i]
			}
		case a == "-E" || a == "--cert":
			i++
			if i < len(args) {
				cert := args[i]
				opts.CertFile = cert
				// Check for certificate:password
				if !strings.HasPrefix(cert, "./") && !strings.HasPrefix(cert, "/") {
					colonIdx := strings.Index(cert, ":")
					if colonIdx == 1 && len(cert) >= 3 && ((cert[0] >= 'a' && cert[0] <= 'z') || (cert[0] >= 'A' && cert[0] <= 'Z')) && (cert[2] == '\\' || cert[2] == '/') {
						// Windows drive prefix (e.g., C:\), look for a second colon
						rest := cert[2:]
						if nextColon := strings.Index(rest, ":"); nextColon != -1 {
							opts.CertFile = cert[:2+nextColon]
							opts.Pass = rest[nextColon+1:]
						}
					} else if colonIdx != -1 {
						opts.CertFile = cert[:colonIdx]
						opts.Pass = cert[colonIdx+1:]
					}
				}
			}
		case a == "--key":
			i++
			if i < len(args) {
				opts.KeyFile = args[i]
			}
		case a == "--pass":
			i++
			if i < len(args) {
				opts.Pass = args[i]
			}
		case a == "--digest":
			opts.DigestAuth = true
		case a == "--netrc-file":
			i++
			if i < len(args) {
				opts.NetrcFile = args[i]
			}
		case a == "--unix-socket":
			i++
			if i < len(args) {
				opts.UnixSocket = args[i]
			}
		case a == "-z" || a == "--time-cond":
			i++
			if i < len(args) {
				opts.TimeCond = args[i]
			}
		case a == "--trace-ascii":
			i++
			if i < len(args) {
				opts.TraceAscii = args[i]
			}
		case a == "-n" || a == "--netrc":
			opts.Netrc = true
		case a == "-4" || a == "--ipv4":
			opts.IPv4 = true
		case a == "-6" || a == "--ipv6":
			opts.IPv6 = true
		case a == "--doh-url":
			i++
			if i < len(args) {
				opts.DohURL = args[i]
			}
		case a == "-u" || a == "--user":
			i++
			if i < len(args) {
				opts.BasicAuth = args[i]
			}
		case a == "-K" || a == "--config":
			i++
			if i < len(args) {
				parseConfigFile(&opts, args[i])
			}
		case a == "-x" || a == "--proxy":
			i++
			if i < len(args) {
				opts.ProxyURL = args[i]
			}
		case a == "--proxy-user":
			i++
			if i < len(args) {
				opts.ProxyUser = args[i]
			}
		case a == "-d" || a == "--data":
			i++
			if i < len(args) {
				opts.DataArgs = append(opts.DataArgs, args[i])
			}
		case a == "-F" || a == "--form":
			i++
			if i < len(args) {
				opts.FormArgs = append(opts.FormArgs, args[i])
			}
		case a == "--data-urlencode":
			i++
			if i < len(args) {
				opts.URLEncodeArgs = append(opts.URLEncodeArgs, args[i])
			}
		case a == "--json":
			i++
			if i < len(args) {
				opts.JSONData = args[i]
			}
		case a == "--retry":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%d", &opts.RetryCount)
			}
		case a == "--retry-delay":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%f", &opts.RetryDelay)
			}
		case a == "--retry-connrefused":
			opts.RetryConnRefused = true
		case a == "--retry-all-errors":
			opts.RetryAllErrors = true
		case a == "--fail-early":
			opts.FailEarly = true
		case a == "--resolve":
			i++
			if i < len(args) {
				opts.ResolveArgs = append(opts.ResolveArgs, args[i])
			}
		case a == "--limit-rate":
			i++
			if i < len(args) {
				opts.LimitRate = parseRate(args[i])
			}
		case a == "--connect-timeout":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%f", &opts.ConnectTmout)
			}
		case a == "--max-time" || a == "-m":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%f", &opts.MaxTime)
			}
		case a == "-r" || a == "--range":
			i++
			if i < len(args) {
				opts.RangeHeader = args[i]
			}
		case a == "--help":
			opts.ShowHelp = true
		case a == "--manual":
			opts.ShowManual = true
		case a == "--version":
			opts.ShowVersion = true
		case strings.HasPrefix(a, "-"):
			// Unknown flag, ignore
		default:
			opts.TargetURLs = append(opts.TargetURLs, expandGlob(a)...)
		}
	}

	allOpts = append(allOpts, opts)

	// If no URLs found in any of the segments, and not showing help/version/manual
	hasURLs := false
	for _, o := range allOpts {
		if len(o.TargetURLs) > 0 || o.ShowHelp || o.ShowVersion || o.ShowManual {
			hasURLs = true
			break
		}
	}

	if !hasURLs {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	return allOpts
}

func parseConfigFile(opts *Options, configPath string) {
	var data []byte
	var err error
	if configPath == "-" {
		data, err = io.ReadAll(os.Stdin)
	} else {
		data, err = os.ReadFile(configPath)
	}
	if err != nil {
		return
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		key := strings.TrimSpace(parts[0])
		val := ""
		if len(parts) == 2 {
			val = strings.Trim(strings.TrimSpace(parts[1]), "\"")
		}

		switch key {
		case "url":
			opts.TargetURLs = append(opts.TargetURLs, val)
		case "header":
			opts.Headers = append(opts.Headers, val)
		case "user-agent":
			opts.UserAgent = val
		case "referer":
			opts.Referer = val
		}
	}
}

func parseRate(s string) int64 {
	s = strings.ToLower(s)
	unit := int64(1)
	valStr := s
	switch {
	case strings.HasSuffix(s, "k"):
		unit = 1024
		valStr = s[:len(s)-1]
	case strings.HasSuffix(s, "m"):
		unit = 1024 * 1024
		valStr = s[:len(s)-1]
	case strings.HasSuffix(s, "g"):
		unit = 1024 * 1024 * 1024
		valStr = s[:len(s)-1]
	}
	var val int64
	_, _ = fmt.Sscanf(valStr, "%d", &val)
	return val * unit
}

func expandGlob(s string) []string {
	// Very basic implementation of {} and []
	urls := []string{s}

	// Handle {}
	for {
		newURLs := []string{}
		found := false
		for _, u := range urls {
			start := strings.Index(u, "{")
			end := strings.Index(u, "}")
			if start != -1 && end > start {
				found = true
				prefix := u[:start]
				suffix := u[end+1:]
				for opt := range strings.SplitSeq(u[start+1:end], ",") {
					newURLs = append(newURLs, prefix+opt+suffix)
				}
			} else {
				newURLs = append(newURLs, u)
			}
		}
		urls = newURLs
		if !found {
			break
		}
	}

	// Handle []
	for {
		newURLs := []string{}
		found := false
		for _, u := range urls {
			start := strings.Index(u, "[")
			end := strings.Index(u, "]")
			if start != -1 && end > start {
				content := u[start+1 : end]
				if strings.Contains(content, "-") {
					parts := strings.SplitN(content, "-", 2)
					if len(parts) == 2 {
						found = true
						prefix := u[:start]
						suffix := u[end+1:]

						// Try numeric range
						var low, high int
						_, err1 := fmt.Sscanf(parts[0], "%d", &low)
						_, err2 := fmt.Sscanf(parts[1], "%d", &high)
						if err1 == nil && err2 == nil {
							for i := low; i <= high; i++ {
								// Handle leading zeros if any
								format := "%d"
								if len(parts[0]) == len(parts[1]) && strings.HasPrefix(parts[0], "0") {
									format = fmt.Sprintf("%%0%dd", len(parts[0]))
								}
								newURLs = append(newURLs, prefix+fmt.Sprintf(format, i)+suffix)
							}
						} else if len(parts[0]) == 1 && len(parts[1]) == 1 {
							// Char range
							for c := parts[0][0]; c <= parts[1][0]; c++ {
								newURLs = append(newURLs, prefix+string(c)+suffix)
							}
						} else {
							newURLs = append(newURLs, u)
							found = false
						}
					} else {
						newURLs = append(newURLs, u)
					}
				} else {
					newURLs = append(newURLs, u)
				}
			} else {
				newURLs = append(newURLs, u)
			}
		}
		urls = newURLs
		if !found {
			break
		}
	}

	return urls
}
