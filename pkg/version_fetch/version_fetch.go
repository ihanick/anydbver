package versionfetch

import (
	"database/sql"
	"fmt"
	"strings"

	"github.com/zelmario/anydbver/pkg/debianpackages"
	"github.com/zelmario/anydbver/pkg/rpmpackages"
	_ "modernc.org/sqlite"
)

func VersionFetch(program string, dbFile string) error {
	progUrls, err := getProgramUrls(program, dbFile)
	if err != nil {
		return fmt.Errorf("can't fetch versions for program: %s %w", program, err)
	}

	for _, pu := range progUrls {
		if strings.HasSuffix(pu.url, "/Packages") || strings.HasSuffix(pu.url, "/Packages.gz") {
			if err := VersionFetchFromDebianPackages(dbFile, program, pu); err != nil {
				return fmt.Errorf("can't get versions from debian packages file %w", err)
			}
		} else {
			if err := VersionFetchFromRpmPackages(dbFile, program, pu); err != nil {
				return fmt.Errorf("can't get versions from RPM packages file %w", err)
			}
		}

	}

	return nil
}

func VersionFetchFromDebianPackages(dbFile string, program string, pu programVersionSource) error {
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	packages, err := debianpackages.ParsePackagesFromURL(pu.url)
	if err != nil {
		return fmt.Errorf("error fetching or parsing Packages file: %w", err)
	}

	//
	// Regex to match package names like postgresql-[0-9.]+
	versionsByPackage := debianpackages.FilterPackagesByRegex(packages, pu.pattern)

	// Output the filtered versions
	versions_cnt := 0
	for pkgName, versions := range versionsByPackage {
		for _, version := range versions {
			versions_cnt += len(versions)
			switch program {
			case "postgresql":
				query := "REPLACE INTO postgresql_version VALUES(?,?,?,?,?,?,?,?,?)"
				if _, err := db.Exec(query, version, pu.osver, pu.arch, "",
					pu.repo_file, pu.repo_str,
					"postgresql", fmt.Sprintf("%s=%s", pkgName, version), ""); err != nil {
					return fmt.Errorf("can't insert postgresql package via '%s' %w", query, err)
				}
			case "mariadb":
				query := "REPLACE INTO mariadb_version VALUES(?,?,?,?,?,?,?,?,?)"
				if _, err := db.Exec(query, version, pu.osver, pu.arch, "",
					pu.repo_file, pu.repo_str,
					"mariadb", fmt.Sprintf("%s=%s", pkgName, version), ""); err != nil {
					return fmt.Errorf("can't insert mariadb package via '%s' %w", query, err)
				}
			}
		}
	}
	fmt.Printf("OS: %s, Program: %s, Packages: %d, Versions: %d\n",
		pu.osver, program, len(versionsByPackage), versions_cnt)
	return nil
}

// extractBaseVersion extracts the base version from RPM version strings
// e.g., "17.0-1PGDG.rhel8" -> "17.0-1"
func extractBaseVersion(version string) string {
	// Find the first occurrence of a letter (indicating distro suffix)
	for i, char := range version {
		if (char >= 'A' && char <= 'Z') || (char >= 'a' && char <= 'z') {
			// If we found a letter, check if there's a dot before it and exclude it
			if i > 0 && version[i-1] == '.' {
				return version[:i-1]
			}
			return version[:i]
		}
	}
	return version
}

// getPostgreSQLRepoURL returns the appropriate PostgreSQL repository URL based on OS and architecture
func getPostgreSQLRepoURL(program, osver, arch string) string {
	if program != "postgresql" {
		return ""
	}

	// Map OS versions to their corresponding EL versions
	elVersion := ""
	switch osver {
	case "el6":
		elVersion = "EL-6"
	case "el7":
		elVersion = "EL-7"
	case "el8":
		elVersion = "EL-8"
	case "el9":
		elVersion = "EL-9"
	case "el10":
		elVersion = "EL-10"
	default:
		return ""
	}

	// Map architectures to their corresponding names
	archName := ""
	switch arch {
	case "x86_64":
		archName = "x86_64"
	case "aarch64":
		archName = "aarch64"
	default:
		return ""
	}

	// Construct the repository URL
	return fmt.Sprintf("https://download.postgresql.org/pub/repos/yum/reporpms/%s-%s/pgdg-redhat-repo-latest.noarch.rpm", elVersion, archName)
}

// getPostgreSQLSystemdService returns the appropriate systemd service name for PostgreSQL
func getPostgreSQLSystemdService(program, baseVersion string) string {
	if program != "postgresql" {
		return "mariadb"
	}

	// Extract major version from baseVersion (e.g., "17.0-1" -> "17")
	majorVersion := extractMajorVersion(baseVersion)
	if majorVersion == "" {
		return "postgresql"
	}

	return fmt.Sprintf("postgresql-%s", majorVersion)
}

// extractMajorVersion extracts the major version from a version string
// e.g., "17.0-1" -> "17", "16.10-1" -> "16"
func extractMajorVersion(version string) string {
	// Find the first dot to get the major version
	for i, char := range version {
		if char == '.' {
			return version[:i]
		}
	}
	return ""
}

func VersionFetchFromRpmPackages(dbFile string, program string, pu programVersionSource) error {
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	packages, err := rpmpackages.ParsePackagesFromRepoURL(pu.url)
	if err != nil {
		return fmt.Errorf("error fetching or parsing RPM packages file: %w", err)
	}

	//
	// Regex to match package names like postgresql-[0-9.]+
	versionsByPackage := rpmpackages.FilterPackagesByRegex(packages, pu.pattern)

	// Group packages by version (extract base version from full version)
	versionGroups := make(map[string][]string)
	for pkgName, versions := range versionsByPackage {
		for _, version := range versions {
			// Extract base version (e.g., "17.0-1" from "17.0-1PGDG.rhel8")
			baseVersion := extractBaseVersion(version)
			versionGroups[baseVersion] = append(versionGroups[baseVersion], fmt.Sprintf("%s-%s", pkgName, version))
		}
	}

	// Output the grouped versions
	versions_cnt := 0
	for baseVersion, packageList := range versionGroups {
		versions_cnt++
		packagesStr := strings.Join(packageList, "|")

		// Determine repo_url based on program, OS, and architecture
		repoURL := getPostgreSQLRepoURL(program, pu.osver, pu.arch)

		// Determine systemd service name
		systemdService := getPostgreSQLSystemdService(program, baseVersion)

		switch program {
		case "postgresql":
			query := "REPLACE INTO postgresql_version VALUES(?,?,?,?,?,?,?,?,?)"
			if _, err := db.Exec(query, baseVersion, pu.osver, pu.arch, repoURL,
				pu.repo_file, pu.repo_str,
				systemdService, packagesStr, ""); err != nil {
				return fmt.Errorf("can't insert postgresql package via '%s' %w", query, err)
			}
		case "mariadb":
			query := "REPLACE INTO mariadb_version VALUES(?,?,?,?,?,?,?,?,?)"
			if _, err := db.Exec(query, baseVersion, pu.osver, pu.arch, repoURL,
				pu.repo_file, pu.repo_str,
				systemdService, packagesStr, ""); err != nil {
				return fmt.Errorf("can't insert mariadb package via '%s' %w", query, err)
			}
		case "pmm-client":
			// Save to general_version table for pmm-client
			query := "REPLACE INTO general_version (version, os, arch, program) VALUES(?,?,?,?)"
			if _, err := db.Exec(query, baseVersion, pu.osver, pu.arch, "pmm-client"); err != nil {
				return fmt.Errorf("can't insert pmm-client package via '%s' %w", query, err)
			}
		}
	}
	fmt.Printf("OS: %s, Program: %s, Packages: %d, Versions: %d\n",
		pu.osver, program, len(versionsByPackage), versions_cnt)
	return nil
}

type programVersionSource struct {
	url       string
	pattern   string
	osver     string
	arch      string
	repo_file string
	repo_str  string
}

func getProgramUrls(program string, dbFile string) ([]programVersionSource, error) {
	var res []programVersionSource
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return res, fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	query := `SELECT url, pattern, osver, arch, repo_file, repo_str FROM download_sites WHERE program = ?`

	rows, err := db.Query(query, program)
	if err != nil {
		return res, fmt.Errorf("failed to execute select query: %w", err)
	}
	defer rows.Close()

	// Collect the results into a string
	for rows.Next() {
		var prg programVersionSource
		if err := rows.Scan(&prg.url, &prg.pattern, &prg.osver, &prg.arch, &prg.repo_file, &prg.repo_str); err != nil {
			return res, fmt.Errorf("failed to scan row: %v", err)
		}
		res = append(res, prg)
	}

	return res, nil
}
