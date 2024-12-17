package debianpackages

import (
	"bufio"
	"fmt"
	"net/http"
	"regexp"
	"strings"
)

type PackageEntry struct {
	Fields map[string]string
}

func ParsePackagesFromURL(url string) ([]PackageEntry, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch URL: %s, status: %d", url, resp.StatusCode)
	}

	var packages []PackageEntry
	currentFields := make(map[string]string)
	scanner := bufio.NewScanner(resp.Body)

	for scanner.Scan() {
		line := scanner.Text()

		if line == "" {
			if len(currentFields) > 0 {
				packages = append(packages, PackageEntry{Fields: currentFields})
				currentFields = make(map[string]string)
			}
			continue
		}

		if strings.Contains(line, ": ") {
			parts := strings.SplitN(line, ": ", 2)
			key := parts[0]
			value := parts[1]
			currentFields[key] = value
		}
	}

	if len(currentFields) > 0 {
		packages = append(packages, PackageEntry{Fields: currentFields})
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return packages, nil
}

func getLastKey(fields map[string]string) string {
	for key := range fields {
		return key
	}
	return ""
}

func FilterPackagesByRegex(packages []PackageEntry, pattern string) map[string][]string {
	regex := regexp.MustCompile(pattern)
	versionsByPackage := make(map[string][]string)

	for _, pkg := range packages {
		if name, ok := pkg.Fields["Package"]; ok && regex.MatchString(name) {
			if version, exists := pkg.Fields["Version"]; exists {
				versionsByPackage[name] = append(versionsByPackage[name], version)
			}
		}
	}

	return versionsByPackage
}
