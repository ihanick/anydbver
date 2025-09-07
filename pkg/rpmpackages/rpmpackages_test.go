package rpmpackages

import (
	"strings"
	"testing"
)

func TestFilterPackagesByRegex(t *testing.T) {
	// Create test packages
	packages := []PackageEntry{
		{
			Fields: map[string]string{
				"Name":         "mysql-server",
				"FullVersion":  "8.0.33-1.el8",
				"Architecture": "x86_64",
			},
		},
		{
			Fields: map[string]string{
				"Name":         "mysql-client",
				"FullVersion":  "8.0.33-1.el8",
				"Architecture": "x86_64",
			},
		},
		{
			Fields: map[string]string{
				"Name":         "postgresql-server",
				"FullVersion":  "13.7-1.el8",
				"Architecture": "x86_64",
			},
		},
		{
			Fields: map[string]string{
				"Name":         "nginx",
				"FullVersion":  "1.20.1-1.el8",
				"Architecture": "x86_64",
			},
		},
	}

	// Test filtering for MySQL packages
	result := FilterPackagesByRegex(packages, "mysql.*")

	expectedCount := 2
	if len(result) != expectedCount {
		t.Errorf("Expected %d packages, got %d", expectedCount, len(result))
	}

	// Check if mysql-server is in results
	if versions, exists := result["mysql-server"]; !exists || len(versions) != 1 {
		t.Errorf("mysql-server not found or wrong version count")
	}

	// Check if mysql-client is in results
	if versions, exists := result["mysql-client"]; !exists || len(versions) != 1 {
		t.Errorf("mysql-client not found or wrong version count")
	}

	// Test filtering for PostgreSQL packages
	result = FilterPackagesByRegex(packages, "postgresql.*")

	expectedCount = 1
	if len(result) != expectedCount {
		t.Errorf("Expected %d packages, got %d", expectedCount, len(result))
	}

	// Check if postgresql-server is in results
	if versions, exists := result["postgresql-server"]; !exists || len(versions) != 1 {
		t.Errorf("postgresql-server not found or wrong version count")
	}
}

func TestGetRepomdURL(t *testing.T) {
	tests := []struct {
		baseURL  string
		expected string
	}{
		{
			baseURL:  "https://repo.mysql.com/yum/mysql-8.0-el/8",
			expected: "https://repo.mysql.com/yum/mysql-8.0-el/8/repodata/repomd.xml",
		},
		{
			baseURL:  "https://repo.mysql.com/yum/mysql-8.0-el/8/",
			expected: "https://repo.mysql.com/yum/mysql-8.0-el/8/repodata/repomd.xml",
		},
	}

	for _, test := range tests {
		result := GetRepomdURL(test.baseURL)
		if result != test.expected {
			t.Errorf("GetRepomdURL(%s) = %s, expected %s", test.baseURL, result, test.expected)
		}
	}
}

func TestCompressionDetection(t *testing.T) {
	tests := []struct {
		url        string
		expectGzip bool
		expectZstd bool
	}{
		{
			url:        "https://example.com/primary.xml.gz",
			expectGzip: true,
			expectZstd: false,
		},
		{
			url:        "https://example.com/primary.xml.zst",
			expectGzip: false,
			expectZstd: true,
		},
		{
			url:        "https://example.com/primary.xml",
			expectGzip: false,
			expectZstd: false,
		},
	}

	for _, test := range tests {
		isGzipped := strings.HasSuffix(test.url, ".gz")
		isZstd := strings.HasSuffix(test.url, ".zst")

		if isGzipped != test.expectGzip {
			t.Errorf("Gzip detection for %s: got %v, expected %v", test.url, isGzipped, test.expectGzip)
		}
		if isZstd != test.expectZstd {
			t.Errorf("Zstd detection for %s: got %v, expected %v", test.url, isZstd, test.expectZstd)
		}
	}
}
