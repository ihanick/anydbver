package versionfetch

import (
	"testing"
)

func TestExtractBaseVersion(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{
			input:    "17.0-1PGDG.rhel8",
			expected: "17.0-1",
		},
		{
			input:    "17.0-2PGDG.rhel8",
			expected: "17.0-2",
		},
		{
			input:    "17.1-1PGDG.rhel8",
			expected: "17.1-1",
		},
		{
			input:    "8.0.33-1.el8",
			expected: "8.0.33-1",
		},
		{
			input:    "13.7-1.el8",
			expected: "13.7-1",
		},
		{
			input:    "1.20.1-1",
			expected: "1.20.1-1",
		},
	}

	for _, test := range tests {
		result := extractBaseVersion(test.input)
		if result != test.expected {
			t.Errorf("extractBaseVersion(%s) = %s, expected %s", test.input, result, test.expected)
		}
	}
}

func TestGetPostgreSQLRepoURL(t *testing.T) {
	tests := []struct {
		program  string
		osver    string
		arch     string
		expected string
	}{
		{
			program:  "postgresql",
			osver:    "el6",
			arch:     "x86_64",
			expected: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-6-x86_64/pgdg-redhat-repo-latest.noarch.rpm",
		},
		{
			program:  "postgresql",
			osver:    "el6",
			arch:     "aarch64",
			expected: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-6-aarch64/pgdg-redhat-repo-latest.noarch.rpm",
		},
		{
			program:  "postgresql",
			osver:    "el7",
			arch:     "x86_64",
			expected: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm",
		},
		{
			program:  "postgresql",
			osver:    "el8",
			arch:     "aarch64",
			expected: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-aarch64/pgdg-redhat-repo-latest.noarch.rpm",
		},
		{
			program:  "postgresql",
			osver:    "el9",
			arch:     "x86_64",
			expected: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm",
		},
		{
			program:  "postgresql",
			osver:    "el10",
			arch:     "aarch64",
			expected: "https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-aarch64/pgdg-redhat-repo-latest.noarch.rpm",
		},
		{
			program:  "mariadb",
			osver:    "el8",
			arch:     "x86_64",
			expected: "",
		},
		{
			program:  "postgresql",
			osver:    "unknown",
			arch:     "x86_64",
			expected: "",
		},
		{
			program:  "postgresql",
			osver:    "el8",
			arch:     "unknown",
			expected: "",
		},
	}

	for _, test := range tests {
		result := getPostgreSQLRepoURL(test.program, test.osver, test.arch)
		if result != test.expected {
			t.Errorf("getPostgreSQLRepoURL(%s, %s, %s) = %s, expected %s", test.program, test.osver, test.arch, result, test.expected)
		}
	}
}

func TestExtractMajorVersion(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{
			input:    "17.0-1",
			expected: "17",
		},
		{
			input:    "16.10-1",
			expected: "16",
		},
		{
			input:    "15.4-1",
			expected: "15",
		},
		{
			input:    "14.9-1",
			expected: "14",
		},
		{
			input:    "13.12-1",
			expected: "13",
		},
		{
			input:    "12.16-1",
			expected: "12",
		},
		{
			input:    "11.21-1",
			expected: "11",
		},
		{
			input:    "10.24-1",
			expected: "10",
		},
		{
			input:    "9.6.25-1",
			expected: "9",
		},
		{
			input:    "8.4.22-1",
			expected: "8",
		},
		{
			input:    "17",
			expected: "",
		},
		{
			input:    "",
			expected: "",
		},
	}

	for _, test := range tests {
		result := extractMajorVersion(test.input)
		if result != test.expected {
			t.Errorf("extractMajorVersion(%s) = %s, expected %s", test.input, result, test.expected)
		}
	}
}

func TestGetPostgreSQLSystemdService(t *testing.T) {
	tests := []struct {
		program     string
		baseVersion string
		expected    string
	}{
		{
			program:     "postgresql",
			baseVersion: "17.0-1",
			expected:    "postgresql-17",
		},
		{
			program:     "postgresql",
			baseVersion: "16.10-1",
			expected:    "postgresql-16",
		},
		{
			program:     "postgresql",
			baseVersion: "15.4-1",
			expected:    "postgresql-15",
		},
		{
			program:     "postgresql",
			baseVersion: "14.9-1",
			expected:    "postgresql-14",
		},
		{
			program:     "postgresql",
			baseVersion: "13.12-1",
			expected:    "postgresql-13",
		},
		{
			program:     "postgresql",
			baseVersion: "12.16-1",
			expected:    "postgresql-12",
		},
		{
			program:     "postgresql",
			baseVersion: "11.21-1",
			expected:    "postgresql-11",
		},
		{
			program:     "postgresql",
			baseVersion: "10.24-1",
			expected:    "postgresql-10",
		},
		{
			program:     "postgresql",
			baseVersion: "9.6.25-1",
			expected:    "postgresql-9",
		},
		{
			program:     "postgresql",
			baseVersion: "8.4.22-1",
			expected:    "postgresql-8",
		},
		{
			program:     "postgresql",
			baseVersion: "17",
			expected:    "postgresql",
		},
		{
			program:     "mariadb",
			baseVersion: "10.11.4-1",
			expected:    "mariadb",
		},
		{
			program:     "unknown",
			baseVersion: "17.0-1",
			expected:    "mariadb",
		},
	}

	for _, test := range tests {
		result := getPostgreSQLSystemdService(test.program, test.baseVersion)
		if result != test.expected {
			t.Errorf("getPostgreSQLSystemdService(%s, %s) = %s, expected %s", test.program, test.baseVersion, result, test.expected)
		}
	}
}
