package versionfetch

import (
	"database/sql"
	"fmt"
	"strings"

	"github.com/ihanick/anydbver/pkg/debianpackages"
	_ "modernc.org/sqlite"
)

func VersionFetch(program string, dbFile string) error {
	progUrls, err := getProgramUrls(program, dbFile)
	if err != nil {
		return fmt.Errorf("Can't fetch versions for program: %s %w", program, err)
	}

	for _, pu := range progUrls {
		if strings.HasSuffix(pu.url, "/Packages") {
			if err := VersionFetchFromDebianPackages(dbFile, pu.url, pu.pattern, pu.osver, pu.arch, pu.repo_file, pu.repo_str); err != nil {
				return fmt.Errorf("Can't get versions from debian packages file %w", err)
			}
		}

	}

	return nil
}

func VersionFetchFromDebianPackages(dbFile string, url string, packagePattern string, osver string, arch string, repo_file string, repo_str string) error {
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	packages, err := debianpackages.ParsePackagesFromURL(url)
	if err != nil {
		return fmt.Errorf("Error fetching or parsing Packages file: %w", err)
	}

	//
	// Regex to match package names like postgresql-[0-9.]+
	versionsByPackage := debianpackages.FilterPackagesByRegex(packages, packagePattern)

	// Output the filtered versions
	fmt.Println("Versions for matching PostgreSQL packages:")
	for pkgName, versions := range versionsByPackage {
		fmt.Printf("Package: %s\n", pkgName)
		for _, version := range versions {
			fmt.Printf("  Version: %s\n", version)
			// INSERT INTO postgresql_version VALUES('9.0.23-7.pgdg22.04+1','jammy','x86_64','',
			// '/etc/apt/sources.d/pgdg-archive.list','deb https://apt-archive.postgresql.org/pub/repos/apt jammy-pgdg-archive main',
			// 'postgresql','postgresql-9.0=9.0.23-7.pgdg22.04+1','');
			query := "REPLACE INTO postgresql_version VALUES(?,?,?,?,?,?,?,?,?)"
			if _, err := db.Exec(query, version, osver, arch, "", repo_file, repo_str, "postgresql", fmt.Sprintf("%s=%s", pkgName, version), ""); err != nil {
				return fmt.Errorf("Can't insert postgresql package via '%s' %w", query, err)
			}

		}
	}
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
