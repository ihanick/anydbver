package common

import (
	"bufio"
	"database/sql"
	"errors"
	"fmt"
	"github.com/zelmario/anydbver/pkg/runtools"
	"io"
	"log"
	_ "modernc.org/sqlite"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	ANYDBVER_VERSION_DATABASE_SQL_URL = "https://github.com/zelmario/anydbver/raw/master/anydbver_version.sql"
	ANYDBVER_DEFAULT_PASSWORD         = "verysecretpassword1^"
	ANYDBVER_MINIO_USER               = "UIdgE4sXPBTcBB4eEawU"
	ANYDBVER_MINIO_PASS               = "7UdlDzBF769dbIOMVILV"
	ANYDBVER_MINIO_BUCKET             = "backup"
)

func CreateSshKeysForContainers(logger *log.Logger, namespace string) {
	secretDir := filepath.Join(filepath.Dir(GetConfigPath(logger)), "secret")
	sshKeyPath := filepath.Join(secretDir, "id_rsa.pub")
	if _, err := os.Stat(secretDir); os.IsNotExist(err) {
		os.MkdirAll(secretDir, os.ModePerm)
	}
	if _, err := os.Stat(sshKeyPath); os.IsNotExist(err) {
		user := GetUser(logger)

		cmd_args := []string{
			"docker", "run", "-i", "--rm",
			"--name", MakeContainerHostName(logger, namespace, "keygen"),
			"-v", secretDir + ":/vagrant/secret:Z",
			GetDockerImageName("ansible", user),
			"bash", "-c", "cd /vagrant/secret;ssh-keygen -t rsa -f id_rsa -P ''",
		}

		env := map[string]string{}
		errMsg := "Error creating container"
		ignoreMsg := regexp.MustCompile("ignore this")
		runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env, runtools.COMMAND_TIMEOUT)
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
				logger.Println("Error opening file:", err)
				return ""
			}
			defer file.Close()

			_, err = file.WriteString("PROVIDER=docker\n")
			if err != nil {
				logger.Println("Error writing config file file:", err)
				return ""
			}
		}

	}

	abs_path, err := filepath.Abs(programrcPath)

	if err != nil {
		logger.Println("Error getting absolute p;ath:", err)
		return ""
	}

	return abs_path
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
	db, err := sql.Open("sqlite", dbpath)
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

func UpdateSqliteDatabase(logger *log.Logger, dbpath string) {
	sqlpath, err := downloadVersionDatabase(ANYDBVER_VERSION_DATABASE_SQL_URL)
	if err != nil {
		logger.Printf("Failed to download version database SQL script: %v\n", err)
		return
	}

	err = createAndPopulateDatabase(dbpath, sqlpath, logger)
	if err != nil {
		logger.Fatal("Copy anydbver_version.db to", dbpath)
		return
	}

	os.Remove(sqlpath)
}

func GetDatabasePath(logger *log.Logger) string {
	dbpath := "anydbver_version.db"
	dbpath = filepath.Join(filepath.Dir(GetConfigPath(logger)), dbpath)
	if _, err := os.Stat(dbpath); os.IsNotExist(err) {
		UpdateSqliteDatabase(logger, dbpath)
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

func GetK3dPath(logger *log.Logger) (string, error) {
	k3d_path, err := exec.LookPath("k3d")
	if err == nil {
		return k3d_path, nil
	}
	k3d_path = "tools/k3d"
	_, err = os.Stat(k3d_path)
	if err == nil {
		return k3d_path, nil
	}

	if _, err := exec.LookPath("curl"); err != nil {
		return "", fmt.Errorf("Can't install k3d, please install curl and add it to the $PATH %w", err)
	}

	k3d_path = filepath.Join(GetCacheDirectory(logger), "k3d")
	_, err = os.Stat(k3d_path)
	if err == nil {
		return k3d_path, nil
	}

	k3d_create_cmd := []string{
		"bash", "-c",
		"curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | PATH=$PATH:" +
			GetCacheDirectory(logger) +
			" K3D_INSTALL_DIR=" +
			GetCacheDirectory(logger) +
			" USE_SUDO=false bash"}

	env := map[string]string{}
	errMsg := "Can't install k3d"
	ignoreMsg := regexp.MustCompile(".*")
	runtools.RunFatal(logger, k3d_create_cmd, errMsg, ignoreMsg, true, env)
	_, err = os.Stat(k3d_path)
	if err == nil {
		return k3d_path, nil
	}

	return "", fmt.Errorf("Can't install k3d %w", err)
}

func GetAnsibleInventory(logger *log.Logger, namespace string) string {
	return filepath.Join(GetCacheDirectory(logger), MakeContainerHostName(logger, namespace, "ansible_hosts_run"))
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

func GetToolsDirectory(logger *log.Logger, namespace string) string {
	tools_directory := "tools"
	if _, err := os.Stat("tools/setup_postgresql_replication_docker.sh"); os.IsNotExist(err) {
		user := GetUser(logger)
		tools_directory = filepath.Join(GetCacheDirectory(logger), "tools")

		cmd_args := []string{
			"docker", "run", "-i", "--rm",
			"--name", MakeContainerHostName(logger, namespace, "toolscopy"),
			"-v", tools_directory + ":" + "/newtools",
			GetDockerImageName("ansible", user),
			"bash", "-c", "cp -r /vagrant/tools/* /newtools/",
		}

		env := map[string]string{}
		errMsg := "Error creating container"
		ignoreMsg := regexp.MustCompile("ignore this")
		runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env, runtools.COMMAND_TIMEOUT)
	}

	abs_path, err := filepath.Abs(tools_directory)

	if err != nil {
		logger.Println("Error getting absolute p;ath:", err)
		return ""
	}

	return abs_path

}

func RunCommandInBaseContainer(logger *log.Logger, namespace string, cmd string, volumes []string, errMsg string, interactive bool) (string, error) {
	user := GetUser(logger)

	cmd_args := []string{
		"docker", "run", "-i", "--rm",
		"--name", MakeContainerHostName(logger, namespace, "ansible"),
		"--network", MakeContainerHostName(logger, namespace, "anydbver"),
	}

	if interactive {
		cmd_args = append(cmd_args, "-t")
	}

	cmd_args = append(cmd_args, volumes...)

	cmd_args = append(cmd_args,
		GetDockerImageName("ansible", user),
		"bash", "-c", cmd)

	env := map[string]string{}
	ignoreMsg := regexp.MustCompile("ignore this")
	if interactive {
		cmd := exec.Command(cmd_args[0], cmd_args[1:]...)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		// Run the command
		err := cmd.Run()
		if err != nil {
			os.Exit(1)
		}
	}
	return runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env, runtools.COMMAND_TIMEOUT)
}

func MakeContainerHostName(logger *log.Logger, namespace string, name string) string {
	user := GetUser(logger)
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}

	return strings.ReplaceAll(prefix+"-"+name, ".", "-")
}

func getContainerIp(provider string, logger *log.Logger, namespace string, containerName string) (string, error) {
	network := MakeContainerHostName(logger, namespace, "anydbver")
	if provider == "docker" {
		args := []string{"docker", "inspect", containerName, "--format", "{{ index .NetworkSettings.Networks \"" + network + "\" \"IPAddress\" }}"}

		env := map[string]string{}
		errMsg := "Error getting docker container ip"
		ignoreMsg := regexp.MustCompile("ignore this")

		ip, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env, runtools.COMMAND_TIMEOUT)
		return strings.TrimSuffix(ip, "\n"), err
	}
	return "", errors.New("node ip is not found")
}

func ResolveNodeIp(provider string, logger *log.Logger, namespace string, name string) (string, error) {
	if provider == "docker" || provider == "docker-image" {

		return getContainerIp(provider, logger, namespace, MakeContainerHostName(logger, namespace, name))
	}
	return "", errors.New("node ip is not found")
}

func AppendExposeParams(cmd []string, args map[string]string) []string {
	if expose_port, ok := args["expose"]; ok {
		return append(cmd, []string{"-p", expose_port}...)
	}
	return cmd
}
