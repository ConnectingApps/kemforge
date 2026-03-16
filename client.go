package main

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/des"
	"crypto/md5"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/icholy/digest"
	"github.com/youmark/pkcs8"
	"golang.org/x/net/http2"
)

// BuildClient creates an *http.Client with the appropriate transport,
// proxy, TLS, timeout, redirect, and cookie jar settings.
func BuildClient(opts Options) (*http.Client, *simpleCookieJar) {
	tlsConfig := &tls.Config{
		InsecureSkipVerify: opts.Insecure,
	}

	if opts.CACert != "" {
		caCert, err := os.ReadFile(opts.CACert)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "kemforge: failed to read CA cert: %v\n", err)
		} else {
			caCertPool := x509.NewCertPool()
			caCertPool.AppendCertsFromPEM(caCert)
			tlsConfig.RootCAs = caCertPool
		}
	}

	if opts.PinnedPubKey != "" {
		tlsConfig.VerifyConnection = func(cs tls.ConnectionState) error {
			if len(cs.PeerCertificates) == 0 {
				return fmt.Errorf("no peer certificates")
			}
			peerPubKey, err := x509.MarshalPKIXPublicKey(cs.PeerCertificates[0].PublicKey)
			if err != nil {
				return err
			}

			if strings.HasPrefix(opts.PinnedPubKey, "sha256//") {
				peerHash := sha256.Sum256(peerPubKey)
				for h := range strings.SplitSeq(opts.PinnedPubKey, ";") {
					if strings.HasPrefix(h, "sha256//") {
						b64Hash := h[8:]
						decoded, err := base64.StdEncoding.DecodeString(b64Hash)
						if err != nil {
							continue
						}
						if bytes.Equal(peerHash[:], decoded) {
							return nil
						}
					}
				}
				return fmt.Errorf("pinned public key hash mismatch")
			}

			// Not a hash, so it must be a file path
			data, err := os.ReadFile(opts.PinnedPubKey)
			if err != nil {
				return fmt.Errorf("failed to read pinned public key file: %w", err)
			}

			var pinnedPubKey []byte
			block, _ := pem.Decode(data)
			if block != nil {
				if block.Type == "PUBLIC KEY" {
					pinnedPubKey = block.Bytes
				} else if block.Type == "CERTIFICATE" {
					cert, err := x509.ParseCertificate(block.Bytes)
					if err != nil {
						return fmt.Errorf("failed to parse certificate in pinned public key file: %w", err)
					}
					pinnedPubKey, err = x509.MarshalPKIXPublicKey(cert.PublicKey)
					if err != nil {
						return fmt.Errorf("failed to marshal pinned public key: %w", err)
					}
				} else {
					return fmt.Errorf("unsupported PEM block type: %s", block.Type)
				}
			} else {
				// Assume DER
				pinnedPubKey = data
			}

			if !bytes.Equal(peerPubKey, pinnedPubKey) {
				return fmt.Errorf("pinned public key mismatch")
			}
			return nil
		}
	}

	transport := &http.Transport{
		TLSClientConfig:       tlsConfig,
		DisableCompression:    !opts.Compressed,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   5 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
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
			for p := range strings.SplitSeq(noProxy, ",") {
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
	connectTimeout := time.Duration(opts.ConnectTmout * float64(time.Second))
	if connectTimeout == 0 {
		connectTimeout = 30 * time.Second
	}
	dialer := &net.Dialer{
		Timeout:   connectTimeout,
		KeepAlive: 30 * time.Second,
	}

	if opts.Interface != "" {
		localAddr, err := net.ResolveIPAddr("ip", opts.Interface)
		if err == nil {
			dialer.LocalAddr = &net.TCPAddr{IP: localAddr.IP}
		} else {
			// Try as interface name
			iface, err := net.InterfaceByName(opts.Interface)
			if err == nil {
				addrs, err := iface.Addrs()
				if err == nil && len(addrs) > 0 {
					if ipnet, ok := addrs[0].(*net.IPNet); ok {
						dialer.LocalAddr = &net.TCPAddr{IP: ipnet.IP}
					}
				}
			}
		}
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
	var rt http.RoundTripper = transport
	if opts.DigestAuth && opts.BasicAuth != "" {
		parts := strings.SplitN(opts.BasicAuth, ":", 2)
		username := parts[0]
		password := ""
		if len(parts) == 2 {
			password = parts[1]
		}
		rt = &digest.Transport{
			Username:  username,
			Password:  password,
			Transport: transport,
		}
	}

	client := &http.Client{
		Transport: rt,
	}
	if opts.MaxTime > 0 {
		client.Timeout = time.Duration(opts.MaxTime * float64(time.Second))
	} else if defTimeout := os.Getenv("KEMFORGE_DEFAULT_TIMEOUT"); defTimeout != "" {
		if d, err := time.ParseDuration(defTimeout); err == nil {
			client.Timeout = d
		}
	}

	// Follow redirects or not
	if !opts.FollowRedirs {
		client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		}
	} else {
		client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
			if opts.MaxRedirs > 0 && len(via) >= opts.MaxRedirs {
				return fmt.Errorf("maximum (%d) redirects followed", opts.MaxRedirs)
			}

			lastReq := via[len(via)-1]
			resp := req.Response // This might be nil in some Go versions during CheckRedirect? No, it's there.

			if resp != nil {
				// Handle --post301, --post302, --post303
				shouldPreservePOST := false
				if resp.StatusCode == 301 && opts.Post301 {
					shouldPreservePOST = true
				} else if resp.StatusCode == 302 && opts.Post302 {
					shouldPreservePOST = true
				} else if resp.StatusCode == 303 && opts.Post303 {
					shouldPreservePOST = true
				}

				if shouldPreservePOST && lastReq.Method == "POST" {
					req.Method = "POST"
					// We need to re-attach the body, but it might have been consumed.
					// Curl handles this by re-sending. In Go, we might need a GetBody function on the original request.
					if lastReq.GetBody != nil {
						req.Body, _ = lastReq.GetBody()
					}
				}
			}

			if opts.LocationTrusted {
				// Copy authorization header if it's the same host OR we trust it
				if auth := lastReq.Header.Get("Authorization"); auth != "" {
					req.Header.Set("Authorization", auth)
				}
			}

			return nil
		}
	}

	// Set client certificates
	if opts.CertFile != "" {
		cert, err := loadCertWithKey(opts.CertFile, opts.KeyFile, opts.Pass)
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

func loadCertWithKey(certFile, keyFile, password string) (tls.Certificate, error) {
	if keyFile == "" {
		keyFile = certFile
	}
	certPEM, err := os.ReadFile(certFile)
	if err != nil {
		return tls.Certificate{}, err
	}
	keyPEM, err := os.ReadFile(keyFile)
	if err != nil {
		return tls.Certificate{}, err
	}

	var decryptedKeyPEM []byte
	tmpPEM := keyPEM
	for {
		var block *pem.Block
		block, tmpPEM = pem.Decode(tmpPEM)
		if block == nil {
			break
		}
		if block.Type == "ENCRYPTED PRIVATE KEY" {
			// Modern PKCS#8 encrypted key
			key, err := pkcs8.ParsePKCS8PrivateKey(block.Bytes, []byte(password))
			if err != nil {
				return tls.Certificate{}, fmt.Errorf("failed to decrypt PKCS#8 private key: %v", err)
			}
			der, err := x509.MarshalPKCS8PrivateKey(key)
			if err != nil {
				return tls.Certificate{}, fmt.Errorf("failed to marshal private key: %v", err)
			}
			block = &pem.Block{Type: "PRIVATE KEY", Bytes: der}
		} else if block.Headers["DEK-Info"] != "" {
			// Legacy PEM encryption (RFC 1423)
			der, err := decryptLegacyPEMBlock(block, []byte(password))
			if err != nil {
				return tls.Certificate{}, fmt.Errorf("failed to decrypt legacy private key: %v", err)
			}
			block = &pem.Block{Type: block.Type, Bytes: der}
		}
		decryptedKeyPEM = append(decryptedKeyPEM, pem.EncodeToMemory(block)...)
	}

	if len(decryptedKeyPEM) == 0 {
		return tls.X509KeyPair(certPEM, keyPEM) // Fallback to original
	}

	return tls.X509KeyPair(certPEM, decryptedKeyPEM)
}

// decryptLegacyPEMBlock decrypts a legacy RFC 1423 encrypted PEM block.
// This replaces the deprecated x509.DecryptPEMBlock.
func decryptLegacyPEMBlock(block *pem.Block, password []byte) ([]byte, error) {
	dekInfo := block.Headers["DEK-Info"]
	if dekInfo == "" {
		return nil, fmt.Errorf("no DEK-Info header")
	}
	cipherName, ivHex, ok := strings.Cut(dekInfo, ",")
	if !ok {
		return nil, fmt.Errorf("malformed DEK-Info header")
	}
	ivBytes, err := hex.DecodeString(strings.TrimSpace(ivHex))
	if err != nil {
		return nil, fmt.Errorf("malformed IV in DEK-Info: %v", err)
	}

	var newCipher func([]byte) (cipher.Block, error)
	var keyLen int
	switch cipherName {
	case "DES-CBC":
		newCipher = des.NewCipher
		keyLen = 8
	case "DES-EDE3-CBC":
		newCipher = des.NewTripleDESCipher
		keyLen = 24
	case "AES-128-CBC":
		newCipher = aes.NewCipher
		keyLen = 16
	case "AES-192-CBC":
		newCipher = aes.NewCipher
		keyLen = 24
	case "AES-256-CBC":
		newCipher = aes.NewCipher
		keyLen = 32
	default:
		return nil, fmt.Errorf("unsupported PEM cipher: %s", cipherName)
	}

	// Derive key using MD5-based OpenSSL key derivation (EVP_BytesToKey with count=1)
	key := make([]byte, 0, keyLen)
	var prev []byte
	for len(key) < keyLen {
		h := md5.New()
		h.Write(prev)
		h.Write(password)
		h.Write(ivBytes[:8])
		prev = h.Sum(nil)
		key = append(key, prev...)
	}
	key = key[:keyLen]

	block2, err := newCipher(key)
	if err != nil {
		return nil, err
	}
	if len(block.Bytes)%block2.BlockSize() != 0 {
		return nil, fmt.Errorf("encrypted data is not a multiple of the block size")
	}
	data := make([]byte, len(block.Bytes))
	cbc := cipher.NewCBCDecrypter(block2, ivBytes)
	cbc.CryptBlocks(data, block.Bytes)

	// Remove PKCS#7 padding
	if len(data) == 0 {
		return nil, fmt.Errorf("empty decrypted data")
	}
	padLen := int(data[len(data)-1])
	if padLen < 1 || padLen > block2.BlockSize() || padLen > len(data) {
		return nil, fmt.Errorf("invalid padding")
	}
	for _, b := range data[len(data)-padLen:] {
		if int(b) != padLen {
			return nil, fmt.Errorf("invalid padding")
		}
	}
	return data[:len(data)-padLen], nil
}
