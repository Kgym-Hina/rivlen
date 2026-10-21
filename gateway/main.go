package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/skip2/go-qrcode"
)

//go:embed web/index.html
var webFiles embed.FS

const (
	maxRequestBytes = 64 << 20
	inviteLifetime  = 10 * time.Minute
)

type config struct {
	listenAddr      string
	nodeRedURL      *url.URL
	nodeRedAuthMode string
	publicURL       string
	dataFile        string
	pairingPassword string
	nodeRedToken    string
	nodeRedUsername string
	nodeRedPassword string
	tlsCertFile     string
	tlsKeyFile      string
}

type pairingFile struct {
	Version    int       `json:"version"`
	GatewayID  string    `json:"gatewayId"`
	GatewayURL string    `json:"gatewayUrl"`
	InviteID   string    `json:"inviteId"`
	ExpiresAt  time.Time `json:"expiresAt"`
}

type device struct {
	ID             string     `json:"id"`
	Name           string     `json:"name"`
	Role           string     `json:"role"`
	CreatedAt      time.Time  `json:"createdAt"`
	LastAccessedAt *time.Time `json:"lastAccessedAt"`
}

type storedDevice struct {
	Device    device `json:"device"`
	TokenHash string `json:"tokenHash"`
}

type gatewayState struct {
	GatewayID string         `json:"gatewayId"`
	Devices   []storedDevice `json:"devices"`
}

type store struct {
	mu    sync.Mutex
	path  string
	state gatewayState
}

type invite struct {
	file    pairingFile
	pending bool
}

type rateWindow struct {
	started time.Time
	count   int
}

type rateLimiter struct {
	mu      sync.Mutex
	clients map[string]rateWindow
}

type server struct {
	cfg          config
	passwordHash [sha256.Size]byte
	store        *store
	client       *http.Client
	inviteMu     sync.Mutex
	invites      map[string]*invite
	limiter      rateLimiter
	tokenMu      sync.Mutex
	adminToken   string
	tokenExpiry  time.Time
}

func main() {
	cfg, err := readConfig()
	if err != nil {
		log.Fatal(err)
	}
	s, err := newServer(cfg)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("Rivlen Gateway listening on %s", cfg.listenAddr)
	if cfg.publicURL != "" {
		log.Printf("Public gateway URL: %s", strings.TrimRight(cfg.publicURL, "/"))
	}
	httpServer := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           s.routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       2 * time.Minute,
		WriteTimeout:      90 * time.Second,
		IdleTimeout:       2 * time.Minute,
		MaxHeaderBytes:    1 << 20,
	}
	var serveErr error
	if cfg.tlsCertFile != "" {
		log.Printf("Serving HTTPS on %s", cfg.listenAddr)
		serveErr = httpServer.ListenAndServeTLS(cfg.tlsCertFile, cfg.tlsKeyFile)
	} else {
		serveErr = httpServer.ListenAndServe()
	}
	if serveErr != nil && !errors.Is(serveErr, http.ErrServerClosed) {
		log.Fatal(serveErr)
	}
}

func readConfig() (config, error) {
	listen := env("RIVLEN_GATEWAY_LISTEN", "127.0.0.1:8787")
	nodeURL := env("RIVLEN_NODE_RED_URL", "http://127.0.0.1:1880")
	nodeRedAuthMode := env("RIVLEN_NODE_RED_AUTH_MODE", "admin")
	if nodeRedAuthMode != "admin" && nodeRedAuthMode != "basic" {
		return config{}, errors.New("RIVLEN_NODE_RED_AUTH_MODE must be admin or basic")
	}
	parsedNodeURL, err := url.Parse(nodeURL)
	if err != nil || !parsedNodeURL.IsAbs() || parsedNodeURL.Host == "" || (parsedNodeURL.Scheme != "http" && parsedNodeURL.Scheme != "https") || parsedNodeURL.User != nil || parsedNodeURL.RawQuery != "" || parsedNodeURL.Fragment != "" {
		return config{}, errors.New("RIVLEN_NODE_RED_URL must be an HTTP or HTTPS Node-RED base URL without credentials, query, or fragment")
	}
	password := os.Getenv("RIVLEN_PAIRING_PASSWORD")
	if len([]rune(password)) < 12 {
		return config{}, errors.New("set RIVLEN_PAIRING_PASSWORD to a custom password of at least 12 characters")
	}
	username := os.Getenv("RIVLEN_NODE_RED_USERNAME")
	adminPassword := os.Getenv("RIVLEN_NODE_RED_PASSWORD")
	if (username == "") != (adminPassword == "") {
		return config{}, errors.New("set both RIVLEN_NODE_RED_USERNAME and RIVLEN_NODE_RED_PASSWORD, or neither")
	}
	nodeRedToken := os.Getenv("RIVLEN_NODE_RED_TOKEN")
	if nodeRedAuthMode == "admin" && username != "" && nodeRedToken != "" {
		return config{}, errors.New("configure either RIVLEN_NODE_RED_TOKEN or Node-RED username/password, not both")
	}
	if nodeRedAuthMode == "basic" && (username == "" || nodeRedToken != "") {
		return config{}, errors.New("basic auth requires Node-RED username/password and cannot be combined with RIVLEN_NODE_RED_TOKEN")
	}
	tlsCert := os.Getenv("RIVLEN_TLS_CERT")
	tlsKey := os.Getenv("RIVLEN_TLS_KEY")
	if (tlsCert == "") != (tlsKey == "") {
		return config{}, errors.New("set both RIVLEN_TLS_CERT and RIVLEN_TLS_KEY, or neither")
	}
	return config{
		listenAddr:      listen,
		nodeRedURL:      parsedNodeURL,
		nodeRedAuthMode: nodeRedAuthMode,
		publicURL:       strings.TrimRight(os.Getenv("RIVLEN_PUBLIC_URL"), "/"),
		dataFile:        env("RIVLEN_DATA_FILE", "./data/gateway.json"),
		pairingPassword: password,
		nodeRedToken:    nodeRedToken,
		nodeRedUsername: username,
		nodeRedPassword: adminPassword,
		tlsCertFile:     tlsCert,
		tlsKeyFile:      tlsKey,
	}, nil
}

func newServer(cfg config) (*server, error) {
	if cfg.nodeRedURL == nil {
		return nil, errors.New("Node-RED URL is required")
	}
	if cfg.publicURL != "" {
		if _, err := validatePublicURL(cfg.publicURL); err != nil {
			return nil, fmt.Errorf("RIVLEN_PUBLIC_URL: %w", err)
		}
	}
	state, err := openStore(cfg.dataFile)
	if err != nil {
		return nil, err
	}
	s := &server{
		cfg:          cfg,
		passwordHash: sha256.Sum256([]byte(cfg.pairingPassword)),
		store:        state,
		client: &http.Client{
			Timeout: 45 * time.Second,
			CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
		invites: make(map[string]*invite),
		limiter: rateLimiter{clients: make(map[string]rateWindow)},
	}
	return s, nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleHome)
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/api/v1/pairing-files", s.handlePairingFile)
	mux.HandleFunc("/api/v1/pair", s.handlePair)
	mux.HandleFunc("/api/v1/devices", s.handleDevices)
	mux.HandleFunc("/api/v1/devices/", s.handleDevice)
	mux.HandleFunc("/api/node-red/flows", s.handleFlows)
	return securityHeaders(mux)
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
		next.ServeHTTP(w, r)
	})
}

func (s *server) handleHome(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	page, err := webFiles.ReadFile("web/index.html")
	if err != nil {
		http.Error(w, "Gateway page unavailable", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write(page)
}

func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handlePairingFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodPost)
		return
	}
	if !s.sameOrigin(r) {
		writeError(w, http.StatusForbidden, "Cross-origin request rejected")
		return
	}
	if !s.limiter.allow(clientIP(r)) {
		writeError(w, http.StatusTooManyRequests, "Too many pairing attempts; try again later")
		return
	}
	var request struct {
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &request, 4096); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request")
		return
	}
	if !s.validPassword(request.Password) {
		writeError(w, http.StatusUnauthorized, "Pairing password is incorrect")
		return
	}
	baseURL, err := s.pairingBaseURL(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	inviteID, err := randomID(18)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Could not create a pairing file")
		return
	}
	file := pairingFile{
		Version:    1,
		GatewayID:  s.store.gatewayID(),
		GatewayURL: baseURL,
		InviteID:   inviteID,
		ExpiresAt:  time.Now().UTC().Add(inviteLifetime),
	}
	serialized, err := json.Marshal(file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Could not create a pairing file")
		return
	}
	qrPNG, err := qrcode.Encode(string(serialized), qrcode.Medium, 360)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Could not create a pairing QR code")
		return
	}
	s.inviteMu.Lock()
	s.pruneInvitesLocked()
	s.invites[inviteID] = &invite{file: file}
	s.inviteMu.Unlock()
	writeJSON(w, http.StatusCreated, map[string]any{
		"pairingFile":   file,
		"qrCodeDataUrl": "data:image/png;base64," + base64.StdEncoding.EncodeToString(qrPNG),
	})
}

func (s *server) handlePair(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodPost)
		return
	}
	if !s.sameOrigin(r) {
		writeError(w, http.StatusForbidden, "Cross-origin request rejected")
		return
	}
	if !s.limiter.allow(clientIP(r)) {
		writeError(w, http.StatusTooManyRequests, "Too many pairing attempts; try again later")
		return
	}
	var request struct {
		PairingFile pairingFile `json:"pairingFile"`
		Password    string      `json:"password"`
		DeviceName  string      `json:"deviceName"`
	}
	if err := decodeJSON(w, r, &request, 16<<10); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid pairing file")
		return
	}
	if !s.validPassword(request.Password) {
		writeError(w, http.StatusUnauthorized, "Pairing password is incorrect")
		return
	}
	if request.PairingFile.Version != 1 || request.PairingFile.GatewayID != s.store.gatewayID() || request.PairingFile.InviteID == "" {
		writeError(w, http.StatusBadRequest, "This pairing file belongs to a different gateway")
		return
	}
	if !request.PairingFile.ExpiresAt.After(time.Now()) {
		writeError(w, http.StatusGone, "This pairing file has expired")
		return
	}
	if err := s.claimInvite(request.PairingFile); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}
	completed := false
	defer func() {
		if !completed {
			s.releaseInvite(request.PairingFile.InviteID)
		}
	}()

	probe, err := s.nodeRedRequest(r.Context(), http.MethodGet, nil, nil)
	if err != nil {
		writeError(w, http.StatusBadGateway, "The gateway could not connect to Node-RED")
		return
	}
	probe.Body.Close()
	if probe.StatusCode != http.StatusOK {
		writeError(w, http.StatusBadGateway, fmt.Sprintf("Node-RED returned HTTP %d while checking access", probe.StatusCode))
		return
	}

	token, err := randomToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Could not authorize this device")
		return
	}
	name := strings.TrimSpace(request.DeviceName)
	if name == "" {
		name = "Rivlen device"
	}
	if len([]rune(name)) > 64 {
		writeError(w, http.StatusBadRequest, "Device name must be 64 characters or fewer")
		return
	}
	created, err := s.store.addDevice(name, token)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Could not save device authorization")
		return
	}
	s.inviteMu.Lock()
	delete(s.invites, request.PairingFile.InviteID)
	s.inviteMu.Unlock()
	completed = true
	writeJSON(w, http.StatusCreated, map[string]any{
		"device":      created,
		"accessToken": token,
	})
}

func (s *server) handleDevices(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w, http.MethodGet)
		return
	}
	current, ok := s.authorize(w, r)
	if !ok {
		return
	}
	devices := s.store.devices()
	writeJSON(w, http.StatusOK, map[string]any{
		"devices":       devices,
		"currentDevice": current.ID,
		"canManage":     current.Role == "owner",
	})
}

func (s *server) handleDevice(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		methodNotAllowed(w, http.MethodDelete)
		return
	}
	current, ok := s.authorize(w, r)
	if !ok {
		return
	}
	if current.Role != "owner" {
		writeError(w, http.StatusForbidden, "Only the owner device can revoke authorizations")
		return
	}
	deviceID := strings.TrimPrefix(r.URL.Path, "/api/v1/devices/")
	decodedID, err := url.PathUnescape(deviceID)
	if err != nil || decodedID == "" || strings.Contains(decodedID, "/") {
		writeError(w, http.StatusBadRequest, "Invalid device ID")
		return
	}
	if decodedID == current.ID {
		writeError(w, http.StatusConflict, "The owner device cannot revoke its own authorization")
		return
	}
	if err := s.store.revoke(decodedID); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			writeError(w, http.StatusNotFound, "Device not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "Could not save device changes")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handleFlows(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodPost {
		methodNotAllowed(w, http.MethodGet+", "+http.MethodPost)
		return
	}
	if _, ok := s.authorize(w, r); !ok {
		return
	}
	var body []byte
	if r.Method == http.MethodPost {
		var err error
		body, err = io.ReadAll(http.MaxBytesReader(w, r.Body, maxRequestBytes))
		if err != nil {
			writeError(w, http.StatusRequestEntityTooLarge, "Flow request is too large")
			return
		}
	}
	allowed := make(http.Header)
	for _, name := range []string{"Accept", "Content-Type", "Node-RED-API-Version", "Node-RED-Deployment-Type"} {
		if value := r.Header.Get(name); value != "" {
			allowed.Set(name, value)
		}
	}
	response, err := s.nodeRedRequest(r.Context(), r.Method, allowed, body)
	if err != nil {
		writeError(w, http.StatusBadGateway, "Could not reach Node-RED")
		return
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, maxRequestBytes+1))
	if err != nil {
		writeError(w, http.StatusBadGateway, "Could not read the Node-RED response")
		return
	}
	if int64(len(responseBody)) > maxRequestBytes {
		writeError(w, http.StatusBadGateway, "Node-RED response is too large")
		return
	}
	for _, name := range []string{"Content-Type", "ETag", "Node-RED-API-Version"} {
		if value := response.Header.Get(name); value != "" {
			w.Header().Set(name, value)
		}
	}
	w.WriteHeader(response.StatusCode)
	_, _ = w.Write(responseBody)
}

func (s *server) authorize(w http.ResponseWriter, r *http.Request) (device, bool) {
	value := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(value, "Bearer ") || len(value) <= len("Bearer ") {
		writeError(w, http.StatusUnauthorized, "Device authorization is required")
		return device{}, false
	}
	current, err := s.store.authenticate(strings.TrimSpace(strings.TrimPrefix(value, "Bearer ")))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			writeError(w, http.StatusUnauthorized, "Device authorization is invalid or revoked")
		} else {
			writeError(w, http.StatusInternalServerError, "Could not update device access time")
		}
		return device{}, false
	}
	return current, true
}

func (s *server) validPassword(value string) bool {
	actual := sha256.Sum256([]byte(value))
	return subtle.ConstantTimeCompare(actual[:], s.passwordHash[:]) == 1
}

func (s *server) sameOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	return err == nil && u.Host != "" && strings.EqualFold(u.Host, r.Host) && (u.Scheme == "http" || u.Scheme == "https")
}

func (s *server) pairingBaseURL(r *http.Request) (string, error) {
	if s.cfg.publicURL != "" {
		return validatePublicURL(s.cfg.publicURL)
	}
	proto := "http"
	if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
		proto = "https"
	}
	return validatePublicURL(proto + "://" + r.Host)
}

func validatePublicURL(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || !u.IsAbs() || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return "", errors.New("use a complete public URL without credentials, query, or fragment")
	}
	if u.Scheme != "https" && !isPrivateHost(u.Hostname()) {
		return "", errors.New("public pairing requires HTTPS; HTTP is allowed only for localhost or a private LAN address")
	}
	u.Path = strings.TrimRight(u.Path, "/")
	u.RawPath = ""
	return u.String(), nil
}

func isPrivateHost(host string) bool {
	if strings.EqualFold(host, "localhost") || strings.HasSuffix(strings.ToLower(host), ".local") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && (ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast())
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func (l *rateLimiter) allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	for ip, window := range l.clients {
		if now.Sub(window.started) > time.Minute {
			delete(l.clients, ip)
		}
	}
	window := l.clients[key]
	if window.started.IsZero() || now.Sub(window.started) > time.Minute {
		window = rateWindow{started: now}
	}
	window.count++
	l.clients[key] = window
	return window.count <= 10
}

func (s *server) claimInvite(file pairingFile) error {
	s.inviteMu.Lock()
	defer s.inviteMu.Unlock()
	s.pruneInvitesLocked()
	known := s.invites[file.InviteID]
	if known == nil || !samePairingFile(known.file, file) {
		return errors.New("pairing file is invalid or has already been used")
	}
	if known.pending {
		return errors.New("pairing file is already being used")
	}
	known.pending = true
	return nil
}

func (s *server) releaseInvite(id string) {
	s.inviteMu.Lock()
	defer s.inviteMu.Unlock()
	if known := s.invites[id]; known != nil {
		known.pending = false
	}
}

func (s *server) pruneInvitesLocked() {
	now := time.Now()
	for id, known := range s.invites {
		if !known.file.ExpiresAt.After(now) {
			delete(s.invites, id)
		}
	}
}

func samePairingFile(a, b pairingFile) bool {
	return a.Version == b.Version && a.GatewayID == b.GatewayID && a.GatewayURL == b.GatewayURL && a.InviteID == b.InviteID && a.ExpiresAt.Equal(b.ExpiresAt)
}

func (s *server) nodeRedRequest(ctx context.Context, method string, headers http.Header, body []byte) (*http.Response, error) {
	response, err := s.doNodeRed(ctx, method, headers, body, false)
	if err != nil || s.cfg.nodeRedAuthMode != "admin" || response.StatusCode != http.StatusUnauthorized || s.cfg.nodeRedUsername == "" {
		return response, err
	}
	response.Body.Close()
	return s.doNodeRed(ctx, method, headers, body, true)
}

func (s *server) doNodeRed(ctx context.Context, method string, headers http.Header, body []byte, refresh bool) (*http.Response, error) {
	token := ""
	if s.cfg.nodeRedAuthMode == "admin" {
		var err error
		token, err = s.nodeRedAuthToken(ctx, refresh)
		if err != nil {
			return nil, err
		}
	}
	target := *s.cfg.nodeRedURL
	prefix := strings.TrimRight(target.Path, "/")
	target.Path = prefix + "/flows"
	target.RawPath = ""
	target.RawQuery = ""
	target.Fragment = ""
	request, err := http.NewRequestWithContext(ctx, method, target.String(), strings.NewReader(string(body)))
	if err != nil {
		return nil, err
	}
	for key, values := range headers {
		for _, value := range values {
			request.Header.Add(key, value)
		}
	}
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	} else if s.cfg.nodeRedAuthMode == "basic" {
		request.SetBasicAuth(s.cfg.nodeRedUsername, s.cfg.nodeRedPassword)
	}
	return s.client.Do(request)
}

func (s *server) nodeRedAuthToken(ctx context.Context, refresh bool) (string, error) {
	if s.cfg.nodeRedToken != "" {
		return s.cfg.nodeRedToken, nil
	}
	if s.cfg.nodeRedUsername == "" {
		return "", nil
	}
	s.tokenMu.Lock()
	defer s.tokenMu.Unlock()
	if refresh {
		s.adminToken = ""
		s.tokenExpiry = time.Time{}
	}
	if s.adminToken != "" && time.Now().Before(s.tokenExpiry) {
		return s.adminToken, nil
	}
	endpoint := *s.cfg.nodeRedURL
	endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/auth/token"
	endpoint.RawPath, endpoint.RawQuery, endpoint.Fragment = "", "", ""
	credentials, _ := json.Marshal(map[string]string{
		"client_id":  "node-red-admin",
		"grant_type": "password",
		"scope":      "*",
		"username":   s.cfg.nodeRedUsername,
		"password":   s.cfg.nodeRedPassword,
	})
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint.String(), strings.NewReader(string(credentials)))
	if err != nil {
		return "", err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := s.client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("Node-RED authentication returned HTTP %d", response.StatusCode)
	}
	var result struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&result); err != nil || result.AccessToken == "" {
		return "", errors.New("Node-RED did not return an access token")
	}
	lifetime := time.Duration(result.ExpiresIn) * time.Second
	if lifetime <= 0 {
		lifetime = time.Hour
	}
	if lifetime > 30*time.Second {
		lifetime -= 30 * time.Second
	}
	s.adminToken = result.AccessToken
	s.tokenExpiry = time.Now().Add(lifetime)
	return s.adminToken, nil
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any, limit int64) error {
	if !strings.HasPrefix(strings.ToLower(r.Header.Get("Content-Type")), "application/json") {
		return errors.New("expected application/json")
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("expected one JSON value")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func methodNotAllowed(w http.ResponseWriter, methods string) {
	w.Header().Set("Allow", methods)
	writeError(w, http.StatusMethodNotAllowed, "Method not allowed")
}

func randomID(size int) (string, error) {
	bytes := make([]byte, size)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func randomToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func openStore(path string) (*store, error) {
	if path == "" {
		return nil, errors.New("RIVLEN_DATA_FILE must not be empty")
	}
	result := &store{path: path, state: gatewayState{Devices: []storedDevice{}}}
	contents, err := os.ReadFile(path)
	if err == nil {
		if err := json.Unmarshal(contents, &result.state); err != nil {
			return nil, fmt.Errorf("read gateway data file: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("read gateway data file: %w", err)
	}
	if result.state.Devices == nil {
		result.state.Devices = []storedDevice{}
	}
	if result.state.GatewayID == "" {
		id, err := randomID(16)
		if err != nil {
			return nil, err
		}
		result.state.GatewayID = id
		if err := result.persistLocked(); err != nil {
			return nil, err
		}
	}
	return result, nil
}

func (s *store) persistLocked() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0700); err != nil {
		return fmt.Errorf("create gateway data directory: %w", err)
	}
	serialized, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return err
	}
	temporary := s.path + ".tmp"
	if err := os.WriteFile(temporary, serialized, 0600); err != nil {
		return fmt.Errorf("write gateway data file: %w", err)
	}
	if err := os.Rename(temporary, s.path); err != nil {
		_ = os.Remove(temporary)
		return fmt.Errorf("replace gateway data file: %w", err)
	}
	return nil
}

func (s *store) gatewayID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state.GatewayID
}

func (s *store) addDevice(name, token string) (device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id, err := randomID(16)
	if err != nil {
		return device{}, err
	}
	role := "device"
	if len(s.state.Devices) == 0 {
		role = "owner"
	}
	created := device{ID: id, Name: name, Role: role, CreatedAt: time.Now().UTC()}
	hash := sha256.Sum256([]byte(token))
	s.state.Devices = append(s.state.Devices, storedDevice{Device: created, TokenHash: hex.EncodeToString(hash[:])})
	if err := s.persistLocked(); err != nil {
		s.state.Devices = s.state.Devices[:len(s.state.Devices)-1]
		return device{}, err
	}
	return created, nil
}

func (s *store) authenticate(token string) (device, error) {
	hash := sha256.Sum256([]byte(token))
	encoded := hex.EncodeToString(hash[:])
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.state.Devices {
		if subtle.ConstantTimeCompare([]byte(s.state.Devices[i].TokenHash), []byte(encoded)) != 1 {
			continue
		}
		now := time.Now().UTC()
		s.state.Devices[i].Device.LastAccessedAt = &now
		if err := s.persistLocked(); err != nil {
			return device{}, err
		}
		return s.state.Devices[i].Device, nil
	}
	return device{}, os.ErrNotExist
}

func (s *store) devices() []device {
	s.mu.Lock()
	defer s.mu.Unlock()
	result := make([]device, 0, len(s.state.Devices))
	for _, item := range s.state.Devices {
		result = append(result, item.Device)
	}
	return result
}

func (s *store) revoke(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, item := range s.state.Devices {
		if item.Device.ID != id {
			continue
		}
		previous := append([]storedDevice(nil), s.state.Devices...)
		s.state.Devices = append(s.state.Devices[:i], s.state.Devices[i+1:]...)
		if err := s.persistLocked(); err != nil {
			s.state.Devices = previous
			return err
		}
		return nil
	}
	return os.ErrNotExist
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
