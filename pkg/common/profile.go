package common

import (
    "bufio"
    "database/sql"
    "log"
    "io"
    "os"
    "fmt"
    "net/http"
    "path/filepath"
    "strings"
    "regexp"
    _ "github.com/mattn/go-sqlite3"
    "github.com/ihanick/anydbver/pkg/runtools"
)

const (
	ANYDBVER_VERSION_DATABASE_SQL_URL = "https://github.com/ihanick/anydbver/raw/master/anydbver_version.sql"
)

func CreateSshKeysForContainers(logger *log.Logger, namespace string) {
	secretDir := filepath.Join(filepath.Dir(GetConfigPath(logger)), "secret")
	sshKeyPath := filepath.Join(secretDir, "id_rsa.pub")
	if _, err := os.Stat(secretDir); os.IsNotExist(err) {
		os.MkdirAll(secretDir, os.ModePerm)
	}
	if _, err := os.Stat(sshKeyPath); os.IsNotExist(err) {
		user := GetUser(logger) 
		prefix := user
		if namespace != "" {
			prefix = namespace + "-" + prefix
		}


		cmd_args := []string{
			"docker", "run", "-i", "--rm",
			"--name", prefix + "-keygen",
			"-v", secretDir + ":/vagrant/secret",
			GetDockerImageName("ansible", user),
			"bash", "-c", "cd /vagrant/secret;ssh-keygen -t rsa -f id_rsa -P ''",
		}

		env := map[string]string{}
		errMsg := "Error creating container"
		ignoreMsg := regexp.MustCompile("ignore this")
		runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env)
	}
}



func GetConfigPath(logger *log.Logger) string {
	programrcPath := ".anydbver"
	if _, err := os.Stat(programrcPath); os.IsNotExist(err) {
		xdgConfigHome := os.Getenv("XDG_CONFIG_HOME")
		if xdgConfigHome == "" {
			// If XDG_CONFIG_HOME is not set, use $HOME/.config
			homeDir, err := os.UserHomeDir()
			if err != nil {
				logger.Println("Error: Could not determine user's home directory")
				return ""
			}
			xdgConfigHome = filepath.Join(homeDir, ".config")
		}
		programrcPath = filepath.Join(xdgConfigHome, "anydbver", "config")

		if _, err := os.Stat(programrcPath); os.IsNotExist(err) {
			os.MkdirAll(filepath.Join(xdgConfigHome, "anydbver"), os.ModePerm)
			file, err := os.OpenFile(programrcPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if err != nil {
				fmt.Println("Error opening file:", err)
				return ""
			}
			defer file.Close()

			_, err = file.WriteString("PROVIDER=docker\n")
			if err != nil {
				fmt.Println("Error writing config file file:", err)
				return ""
			}
		}


	}

	return programrcPath
}

func downloadVersionDatabase(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to download file: %v", err)
	}
	defer resp.Body.Close()

	// Create a temporary file
	tempFile, err := os.CreateTemp("", "anydbver_version_db-*.sql")
	if err != nil {
		return "", fmt.Errorf("failed to create temporary file: %v", err)
	}
	defer tempFile.Close()

	// Copy the response body to the temporary file
	_, err = io.Copy(tempFile, resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to copy data to temporary file: %v", err)
	}

	return tempFile.Name(), nil
}

func createAndPopulateDatabase(dbpath string, sqlpath string, logger *log.Logger) error {
	// Open (or create) the database
	db, err := sql.Open("sqlite3", dbpath)
	if err != nil {
		logger.Printf("Failed to open database: %v\n", err)
		return fmt.Errorf("failed to open database: %v", err)
	}
	defer db.Close()

	// Read the SQL dump file
	sqlBytes, err := os.ReadFile(sqlpath)
	if err != nil {
		logger.Printf("Failed to read SQL file: %v\n", err)
		return fmt.Errorf("failed to read SQL file: %v", err)
	}
	sqlScript := string(sqlBytes)

	// Execute the SQL script to populate the database
	_, err = db.Exec(sqlScript)
	if err != nil {
		logger.Printf("Failed to execute SQL script: %v\n", err)
		return fmt.Errorf("failed to execute SQL script: %v", err)
	}

	logger.Printf("Database %s created and populated successfully from %s\n", dbpath, sqlpath)
	return nil
}

func GetDatabasePath(logger *log.Logger) string {
	dbpath := "anydbver_version.db"
	dbpath = filepath.Join( filepath.Dir(GetConfigPath(logger)), dbpath)
	if _, err := os.Stat(dbpath); os.IsNotExist(err) {
		sqlpath, err := downloadVersionDatabase(ANYDBVER_VERSION_DATABASE_SQL_URL)
		if err != nil {
			logger.Printf("Failed to download version database SQL script: %v\n", err)
			return dbpath
		}

		err = createAndPopulateDatabase(dbpath, sqlpath, logger)
		if err != nil {
			logger.Fatal("Copy anydbver_version.db to", dbpath)
			return dbpath
		}

		os.Remove(sqlpath)
	}

	return dbpath
}

func GetCacheDirectory(logger *log.Logger) string {
	cache_dir := filepath.Dir(GetConfigPath(logger))
	if cache_dir != "" && cache_dir != "." {
		xdgCacheHome := os.Getenv("XDG_CACHE_HOME")
		if xdgCacheHome == "" {
			// If XDG_CONFIG_HOME is not set, use $HOME/.cache
			homeDir, err := os.UserHomeDir()
			if err != nil {
				logger.Println("Error: Could not determine user's home directory")
				return ""
			}
			xdgCacheHome = filepath.Join(homeDir, ".cache")
		}
		cache_dir = filepath.Join(xdgCacheHome, "anydbver")
		if _, err := os.Stat(cache_dir); os.IsNotExist(err) {
			os.MkdirAll(cache_dir, os.ModePerm)
		}


	}
	return cache_dir

}

func GetAnsibleInventory(logger *log.Logger, namespace string) string {
	ipath := "ansible_hosts_run"
	prefix := ""
	if namespace != "" {
		prefix = namespace + "-"
	}

	ipath = prefix + ipath
	ipath = filepath.Join( GetCacheDirectory(logger), ipath)

	return ipath
}

func GetUser(logger *log.Logger) string {
	programrcFile, err := os.Open(GetConfigPath(logger))
	if err != nil {
		logger.Println("Error: Could not open .anydbver file")
		return ""
	}
	defer programrcFile.Close()

	scanner := bufio.NewScanner(programrcFile)
	var profile string
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		if parts[0] == "PROFILE" || parts[0] == "LXD_PROFILE" {
			profile = strings.TrimSpace(parts[1])
			break
		}
	}
	if err := scanner.Err(); err != nil {
		logger.Println("Error reading .anydbver file:", err)
		return ""
	}

	if profile == "" {
		profile = os.Getenv("USER")
		if profile == "" {
			profile = "anydbver"
		}
	}

	return profile
}
