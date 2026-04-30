package test

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestValidateInteractiveIngressSetupPageWithRetryDelay(t *testing.T) {
	t.Run("passes on setup page", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = w.Write([]byte("<html><h1>Welcome to RunsOn</h1><button>Register GitHub App</button></html>"))
		}))
		defer server.Close()

		err := validateInteractiveIngressSetupPageWithRetryDelay(server.URL, 1, 0, nil)
		require.NoError(t, err)
	})

	t.Run("fails on unexpected status", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "setup pending", http.StatusServiceUnavailable)
		}))
		defer server.Close()

		err := validateInteractiveIngressSetupPageWithRetryDelay(server.URL, 1, 0, nil)
		require.ErrorContains(t, err, "unexpected status code: 503")
	})

	t.Run("fails when setup markers are missing", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = w.Write([]byte("<html><h1>RunsOn</h1></html>"))
		}))
		defer server.Close()

		err := validateInteractiveIngressSetupPageWithRetryDelay(server.URL, 1, 0, nil)
		require.ErrorContains(t, err, "setup page missing expected marker")
	})
}

func TestValidateConfiguredIngressReadinessWithRetryDelay(t *testing.T) {
	t.Run("passes on 200", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))
		defer server.Close()

		err := validateConfiguredIngressReadinessWithRetryDelay(server.URL, 1, 0, nil)
		require.NoError(t, err)
	})

	t.Run("fails on 503", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusServiceUnavailable)
		}))
		defer server.Close()

		err := validateConfiguredIngressReadinessWithRetryDelay(server.URL, 1, 0, nil)
		require.ErrorContains(t, err, "unexpected status code: 503")
	})

	t.Run("retries until ready", func(t *testing.T) {
		attempts := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			attempts++
			if attempts < 2 {
				w.WriteHeader(http.StatusServiceUnavailable)
				return
			}
			w.WriteHeader(http.StatusOK)
		}))
		defer server.Close()

		err := validateConfiguredIngressReadinessWithRetryDelay(server.URL, 2, time.Millisecond, nil)
		require.NoError(t, err)
		require.Equal(t, 2, attempts)
	})
}
