package main

import (
	"fmt"
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
	OutputFile    string
	WriteOut      string
	CookieJar     string // -c
	CookieFile    string // -b
	BasicAuth     string // -u user:pass
	ProxyURL      string // -x
	ConnectTmout  float64
	MaxTime       float64
	RetryCount    int    // --retry
	MaxRedirs     int    // --max-redirs
	Referer       string // -e
	FailOnError   bool   // -f
	JSONData      string // --json
	ConfigPath    string // -K
	LimitRate     int64  // --limit-rate (bytes per second)
	Parallel      bool   // -Z
	RangeHeader   string // -r
	Headers       []string
	DataArgs      []string // -d
	FormArgs      []string // -F
	URLEncodeArgs []string // --data-urlencode
	ResolveArgs   []string // --resolve
	TargetURLs    []string
}

// ParseArgs parses command-line arguments into an Options struct.
func ParseArgs(args []string) Options {
	opts := Options{
		UserAgent: "kemforge/1.0",
	}

	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-s":
			opts.Silent = true
		case a == "-S":
			opts.ShowErrors = true
		case a == "-sS" || a == "-Ss":
			opts.Silent = true
			opts.ShowErrors = true
		case a == "-v":
			opts.Verbose = true
		case a == "-I":
			opts.HeadReq = true
		case a == "-i":
			opts.IncludeHdr = true
		case a == "-L":
			opts.FollowRedirs = true
		case a == "--max-redirs":
			i++
			if i < len(args) {
				_, _ = fmt.Sscanf(args[i], "%d", &opts.MaxRedirs)
			}
		case a == "-k" || a == "--insecure":
			opts.Insecure = true
		case a == "--compressed":
			opts.Compressed = true
		case a == "-G":
			opts.GetMode = true
		case a == "-Z" || a == "--parallel":
			opts.Parallel = true
		case a == "-O":
			opts.RemoteOut = true
		case a == "-X":
			i++
			if i < len(args) {
				opts.Method = args[i]
			}
		case a == "-A":
			i++
			if i < len(args) {
				opts.UserAgent = args[i]
			}
		case a == "-H":
			i++
			if i < len(args) {
				opts.Headers = append(opts.Headers, args[i])
			}
		case a == "-o":
			i++
			if i < len(args) {
				opts.OutputFile = args[i]
			}
		case a == "-w":
			i++
			if i < len(args) {
				opts.WriteOut = args[i]
			}
		case a == "-c":
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
		case a == "-b":
			i++
			if i < len(args) {
				opts.CookieFile = args[i]
			}
		case a == "-u":
			i++
			if i < len(args) {
				opts.BasicAuth = args[i]
			}
		case a == "-K" || a == "--config":
			i++
			if i < len(args) {
				opts.ConfigPath = args[i]
			}
		case a == "-x":
			i++
			if i < len(args) {
				opts.ProxyURL = args[i]
			}
		case a == "-d":
			i++
			if i < len(args) {
				opts.DataArgs = append(opts.DataArgs, args[i])
			}
		case a == "-F":
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
		case strings.HasPrefix(a, "-"):
			// Unknown flag, ignore
		default:
			opts.TargetURLs = append(opts.TargetURLs, a)
		}
	}

	if opts.ConfigPath != "" {
		parseConfigFile(&opts)
	}

	if len(opts.TargetURLs) == 0 {
		_, _ = fmt.Fprintf(os.Stderr, "kemforge: no URL specified\n")
		os.Exit(1)
	}

	return opts
}

func parseConfigFile(opts *Options) {
	data, err := os.ReadFile(opts.ConfigPath)
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
