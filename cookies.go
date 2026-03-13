package main

import (
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

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
	now := time.Now()
	for _, c := range j.entries[host] {
		if !c.Expires.IsZero() && c.Expires.Before(now) {
			continue
		}
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
				Path:  fields[1],
			}
			expires, _ := strconv.ParseInt(fields[4], 10, 64)
			if expires > 0 {
				c.Expires = time.Unix(expires, 0)
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
