package rpmpackages

import (
	"compress/gzip"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"

	"github.com/klauspost/compress/zstd"
)

type PackageEntry struct {
	Fields map[string]string
}

// RPM repository metadata structures
type RepoData struct {
	XMLName  xml.Name  `xml:"metadata"`
	Packages []Package `xml:"package"`
}

type Package struct {
	XMLName     xml.Name `xml:"package"`
	Type        string   `xml:"type,attr"`
	Name        string   `xml:"name"`
	Arch        string   `xml:"arch"`
	Version     Version  `xml:"version"`
	Checksum    Checksum `xml:"checksum"`
	Summary     string   `xml:"summary"`
	Description string   `xml:"description"`
	Location    Location `xml:"location"`
}

type Location struct {
	Href string `xml:"href,attr"`
}

type Version struct {
	Epoch   string `xml:"epoch,attr"`
	Version string `xml:"ver,attr"`
	Release string `xml:"rel,attr"`
}

type Checksum struct {
	Type  string `xml:"type,attr"`
	Value string `xml:",chardata"`
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

	var reader io.Reader = resp.Body

	// Check if the content is compressed
	isGzipped := resp.Header.Get("Content-Encoding") == "gzip" || strings.HasSuffix(url, ".gz")
	isZstd := resp.Header.Get("Content-Encoding") == "zstd" || strings.HasSuffix(url, ".zst")

	if isGzipped {
		gzReader, err := gzip.NewReader(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to create gzip reader: %v", err)
		}
		defer gzReader.Close()
		reader = gzReader
	} else if isZstd {
		zstdReader, err := zstd.NewReader(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to create zstd reader: %v", err)
		}
		defer zstdReader.Close()
		reader = zstdReader
	}

	// Parse XML
	var repoData RepoData
	decoder := xml.NewDecoder(reader)
	err = decoder.Decode(&repoData)
	if err != nil {
		return nil, fmt.Errorf("failed to parse XML: %v, url: %s", err, url)
	}

	// Convert to PackageEntry format
	var packages []PackageEntry
	for _, pkg := range repoData.Packages {
		fields := make(map[string]string)
		fields["Name"] = pkg.Name
		fields["Architecture"] = pkg.Arch
		fields["Version"] = pkg.Version.Version
		fields["Release"] = pkg.Version.Release
		fields["Epoch"] = pkg.Version.Epoch
		fields["Summary"] = pkg.Summary
		fields["Description"] = pkg.Description
		fields["URL"] = pkg.Location.Href
		fields["Checksum"] = pkg.Checksum.Value
		fields["ChecksumType"] = pkg.Checksum.Type

		// Create a full version string similar to RPM format
		fullVersion := pkg.Version.Version
		if pkg.Version.Release != "" {
			fullVersion += "-" + pkg.Version.Release
		}
		if pkg.Version.Epoch != "" && pkg.Version.Epoch != "0" {
			fullVersion = pkg.Version.Epoch + ":" + fullVersion
		}
		fields["FullVersion"] = fullVersion

		packages = append(packages, PackageEntry{Fields: fields})
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
		if name, ok := pkg.Fields["Name"]; ok && regex.MatchString(name) {
			if version, exists := pkg.Fields["FullVersion"]; exists {
				versionsByPackage[name] = append(versionsByPackage[name], version)
			}
		}
	}

	return versionsByPackage
}

// GetRepomdURL constructs the repomd.xml URL from a base repository URL
func GetRepomdURL(baseURL string) string {
	if strings.HasSuffix(baseURL, "/") {
		return baseURL + "repodata/repomd.xml"
	}
	return baseURL + "/repodata/repomd.xml"
}

// GetPrimaryURL extracts the primary.xml.gz URL from repomd.xml
func GetPrimaryURL(repomdURL string) (string, error) {
	resp, err := http.Get(repomdURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to fetch repomd.xml: %s, status: %d", repomdURL, resp.StatusCode)
	}

	// Parse repomd.xml to find primary.xml.gz location
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	// Simple regex to extract primary.xml location (supports both .gz and .zst)
	// This is a simplified approach - in production you might want to use proper XML parsing
	re := regexp.MustCompile(`<location href="([^"]*primary\.xml\.(gz|zst))"`)
	matches := re.FindStringSubmatch(string(body))
	if len(matches) < 2 {
		return "", fmt.Errorf("could not find primary.xml.gz or primary.xml.zst location in repomd.xml")
	}

	// Construct full URL
	baseURL := strings.TrimSuffix(repomdURL, "/repodata/repomd.xml")
	if strings.HasSuffix(baseURL, "/") {
		return baseURL + matches[1], nil
	}
	return baseURL + "/" + matches[1], nil
}

// ParsePackagesFromRepoURL is a convenience function that handles the full workflow
// from repository base URL to parsed packages
func ParsePackagesFromRepoURL(baseURL string) ([]PackageEntry, error) {
	repomdURL := GetRepomdURL(baseURL)
	primaryURL, err := GetPrimaryURL(repomdURL)
	if err != nil {
		return nil, fmt.Errorf("failed to get primary URL: %v", err)
	}

	return ParsePackagesFromURL(primaryURL)
}
