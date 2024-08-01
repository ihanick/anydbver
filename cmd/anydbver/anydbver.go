package main

// build with:  go build -ldflags=-X\ main.Version=$(git log --no-walk --tags --pretty="%H %d" --decorate=short | head -n1 | awk  -F'[, )]' '{ print $4; }')\ -X\ main.GoVersion=$(go version | cut -d " " -f3)\ -X\ main.Commit=$(git rev-list -1 HEAD)\ -X\ main.Build=$(date +%FT%T%z) -o tools/anydbver cmd/anydbver/anydbver.go

import (
	"bufio"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"sort"
	"strconv"
	"strings"
	"unicode"

	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
	unmodified_docker "github.com/ihanick/anydbver/pkg/unmodified_docker"
	"github.com/spf13/cobra"
	"golang.org/x/term"
	_ "modernc.org/sqlite"
)

var (
	Build     = "unknown"
	GoVersion = "unknown"
	Version   = "unknown"
	Commit    = "unknown"
  // goreleaser
  version = "dev"
  commit  = "none"
  date    = "unknown"
)


func getNetworkName(logger *log.Logger, namespace string) string {
	return anydbver_common.MakeContainerHostName(logger, namespace, "anydbver") 
}

func listContainers(logger *log.Logger, provider string, namespace string) {
	if provider == "docker" {
		args := []string{ "docker", "ps", "-a", "--filter", "network=" + getNetworkName(logger, namespace),}

		env := map[string]string{}
		errMsg := "Error docker ps"
		ignoreMsg := regexp.MustCompile("ignore this")

		containers, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env, runtools.COMMAND_TIMEOUT)
		
		if err != nil {
			logger.Printf("Can't list anydbver containers: %v", err)
			runtools.HandleDockerProblem(logger, err)
		}

		fmt.Print(containers)
	}
}

func getNsFromString(logger *log.Logger, input string) string {
	res := ""
	lines := strings.Split(input, "\n")

	suffix := getNetworkName(logger, "")

	for _, line := range lines {
		if strings.HasSuffix(line, suffix) {
			result := strings.TrimSuffix(line, suffix)
			if result == "" {
				res = res + "default\n"
			} else {
				result := strings.TrimSuffix(line, "-" + suffix)
				res = res + result + "\n"
			}
		}
	}
	return res
}

func getContainerIp(provider string, logger *log.Logger, namespace string, containerName string) (string,error) {
	network := getNetworkName(logger, namespace)
	if provider == "docker" {
		args := []string{ "docker", "inspect", containerName, "--format", "{{ index .NetworkSettings.Networks \""+network+"\" \"IPAddress\" }}",}

		env := map[string]string{}
		errMsg := "Error getting docker container ip"
		ignoreMsg := regexp.MustCompile("ignore this")

		ip, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env, runtools.COMMAND_TIMEOUT)
		return strings.TrimSuffix(ip, "\n"), err
	}
	return "", errors.New("node ip is not found")
}




func getNodeIp(provider string, logger *log.Logger, namespace string, name string) (string,error) {
	if provider == "docker" || provider == "docker-image" {

		return getContainerIp(provider, logger, namespace, anydbver_common.MakeContainerHostName(logger, namespace, name))
	}
	return "", errors.New("node ip is not found")
}


func listNamespaces(provider string, logger *log.Logger) {
	if provider == "docker" {
		args := []string{ "docker", "network", "ls", "--format={{.Name}}",}

		env := map[string]string{}
		errMsg := "Error docker network"
		ignoreMsg := regexp.MustCompile("ignore this")

		networks, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env, runtools.COMMAND_TIMEOUT)
		if err != nil {
			logger.Printf("Can't list anydbver namespaces: %v", err)
			runtools.HandleDockerProblem(logger, err)
		}

		fmt.Print(getNsFromString(logger, networks))
	}
}

func findK3dClusters(logger *log.Logger, namespace string) []string {
	k3d_path := anydbver_common.GetK3dPath(logger)
	if k3d_path == "" {
		return []string{}
	}

	net := getNetworkName(logger, namespace)
	args := []string{ "docker", "ps", "-a", "--filter", "network=" + net, "--format", "{{.Names}}",}

	env := map[string]string{}
	errMsg := "Error docker ps"
	ignoreMsg := regexp.MustCompile("not found|No such")

	containers, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env, runtools.COMMAND_TIMEOUT)
	if err != nil {
		logger.Printf("Can't list k3d clusters: %v", err)
		runtools.HandleDockerProblem(logger, err)
	}
	containers_list := slices.DeleteFunc(strings.Split(containers, "\n"), func(e string) bool {
		return e == ""
	})

	clusters := []string{}
	
	for _,name := range containers_list {
		if strings.HasSuffix(name, "-server-0") {
			clusters = append(clusters, strings.TrimPrefix(strings.TrimSuffix(name, "-server-0"), "k3d-"))
		}
	}

	return clusters
}


type AnydbverTest struct {
	id int
	name string
	cmd string
}

func FetchTests(logger *log.Logger, dbFile string, name string) ([]AnydbverTest, error) {
	var tests []AnydbverTest;

	if name == "all" || name == "list" {
		name = "%"
	}

	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return tests, fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	query := `SELECT test_id, test_name, REPLACE(REPLACE(cmd,'./anydbver','anydbver'), 'default', 'node0') as cmd FROM tests WHERE test_name LIKE ? ORDER BY 1`

	rows, err := db.Query(query, name)
	if err != nil {
		return tests, fmt.Errorf("failed to execute select query: %w", err)
	}
	defer rows.Close()

	// Collect the results into a string
	for rows.Next() {
		var test AnydbverTest;
		if err := rows.Scan(&test.id, &test.name, &test.cmd); err != nil {
			return tests, fmt.Errorf("failed to scan row: %w", err)
		}
		tests = append(tests, test)
	}
	if err = rows.Err(); err != nil {
		return tests, fmt.Errorf("error iterating over rows: %w", err)
	}

	return tests, nil
}
func FetchTestCases(logger *log.Logger, dbFile string, test_id int) ([]AnydbverTest, error) {
	var tests []AnydbverTest;

	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return tests, fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	query := `SELECT test_id, REPLACE(REPLACE(REPLACE(cmd,'./anydbver','anydbver'), 'default', 'node0'), 'anydbver ssh', 'anydbver exec') as cmd FROM test_cases WHERE test_id = ? ORDER BY 1,2`

	rows, err := db.Query(query, test_id)
	if err != nil {
		return tests, fmt.Errorf("failed to execute select query: %w", err)
	}
	defer rows.Close()

	// Collect the results into a string
	for rows.Next() {
		var test AnydbverTest;
		if err := rows.Scan(&test.id, &test.cmd); err != nil {
			return tests, fmt.Errorf("failed to scan row: %w", err)
		}
		tests = append(tests, test)
	}
	if err = rows.Err(); err != nil {
		return tests, fmt.Errorf("error iterating over rows: %w", err)
	}

	return tests, nil
}


func writeTestOutput(logger *log.Logger, test_id int, test_name string, test_output string) {
	test_results_path := filepath.Join(anydbver_common.GetCacheDirectory(logger), "test_results")
	err := os.MkdirAll(test_results_path, os.ModePerm)
	if err != nil {
		fmt.Printf("Failed to create directory: %s\n", err)
		return
	}
	file, err := os.Create(filepath.Join(test_results_path, fmt.Sprintf("%d - %s.log", test_id, test_name)))
	if err != nil {
		logger.Printf("Failed to create or open file: %s\n", err)
		return
	}

	defer func() {
		if err := file.Close(); err != nil {
			logger.Printf("Failed to close file: %s\n", err)
		}
	}()

	_, err = file.WriteString(test_output)
	if err != nil {
		logger.Printf("Failed to write to file: %s\n", err)
		return
	}
}

func testAnydbver(logger *log.Logger, _ string, _ string, name string, skip_os []string, registry_cache string) error {
	dbFile := anydbver_common.GetDatabasePath(logger)
	// Join the results with a space
	tests, err := FetchTests(logger, dbFile, name)
	if err != nil {
		return err
	}

	outer:
	for _,test := range tests {
		if registry_cache != "" {
			re := regexp.MustCompile(`^(.*\s*k3d)(:\S+)?(\s.*|)$`)
			if strings.Contains(test.cmd, "k3d:") {
				test.cmd = re.ReplaceAllString(test.cmd, "$1$2,registry-cache="+registry_cache+"$3")
			} else {
				test.cmd = re.ReplaceAllString(test.cmd, "$1$2:latest,registry-cache="+registry_cache+"$3")
			}
		}
		logger.Printf("Test %+v", test)
		if name == "list" {
			continue
		}
		cmd_args := []string{
			"bash", "-c", test.cmd,
		}

		for _, os_name := range skip_os {
			if strings.Contains(test.name, os_name) {
				logger.Println("SKIPPED")
				continue outer
			}
		}

		env := map[string]string{}
		errMsg := "Error running test"
		ignoreMsg := regexp.MustCompile("ignore this")
		out, err := runtools.RunGetOutput(logger, cmd_args, errMsg, ignoreMsg, true, env, runtools.COMMAND_TIMEOUT * 2)
		if err != nil {
			logger.Println("FAILED")
			writeTestOutput(logger, test.id, test.name, out)
		} else {
			logger.Println("DEPLOYED")
			test_cases, err := FetchTestCases(logger, dbFile, test.id)
			if err != nil {
				return err
			}

			for test_case_no,test_case := range test_cases {
				logger.Printf("Test case: %s", test_case.cmd)
				cmd_args := []string{
					"bash", "-c", test_case.cmd,
				}

				errMsg := "Error running test"
				ignoreMsg := regexp.MustCompile("ignore this")
				out, err := runtools.RunGetOutput(logger, cmd_args, errMsg, ignoreMsg, true, env, runtools.COMMAND_TIMEOUT)
				if err != nil {
					logger.Println("test case FAILED")
					writeTestOutput(logger, test.id, test.name + " - " + fmt.Sprint(test_case_no), out)
				} else {
					logger.Println("PASSED")
				}


			}
		}

	}
	return nil

}

func deleteNamespace(logger *log.Logger, provider string, namespace string) {
	if provider == "docker" {
		k3d_path := anydbver_common.GetK3dPath(logger)
		if k3d_path != "" {
			for _, cluster_name := range findK3dClusters(logger, namespace) {
				k3d_create_cmd := []string{ k3d_path, "cluster", "delete", cluster_name, }
				env := map[string]string{}
				errMsg := "Error deleting k3d cluster"
				ignoreMsg := regexp.MustCompile("No clusters found")
				runtools.RunFatal(logger, k3d_create_cmd, errMsg, ignoreMsg, true, env)
			}
		}

		net := getNetworkName(logger, namespace)
		args := []string{ "docker", "ps", "-a", "--filter", "network=" + net, "--format", "{{.ID}}",}

		env := map[string]string{}
		errMsg := "Error docker ps"
		ignoreMsg := regexp.MustCompile("not found|No such|has active endpoints")

		containers, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env, runtools.COMMAND_TIMEOUT)
		if err != nil {
			logger.Fatalf("Can't list anydbver containers to delete: %v", err)
		}
		containers_list := slices.DeleteFunc(strings.Split(containers, "\n"), func(e string) bool {
			return e == ""
		})

		if len(containers_list) > 0 {

			delete_args := []string{ "docker", "rm", "-f", "-v"}
			delete_args = append(delete_args,  containers_list... )
			runtools.RunFatal(logger, delete_args, errMsg, ignoreMsg, true, env)
		}
		delete_args := []string{ "docker", "network", "rm", net}
		runtools.RunFatal(logger, delete_args, errMsg, ignoreMsg, true, env)
		os.Remove(anydbver_common.GetAnsibleInventory(logger, namespace))

	}
}


func ConvertStringToMap(input string) map[string]string {
	result := make(map[string]string)
	pairs := strings.Split(input, ",")
	for _, pair := range pairs {
		keyValue := strings.Split(pair, "=")
		if len(keyValue) == 2 {
			key := keyValue[0]
			value := keyValue[1]
			result[key] = value
		}
	}
	return result
}


func createNamespace(logger *log.Logger, osvers map[string]string, privileged map[string]string, provider, namespace string) {
	network := getNetworkName(logger, namespace)
	if provider == "docker" {
		args := []string{ "docker", "network", "create", network, }
		env := map[string]string{}
		errMsg := "Error creating docker network"
		ignoreMsg := regexp.MustCompile("already exists")
		runtools.RunFatal(logger, args, errMsg, ignoreMsg, true, env)
	}
	for node, value := range osvers {
		privileged_container := true
		if val, ok := privileged[node]; ok {
			if priv, err := strconv.ParseBool(val) ; err == nil {
				privileged_container = priv
			}
		}
		createContainer(logger, node, value, privileged_container, provider, namespace)
	}
}

func createContainer(logger *log.Logger, name string, osver string, privileged bool, provider, namespace string) {
	user := anydbver_common.GetUser(logger)
	fmt.Printf("Creating container with name %s, OS %s, privileged=%t, provider=%s, namespace=%s...\n", name, osver, privileged, provider, namespace)

	args := []string{
		"docker", "run",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"--platform", "linux/" + runtime.GOARCH,
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-d", "--cgroupns=host", "--tmpfs", "/tmp",
		"--network", getNetworkName(logger, namespace),
		"--tmpfs", "/run", "--tmpfs", "/run/lock", 
		"-v", "/sys/fs/cgroup:/sys/fs/cgroup",
		"--hostname", name, }
	if privileged {
		args = append(args, []string{
			"--cap-add", "NET_ADMIN",
			"--cap-add", "SYS_PTRACE",
			"--security-opt", "seccomp=unconfined", }...)
	}
	args = append(args, anydbver_common.GetDockerImageName(osver, user),)
	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, args, errMsg, ignoreMsg, true, env)
}

func containerExec(logger *log.Logger, provider, namespace string, args []string) {
	name := "node0"

	if len(args) <= 1  {
		if len(args) == 1 && args[0] != "--" {
			name = args[0]
		}
		args = []string {"--", "/bin/bash", "--login"}
	} else if len(args) > 1 {
		name = args[0]
		args = args[1:]
	}

	if len(args) > 1 && args[0] == "--" {
		args = args[1:]
	}

	if provider == "docker" {
		docker_args := []string{
			"docker", "exec",
		}


		if term.IsTerminal(int(os.Stdin.Fd())) {
			docker_args = append(docker_args, "-it",)
		} else {
			docker_args = append(docker_args, "-i",)
		}

		docker_args = append(docker_args, anydbver_common.MakeContainerHostName(logger, namespace, name),)

		docker_args = append(docker_args, args...)

		command := exec.Command(docker_args[0], docker_args[1:]...)

		command.Stdin = os.Stdin
		command.Stdout = os.Stdout
		command.Stderr = os.Stderr

		if err := command.Start(); err != nil {
			log.Fatalf("Failed to start command: %v", err)
		}

		err := command.Wait()

		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				os.Exit(exitErr.ExitCode())
			} else {
				log.Fatalf("Command finished with error: %v", err)
			}
		}
		os.Exit(0)
	}

}


func ExecuteQueries(dbFile string, table string, deployCmd string, values map[string]string) (string, error) {
	// Open the SQLite3 database
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return "", fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	// Create the temporary table
	_, err = db.Exec(`CREATE TEMPORARY TABLE provided_subcmd(subcmd TEXT, val TEXT);`)
	if err != nil {
		return "", fmt.Errorf("failed to create temporary table: %w", err)
	}

	// Prepare the insert statement
	stmt, err := db.Prepare(`INSERT INTO provided_subcmd(subcmd, val) VALUES (?, ?);`)
	if err != nil {
		return "", fmt.Errorf("failed to prepare insert statement: %w", err)
	}
	defer stmt.Close()

	// Insert values into the temporary table
	for subcmd, val := range values {
		_, err = stmt.Exec(subcmd, val)
		if err != nil {
			return "", fmt.Errorf("failed to insert values: %w", err)
		}
	}

	// Execute the select query
	query := `
		SELECT aa.arg || CASE COALESCE(NULLIF(ps.val,''),aa.arg_default)  WHEN '' THEN '' ELSE "='" || COALESCE(NULLIF(ps.val,''),aa.arg_default)  ||"'" END as arg_val
		FROM ` + table +` aa
		LEFT JOIN provided_subcmd ps ON aa.subcmd = ps.subcmd
		WHERE aa.cmd=? AND (always_add OR aa.subcmd = ps.subcmd) AND ( (ps.val is not null AND ps.val LIKE aa.version_filter) or ? LIKE aa.version_filter )
		GROUP BY arg
		HAVING orderno = max(orderno);
	`

	rows, err := db.Query(query, deployCmd, values["version"])

	if err != nil {
		return "", fmt.Errorf("failed to execute select query: %w", err)
	}
	defer rows.Close()

	// Collect the results into a string
	var result []string
	for rows.Next() {
		var argVal string
		if err := rows.Scan(&argVal); err != nil {
			return "", fmt.Errorf("failed to scan row: %w", err)
		}
		result = append(result, argVal)
	}
	if err = rows.Err(); err != nil {
		return "", fmt.Errorf("error iterating over rows: %w", err)
	}

	// Join the results with a space
	return strings.Join(result, " "), nil
}

type DeploymentKeywordData struct {
	Cmd string
	Args	map[string]string
}

func IsDeploymentVersion(arg string) bool {
	if strings.HasPrefix(arg, "node") {
		return true
	}
	if strings.HasPrefix(arg, "v") {
		arg = strings.TrimPrefix(arg, "v")
	}

	if len(arg) != 0 && unicode.IsDigit(rune(arg[0])) {
		return true
	}

	return false
}

func ReadDatabaseVersion(dbFile string) (string, error) {
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return "", fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	query := `select version from general_version where program='anydbver' order by version desc LIMIT 1`

	rows, err := db.Query(query)
	if err != nil {
		return "", fmt.Errorf("failed to execute select query: %w", err)
	}
	defer rows.Close()

	// Collect the results into a string
	result := ""
	for rows.Next() {
		var argVal string
		if err := rows.Scan(&argVal); err != nil {
			return "", fmt.Errorf("failed to scan row: %w", err)
		}
		result = argVal
	}
	if err = rows.Err(); err != nil {
		return "", fmt.Errorf("error iterating over rows: %w", err)
	}

	// Join the results with a space
	return result, nil
}


func ResolveAlias(tbl string, dbFile string, deployCmd string) (string, error) {
	db, err := sql.Open("sqlite", dbFile)
	if err != nil {
		return "", fmt.Errorf("failed to open database: %w", err)
	}
	defer db.Close()

	query := `SELECT keyword FROM ` + tbl + ` WHERE alias = ? ORDER BY 1 LIMIT 1`

	rows, err := db.Query(query, deployCmd)
	if err != nil {
		return "", fmt.Errorf("failed to execute select query: %w", err)
	}
	defer rows.Close()

	// Collect the results into a string
	result := deployCmd
	for rows.Next() {
		var argVal string
		if err := rows.Scan(&argVal); err != nil {
			return "", fmt.Errorf("failed to scan row: %w", err)
		}
		result = argVal
	}
	if err = rows.Err(); err != nil {
		return "", fmt.Errorf("error iterating over rows: %w", err)
	}

	// Join the results with a space
	return result, nil
}

func ParseDeploymentKeyword(logger *log.Logger, keyword string) DeploymentKeywordData {
	args := make(map[string]string)
	parts := strings.SplitN(keyword, ":", 2)
	deployCmd := parts[0]
	if len(parts) > 1 {
		keyword = parts[1]
	} else {
		keyword = ""
	}
	if alias, err := ResolveAlias("keyword_aliases", anydbver_common.GetDatabasePath(logger), deployCmd) ; err == nil {
		deployCmd = alias
	}

	if deployCmd == "mongos-shard" || deployCmd == "mongos-cfg" {
		args["version"] = keyword
		return DeploymentKeywordData{
			Cmd: deployCmd,
		     Args: args,
			}
	}

	pairs := strings.Split(keyword, ",")
	for i, pair := range pairs {
		if i == 0 && IsDeploymentVersion(pair)  {
			args["version"] = pair
		} else if i == 0 {
			args["version"] = "latest"
		}

		keyValue := strings.SplitN(pair, "=", 2)

    if alias, err := ResolveAlias("subcmd_aliases", anydbver_common.GetDatabasePath(logger), keyValue[0]) ; err == nil {
      keyValue[0]= alias
    }

		if len(keyValue) == 1 {
			key := keyValue[0]
			args[key] = "" 
		}
		if len(keyValue) == 2 {
			key := keyValue[0]
			value := keyValue[1]
			args[key] = value
		}
	}

	return DeploymentKeywordData{
		Cmd: deployCmd,
		Args: args,
	}
}


func handleDBPreReq(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	if cmd == "percona-server-mongodb" {
		unmodified_docker.SetupMongoKeyFiles(logger, namespace, anydbver_common.MakeContainerHostName(logger, namespace, name), args)
	} else if cmd == "percona-xtradb-cluster" {

	}
}

func handleDeploymentKeyword(logger *log.Logger, table string, keyword string) string {
	deployment_keyword := ParseDeploymentKeyword(logger, keyword)
	if ( table == "ansible_arguments" || table == "k8s_arguments" ) && deployment_keyword.Args["version"] == "latest" {
		delete(deployment_keyword.Args, "version")
	}
	result, err := ExecuteQueries(anydbver_common.GetDatabasePath(logger), table, deployment_keyword.Cmd, deployment_keyword.Args)

	if err != nil {
		logger.Fatalf("Error: %v", err)
		return ""
	}
	logger.Println(result)
	return result
}


func deployHost(provider string, logger *log.Logger, namespace string, name string, ansible_hosts_run_file string, args []string) {
	if provider == "docker-image" {
		for _, arg := range args {
			deployment_keyword := ParseDeploymentKeyword(logger, arg)
			if _, ok := deployment_keyword.Args["docker-image"]; ok {
				unmodified_docker.CreateContainer(logger, namespace, name, deployment_keyword.Cmd, deployment_keyword.Args)
			}
		}
	} else if provider == "kubectl"  {
		cluster_name := anydbver_common.MakeContainerHostName(logger,namespace,name)
		clusterIp, err := getContainerIp("docker", logger, namespace, "k3d-" + cluster_name + "-" + "server-0")
		if err != nil {
			return
		}
		homeDir, err := os.UserHomeDir()
		if err != nil {
			logger.Println("Error: Could not determine user's home directory")
			return
		}

		run_operator_args := ""

		for _, arg := range args {
			run_operator_args = run_operator_args + " " + handleDeploymentKeyword(logger, "k8s_arguments", arg)
			volumes := []string{
				"-v", ansible_hosts_run_file + ":/vagrant/ansible_hosts_run",
				"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
				"-v", filepath.Join(homeDir, ".kube", "config") + ":/vagrant/secret/.kube/config:ro",
				"-v", filepath.Join(anydbver_common.GetCacheDirectory(logger), "data") + ":/vagrant/data",
			}
			ansible_output, err := anydbver_common.RunCommandInBaseContainer(
				logger, namespace,
				"cd /vagrant;mkdir /root/.kube ; cp /vagrant/secret/.kube/config /root/.kube/config; test -f /usr/local/bin/kubectl || (curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/"+runtime.GOARCH+"/kubectl ; chmod +x kubectl ; mv kubectl /usr/local/bin/kubectl); test -f tools/yq || (curl -LO  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_"+runtime.GOARCH+" ; chmod +x yq_linux_"+runtime.GOARCH+"; mv yq_linux_"+runtime.GOARCH+" tools/yq); sed -i -re 's/0.0.0.0:[0-9]+/" + clusterIp + ":6443/g' /root/.kube/config ;python3 tools/run_k8s_operator.py " + run_operator_args,
				volumes,
				"Error running kubernetes operator")
			if err != nil {
				logger.Println("Ansible failed with errors: ")
				fatalPattern := regexp.MustCompile(`^fatal:.*$`)
				scanner := bufio.NewScanner(strings.NewReader(ansible_output))
				for scanner.Scan() {
					line := scanner.Text()
					if fatalPattern.MatchString(line) {
						logger.Print(line)
					}
				}
				os.Exit(runtools.ANYDBVER_ANSIBLE_PROBLEM)
			}

		}

	} else if provider == "docker" {
		logger.Printf("Deploy %v", args)
		file, err := os.OpenFile(ansible_hosts_run_file, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			fmt.Println("Error opening file:", err)
			return
		}
		defer file.Close()

		ip, err := getNodeIp(provider, logger, namespace, name)

		ansible_deployment_args := ""

		for _, arg := range args {
			deployment_keyword := ParseDeploymentKeyword(logger, arg)
			if mstr, ok := deployment_keyword.Args["master"]; ok && mstr == name {
				logger.Printf("A master can't lead itself: %s: %s", name, arg)
				delete(deployment_keyword.Args, "master")
			}
			handleDBPreReq(logger, namespace, name, deployment_keyword.Cmd, deployment_keyword.Args)
			ansible_deployment_args = ansible_deployment_args + " " + handleDeploymentKeyword(logger, "ansible_arguments", arg)
		}

		content := anydbver_common.MakeContainerHostName(logger, namespace, name) + " ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host="+ip+" ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no ' "+ ansible_deployment_args +"\n"

		for {
			re_mongo_shard_hosts := regexp.MustCompile(`(extra_mongos_shard|extra_mongos_cfg)='([^']*)(node[0-9]+)([^']*)'`)
			content_with_ip := re_mongo_shard_hosts.ReplaceAllStringFunc(content, func(match string) string {
				submatches := re_mongo_shard_hosts.FindStringSubmatch(match)
				if len(submatches) > 4 {
					node := submatches[3]
					ip, err :=getNodeIp(provider, logger, namespace, node)
					if err != nil {
						fmt.Println("Error getting node ip:", err)
					}

					return fmt.Sprintf("%s='%s%s%s'", submatches[1], submatches[2], ip, submatches[4])
				}
				return match
			})
			if content_with_ip == content {
				break
			}
			content = content_with_ip
		}



		re_pmm_server := regexp.MustCompile(`(extra_pmm_url)='(node[0-9]+)'`)
		content = re_pmm_server.ReplaceAllStringFunc(content, func(match string) string {
			submatches := re_pmm_server.FindStringSubmatch(match)
			if len(submatches) > 2 {
				node := submatches[2]
				ip, err :=getNodeIp(provider, logger, namespace, node)
				if err != nil {
					fmt.Println("Error getting node ip:", err)
				}

				return fmt.Sprintf("%s='https://admin:%s@%s'", submatches[1] , url.QueryEscape(anydbver_common.ANYDBVER_DEFAULT_PASSWORD), ip)
			}
			return match
		})



		re := regexp.MustCompile(`='(node[0-9]+)'`)
		content = re.ReplaceAllStringFunc(content, func(match string) string {
			submatches := re.FindStringSubmatch(match)
			if len(submatches) > 1 {
				node := submatches[1]
				ip, err :=getNodeIp(provider, logger, namespace, node)
				if err != nil {
					fmt.Println("Error getting node ip:", err)
				}

				return fmt.Sprintf("='%s'", ip)
			}
			return match
		})


		_, err = file.WriteString(content)
		if err != nil {
			fmt.Println("Error writing to file:", err)
			return
		}
	}
}

func fetchDeployCompletions(logger *log.Logger) []string {
	var keywords []string;

	db, err := sql.Open("sqlite", anydbver_common.GetDatabasePath(logger))
	if err != nil {
		logger.Println("failed to open database:", err)
		return keywords
	}
	defer db.Close()

	query := `select distinct keyword from (select keyword from keyword_aliases union select alias as keyword from keyword_aliases) a order by keyword`

	rows, err := db.Query(query)
	if err != nil {
		logger.Println("failed to execute select query:", err)
		return keywords
	}
	defer rows.Close()

	for rows.Next() {
		var keyword string;
		if err := rows.Scan(&keyword); err != nil {
			logger.Println("failed to scan row:", err)
			return keywords
		}
		keywords = append(keywords, keyword)
	}
	if err = rows.Err(); err != nil {
		logger.Println("error iterating over rows:", err)
		return keywords
	}

	return keywords
}

func createK3dCluster(logger *log.Logger, namespace string, name string, args map[string]string) {
	cluster_name := anydbver_common.MakeContainerHostName(logger,namespace,name)
	k3d_agents := 2
	if nodes, ok := args["nodes"]; ok {
		if nodes_num, err := strconv.Atoi(nodes); err == nil {
			nodes_num--
			if nodes_num > 0 {
				k3d_agents = nodes_num
			}
		}
	}

	k3d_path := anydbver_common.GetK3dPath(logger)

	k3d_create_cmd := []string{
		k3d_path, "cluster", "create",
		cluster_name,
		"-i", "rancher/k3s:" + args["version"],
		"--network", getNetworkName(logger, namespace),
		"-a", strconv.Itoa(k3d_agents),}
	
	k3d_create_cmd = append(k3d_create_cmd, []string{
            "--k3s-arg", "--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:*",
            "--k3s-arg", "--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:*",
            "--k3s-arg", "--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@agent:*",
            "--k3s-arg", "--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@agent:*", }...)

	if dir, ok := args["storage-path"]; ok {
		k3d_create_cmd = append(k3d_create_cmd, []string{
			"--volume",
			dir + ":/var/lib/rancher/k3s/storage@all",}...)
	}
	if registry_cache, ok := args["registry-cache"]; ok {
		registry_cache_config := fmt.Sprintf(`
mirrors:
  docker.io:
    endpoint:
    - "%s"
`, registry_cache)
		registry_cache_file := filepath.Join(anydbver_common.GetCacheDirectory(logger), "registry-mirror.yaml")
		file, err := os.OpenFile(registry_cache_file, os.O_TRUNC|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			fmt.Println("Error opening file:", err)
			return
		}
		defer file.Close()
		file.WriteString(registry_cache_config)
		k3d_create_cmd = append(k3d_create_cmd, "--registry-config", registry_cache_file)
	}



	env := map[string]string{}
	errMsg := "Error creating k3d cluster"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunPipe(logger, k3d_create_cmd, errMsg, ignoreMsg, true, env)
}


func deployHosts(logger *log.Logger, ansible_hosts_run_file string, provider string, namespace string, args []string, verbose bool) {
	privileged := ""
	re_lastosver := regexp.MustCompile(`=[^=]+$`)
	osvers := "node0=el8"
	nodeDefinitions := make(map[string][]string)
	nodeProvider := make(map[string]string)
	currentNode := "node0"

	nodeProvider[currentNode] = provider
	for i, arg := range args {
		if strings.HasPrefix(arg, "node") {
			if i == 0 {
				osvers = arg + "=el8"
			} else {
				osvers = osvers + "," + arg + "=el8"
			}

			currentNode = arg
			nodeProvider[currentNode] = provider
		} else {
			if nodeDef, ok := nodeDefinitions[currentNode]; ok {
				nodeDefinitions[currentNode] = append(nodeDef, arg)
			} else {
				nodeDefinitions[currentNode] = []string{arg}
			}
			deployment_keyword := ParseDeploymentKeyword(logger, arg)
			if deployment_keyword.Cmd == "os" {
				osver := strings.TrimPrefix(arg, "os:")
				osvers = re_lastosver.ReplaceAllString(osvers, "="+osver)
			} else if _, ok := deployment_keyword.Args["docker-image"]; ok {
				nodeProvider[currentNode] = "docker-image"
				osvers = re_lastosver.ReplaceAllString(osvers, "")
			} else if deployment_keyword.Cmd == "k3d" {
				nodeProvider[currentNode] = "kubectl"
				osvers = re_lastosver.ReplaceAllString(osvers, "")
				createK3dCluster(logger, namespace, currentNode, deployment_keyword.Args)
			}
		}
	}
	anydbver_common.CreateSshKeysForContainers(logger, namespace)
	createNamespace(logger, ConvertStringToMap(osvers), ConvertStringToMap(privileged), provider, namespace)
	var nodeIdxs []int;
	for k := range nodeDefinitions {
		kStr, _ := strings.CutPrefix(k, "node")
		if nodeNum, err := strconv.Atoi(kStr); err == nil {
			nodeIdxs = append(nodeIdxs, nodeNum)
		}

	}
	sort.Ints(nodeIdxs)
	for _,k := range nodeIdxs {
		nodeName := fmt.Sprintf("node%d", k)
		nodeDef := nodeDefinitions[nodeName]
		deployHost(nodeProvider[nodeName], logger, namespace, nodeName, ansible_hosts_run_file, nodeDef)
	}

	for nodeName, nodeDef := range nodeDefinitions {
		if nodeProvider[nodeName] == "docker-image" {
			for _, arg := range nodeDef {
				deployment_keyword := ParseDeploymentKeyword(logger, arg)
				if _, ok := deployment_keyword.Args["docker-image"]; ok {
					unmodified_docker.SetupContainer(logger, namespace, nodeName, deployment_keyword.Cmd, deployment_keyword.Args)
				}
			}
		}
	}


	user := anydbver_common.GetUser(logger) 

	fileInfo, err := os.Stat(ansible_hosts_run_file)
	if os.IsNotExist(err) || (err == nil && fileInfo.Size() == 0) {
		logger.Println("no traditional installations with systemd, skipping ansible")
		return
	}
	if err != nil {
		logger.Println("Can't stat ansible hosts file", err)
		return
	}

	cmd_args := []string{
		"docker", "run", "-i", "--rm",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, "ansible"),
		"-v", ansible_hosts_run_file + ":/vagrant/ansible_hosts_run",
    "-v", anydbver_common.GetDatabasePath(logger) + ":/vagrant/anydbver_version.db",
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"--network", getNetworkName(logger, namespace),
		"--hostname", anydbver_common.MakeContainerHostName(logger, namespace, "ansible"),
		anydbver_common.GetDockerImageName("ansible", user),
 "bash", "-c",
	}

  ansible_command := "cd /vagrant;until ansible -m ping -i ansible_hosts_run all &>/dev/null ; do sleep 1; done ; ANSIBLE_FORCE_COLOR=True ANSIBLE_DISPLAY_SKIPPED_HOSTS=False ansible-playbook -i ansible_hosts_run --forks 16 playbook.yml"

  if verbose {
    ansible_command += " -vvv"
  }

  cmd_args = append(cmd_args, ansible_command)

	env := map[string]string{}
	errMsg := "Error running Ansible"
	ignoreMsg := regexp.MustCompile("ignore this")
	ansible_output, err := runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env)
	if err != nil {
		logger.Println("Ansible failed with errors: ")
		fatalPattern := regexp.MustCompile(`FAILED[!]|failed=`)
		scanner := bufio.NewScanner(strings.NewReader(ansible_output))
		for scanner.Scan() {
			line := scanner.Text()
			if fatalPattern.MatchString(line) {
				logger.Print(line)
			}
		}
		os.Exit(runtools.ANYDBVER_ANSIBLE_PROBLEM)
	}


}

func printVersion() {
		fmt.Println("anydbver")
		fmt.Printf("Version %s\n", Version)
		fmt.Printf("Build: %s using %s\n", Build, GoVersion)
		fmt.Printf("Commit: %s\n", Commit)
}

func Contains(slice []string, item string) bool {
    for _, v := range slice {
        if v == item {
            return true
        }
    }
    return false
}

func helpDeployCommands(logger *log.Logger, provider string, args []string) {
  logger.Println("Help on deployment commands: anydbver help or anydbver help keyword")
  all_commands := false
  var filter_commands []string;
  if len(args) == 1 && args[0] == "help" {
    logger.Println("Help for all deployment keywords")
    all_commands = true
  }
  fmt.Println(args)
  for _, arg := range args {
    deployment_keyword := ParseDeploymentKeyword(logger, arg)
    fmt.Println(deployment_keyword.Cmd)
    filter_commands = append(filter_commands, deployment_keyword.Cmd)
    for subcmd, _ := range deployment_keyword.Args {
      if subcmd != "version" && subcmd != "help" {
        fmt.Println(subcmd)
      }
    }
  }

	db, err := sql.Open("sqlite", anydbver_common.GetDatabasePath(logger))
	if err != nil {
		logger.Printf("failed to open database: %v", err)
    return
	}
	defer db.Close()

	query := `SELECT cmd, deploy FROM help_examples ORDER BY cmd`

	rows, err := db.Query(query)
	if err != nil {
		logger.Printf("failed to execute select query: %v", err)
    return
	}
	defer rows.Close()

	// Collect the results into a string
	for rows.Next() {
		var keyword string;
		var deploy_cmd string;
		if err := rows.Scan(&keyword, &deploy_cmd); err != nil {
      logger.Printf("failed to scan row: %v", err)
		}
		if all_commands || Contains(filter_commands, keyword) {
      fmt.Println(deploy_cmd)
    }
	}
	if err = rows.Err(); err != nil {
    logger.Printf("failed to scan row: %v", err)
	}
}

func main() {
	var provider string
	var namespace string
  var verbose bool

  if Version == "unknown" {
    Version = version
    Commit = commit
    Build = date
  }

  if Version != "unknown" {
    anydbver_common.RELEASE_VERSION = strings.TrimPrefix(Version, "v")
  }


	logger := log.New(os.Stdout, "", log.LstdFlags)

	var rootCmd = &cobra.Command{
		Use:   "anydbver",
		Short: "A tool for database environments automation",
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			if provider == "" {
				provider = "docker"
			}

      dbFile := anydbver_common.GetDatabasePath(logger)
      if ver, _ := ReadDatabaseVersion(dbFile); ver != strings.TrimPrefix(Version,"v") {
        logger.Println("Version database update is available for", dbFile, ". Run anydbver update to see latest versions")
        
      }
		},
    Version: fmt.Sprintf("\nVersion: %s\nBuild: %s using %s\nCommit: %s", Version, Build, GoVersion, Commit),
	}
	var namespaceCmd = &cobra.Command{
		Use:   "namespace",
		Short: "Manage namespaces",
	}
	var nsCreateCmd = &cobra.Command{
		Use:   "create [name]",
		Short: "Create a namespace with containers",
		Args:  cobra.ExactArgs(1), // Expect exactly one positional argument (name)
		Run: func(cmd *cobra.Command, args []string) {
			name := args[0]
			os, _ := cmd.Flags().GetString("os")
			privileged, _ := cmd.Flags().GetString("privileged")
			createNamespace(logger, ConvertStringToMap(os), ConvertStringToMap(privileged), provider, name)
		},
	}
	var listNsCmd = &cobra.Command{
		Use:   "list",
		Short: "List namespaces",
		Run: func(cmd *cobra.Command, args []string) {
			listNamespaces(provider, logger)
		},
	}
	var deleteNsCmd = &cobra.Command{
		Use:   "delete",
		Short: "Delete namespace",
		Args:  cobra.ExactArgs(1), // Expect exactly one positional argument (name)
		Run: func(cmd *cobra.Command, args []string) {
			deleteNamespace(logger, provider, args[0])
		},
	}
	var destroyCmd = &cobra.Command{
		Use:   "destroy",
		Short: "Delete containers and clusters for current namespace",
		Run: func(cmd *cobra.Command, args []string) {
			deleteNamespace(logger, provider, namespace)
		},
	}
	var updateCmd = &cobra.Command{
		Use:   "update",
		Short: "Deletes current version information database and downloads latest one from https://github.com/ihanick/anydbver/blob/master/anydbver_version.sql",
		Run: func(cmd *cobra.Command, args []string) {
      dbFile := anydbver_common.GetDatabasePath(logger)
      os.Remove(dbFile)
      anydbver_common.UpdateSqliteDatabase(logger, dbFile)
		},
	}

	var testCmd = &cobra.Command{
		Use:   "test",
		Short: "Run tests",
		Args:  cobra.ExactArgs(1), // Expect exactly one positional argument (name)
		Run: func(cmd *cobra.Command, args []string) {
			skip_os, _ := cmd.Flags().GetString("skip-os")
			var skip_os_list []string;
			if skip_os != "" {
				skip_os_list = strings.Split(skip_os,",")
			}
			registry_cache, _ := cmd.Flags().GetString("registry-cache")
			testAnydbver(logger, provider, namespace, args[0], skip_os_list, registry_cache)
		},
	}
	testCmd.Flags().StringP("skip-os", "", "", "Skip tests with specific OS")
	testCmd.Flags().StringP("registry-cache", "", "", "Add a docker registry mirror to all k3d calls")



	nsCreateCmd.Flags().StringP("os", "o", "", "Operating system of containers: node0=osver,node1=osver...")
	nsCreateCmd.Flags().StringP("privileged", "", "", "Whether the container should be privileged: node0=true,node1=true...")

	namespaceCmd.AddCommand(nsCreateCmd)
	namespaceCmd.AddCommand(listNsCmd)
	namespaceCmd.AddCommand(deleteNsCmd)
	rootCmd.AddCommand(namespaceCmd)
	rootCmd.AddCommand(destroyCmd)
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(testCmd)

	var containerCmd = &cobra.Command{
		Use:   "container",
		Short: "Manage containers",
	}
	var listCmd = &cobra.Command{
		Use:   "list",
		Short: "List containers",
		Run: func(cmd *cobra.Command, args []string) {
			listContainers(logger, provider, namespace)
		},
	}
	var createCmd = &cobra.Command{
		Use:   "create [name]",
		Short: "Create a container",
		Args:  cobra.ExactArgs(1), // Expect exactly one positional argument (name)
		Run: func(cmd *cobra.Command, args []string) {
			name := args[0]
			os, _ := cmd.Flags().GetString("os")
			privileged, _ := cmd.Flags().GetBool("privileged")
			createContainer(logger, name, os, privileged, provider, namespace)
		},
	}

	createCmd.Flags().StringP("os", "o", "", "Operating system of the container")
	createCmd.Flags().BoolP("privileged", "", true, "Whether the container should be privileged")

	var deployCmd = &cobra.Command{
		Use:   "deploy",
		Short: "deploy hosts",
		Run: func(cmd *cobra.Command, args []string) {
			keep, _ := cmd.Flags().GetBool("keep")
      if (len(args) > 0 && args[0] == "help") {
        helpDeployCommands(logger, provider, args)
        os.Exit(0)
      }

			if ! keep {
				deleteNamespace(logger, provider, namespace)
			}
			deployHosts(logger, anydbver_common.GetAnsibleInventory(logger, namespace), provider, namespace, args, verbose)
		},
	}
	deployCmd.Flags().BoolP("keep", "", false, "do not remove existing containers and network")

	deployCmd.ValidArgsFunction = cobra.FixedCompletions(fetchDeployCompletions(logger), cobra.ShellCompDirectiveNoSpace)
	rootCmd.AddCommand(deployCmd)

	var execCmd = &cobra.Command{
		Use:   "exec",
		Short: "exec command in the container",
		Run: func(cmd *cobra.Command, args []string) {
			containerExec(logger, provider, namespace, args)
		},
	}

	rootCmd.AddCommand(execCmd)


	rootCmd.PersistentFlags().StringVarP(&provider, "provider", "p", "", "Container provider")
	rootCmd.PersistentFlags().StringVarP(&namespace, "namespace", "n", "", "Namespace")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "", false, "Verbose ansible output")


	rootCmd.AddCommand(listCmd)

	containerCmd.AddCommand(listCmd)
	containerCmd.AddCommand(createCmd)
	rootCmd.AddCommand(containerCmd)


	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
