package main

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"

	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
	_ "modernc.org/sqlite"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)


func getNetworkName(logger *log.Logger, namespace string) string {
	user := anydbver_common.GetUser(logger) 
	network := user + "-anydbver"
	if namespace != "" {
		network = namespace + "-" + network
	}
	return network
}

func listContainers(logger *log.Logger, provider string, namespace string) {
	if provider == "docker" {
		args := []string{ "docker", "ps", "--filter", "network=" + getNetworkName(logger, namespace),}

		env := map[string]string{}
		errMsg := "Error docker ps"
		ignoreMsg := regexp.MustCompile("ignore this")

		containers, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env)
		
		if err != nil {
			logger.Fatalf("Can't list anydbver containers: %v", err)
		}

		fmt.Print(containers)
	}
}

func getNsFromString(input string, user string) string {
	res := ""
	lines := strings.Split(input, "\n")

	suffix := user + "-anydbver"

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

		ip, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env)
		return strings.TrimSuffix(ip, "\n"), err
	}
	return "", errors.New("node ip is not found")
}




func getNodeIp(provider string, logger *log.Logger, namespace string, name string) (string,error) {
	user := anydbver_common.GetUser(logger)
	prefix := ""
	if namespace != "" {
		prefix = namespace + "-"
	}

	if provider == "docker" {

		return getContainerIp(provider, logger, namespace, prefix + user + "-" + name)
	}
	return "", errors.New("node ip is not found")
}


func listNamespaces(provider string, logger *log.Logger) {
	if provider == "docker" {
		args := []string{ "docker", "network", "ls", "--format={{.Name}}",}

		env := map[string]string{}
		errMsg := "Error docker network"
		ignoreMsg := regexp.MustCompile("ignore this")

		networks, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env)
		if err != nil {
			logger.Fatalf("Can't list anydbver namespaces: %v", err)
		}

		user := anydbver_common.GetUser(logger)
		fmt.Print(getNsFromString(networks, user))

	}
}

func findK3dClusters(logger *log.Logger, namespace string) []string {
	k3d_path := anydbver_common.GetK3dPath(logger)
	if k3d_path == "" {
		return []string{}
	}

	net := getNetworkName(logger, namespace)
	args := []string{ "docker", "ps", "--filter", "network=" + net, "--format", "{{.Names}}",}

	env := map[string]string{}
	errMsg := "Error docker ps"
	ignoreMsg := regexp.MustCompile("not found|No such")

	containers, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env)
	if err != nil {
		logger.Fatalf("Can't list anydbver containers: %v", err)
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
		args := []string{ "docker", "ps", "--filter", "network=" + net, "--format", "{{.ID}}",}

		env := map[string]string{}
		errMsg := "Error docker ps"
		ignoreMsg := regexp.MustCompile("not found|No such")

		containers, err := runtools.RunGetOutput(logger, args, errMsg, ignoreMsg, false, env)
		if err != nil {
			logger.Fatalf("Can't list anydbver containers: %v", err)
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
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}

	args := []string{
		"docker", "run",
		"--name", prefix + "-" + name,
		"--platform", "linux/amd64",
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-d", "--cgroupns=host", "--tmpfs", "/tmp",
		"--network", prefix + "-anydbver",
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
	if len(args) > 1 {
		name = args[0]
		args = args[1:]
	}

	if namespace != "" {
		name = namespace + "-" + name
	}

	if len(args) > 1 && args[0] == "--" {
		args = args[1:]
	}


	user := anydbver_common.GetUser(logger)

	if provider == "docker" {
		docker_args := []string{
			"docker", "exec",
		}


		if term.IsTerminal(int(os.Stdin.Fd())) {
			docker_args = append(docker_args, "-it",)
		} else {
			docker_args = append(docker_args, "-i",)
		}

		docker_args = append(docker_args, user + "-" + name,)

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


func ExecuteQueries(dbFile string, deployCmd string, values map[string]string) (string, error) {
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
		SELECT aa.arg || "='" || COALESCE(NULLIF(ps.val,''),aa.arg_default) ||"'" as arg_val
		FROM ansible_arguments aa
		LEFT JOIN provided_subcmd ps ON aa.subcmd = ps.subcmd
		WHERE aa.cmd=? AND (always_add OR aa.subcmd = ps.subcmd)
		GROUP BY arg
		HAVING orderno = max(orderno);
	`

	rows, err := db.Query(query, deployCmd)
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
	if strings.HasPrefix(arg, "v") {
		arg = strings.TrimPrefix(arg, "v")
	}

	if len(arg) != 0 && unicode.IsDigit(rune(arg[0])) {
		return true
	}

	return false
}

func ParseDeploymentKeyword(keyword string) DeploymentKeywordData {
	args := make(map[string]string)
	parts := strings.SplitN(keyword, ":", 2)
	deployCmd := parts[0]
	if len(parts) > 1 {
		keyword = parts[1]
	} else {
		keyword = ""
	}

	pairs := strings.Split(keyword, ",")
	for i, pair := range pairs {
		if i == 0 && IsDeploymentVersion(pair) {
			args["version"] = pair
		} else if i == 0 {
			args["version"] = "latest"
		}

		keyValue := strings.Split(pair, "=")
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


func handleDeploymentKeyword(logger *log.Logger, keyword string) string {
	deployment_keyword := ParseDeploymentKeyword(keyword)
	result, err := ExecuteQueries(anydbver_common.GetDatabasePath(logger), deployment_keyword.Cmd, deployment_keyword.Args)
	if err != nil {
		logger.Fatalf("Error: %v", err)
		return ""
	}
	return result
}

func runK8sOperator() {
}

func deployHost(provider string, logger *log.Logger, namespace string, name string, ansible_hosts_run_file string, args []string) {
	if provider == "kubectl"  {
		user := anydbver_common.GetUser(logger) 
		cluster_name := user + "-" + name
		clusterIp, err := getContainerIp("docker", logger, namespace, "k3d-" + cluster_name + "-" + "server-0")
		if err != nil {
			return
		}
		prefix := user
		if namespace != "" {
			prefix = namespace + "-" + prefix
		}

		homeDir, err := os.UserHomeDir()
		if err != nil {
			logger.Println("Error: Could not determine user's home directory")
			return
		}



		cmd_args := []string{
			"docker", "run", "-i", "--rm",
			"--name", prefix + "-ansible",
			"-v", ansible_hosts_run_file + ":/vagrant/ansible_hosts_run",
			"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
			"-v", filepath.Join(homeDir, ".kube", "config") + ":/vagrant/secret/.kube/config:ro",
			"-v", filepath.Join(anydbver_common.GetCacheDirectory(logger), "data") + ":/vagrant/data",
			"--network", prefix + "-anydbver",
			"--hostname", user + "-ansible",
			anydbver_common.GetDockerImageName("ansible", user),
			"bash", "-c", "cd /vagrant;mkdir /root/.kube ; cp /vagrant/secret/.kube/config /root/.kube/config; test -f /usr/local/bin/kubectl || (curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl ; chmod +x kubectl ; mv kubectl /usr/local/bin/kubectl); sed -i -re 's/0.0.0.0:[0-9]+/" + clusterIp + ":6443/g' /root/.kube/config ;python3 tools/run_k8s_operator.py --cluster-name=cluster1 --operator=percona-postgresql-operator --version=2.3.1",
		}

		env := map[string]string{}
		errMsg := "Error creating container"
		ignoreMsg := regexp.MustCompile("ignore this")
		runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env)
	}
	if provider == "docker" {
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
			ansible_deployment_args = ansible_deployment_args + " " + handleDeploymentKeyword(logger, arg)
		}

		user := anydbver_common.GetUser(logger) 
		content := user + "." + name + " ansible_connection=ssh ansible_user=root ansible_ssh_private_key_file=secret/id_rsa ansible_host="+ip+" ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o GSSAPIDelegateCredentials=no -o GSSAPIKeyExchange=no -o GSSAPITrustDNS=no -o ProxyCommand=none' "+ ansible_deployment_args +"\n"

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

func createK3dCluster(logger *log.Logger, namespace string, name string, args map[string]string) {
	user := anydbver_common.GetUser(logger) 
	cluster_name := user + "-" + name
	if namespace != "" {
		cluster_name = namespace + "-" + cluster_name
	}
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

	env := map[string]string{}
	errMsg := "Error creating k3d cluster"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunPipe(logger, k3d_create_cmd, errMsg, ignoreMsg, true, env)
}


func deployHosts(logger *log.Logger, ansible_hosts_run_file string, provider string, namespace string, args []string) {
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
			deployment_keyword := ParseDeploymentKeyword(arg)
			if deployment_keyword.Cmd == "os" {
				osver := strings.TrimPrefix(arg, "os:")
				osvers = re_lastosver.ReplaceAllString(osvers, "="+osver)
			} else if deployment_keyword.Cmd == "k3d" {
				nodeProvider[currentNode] = "kubectl"
				osvers = re_lastosver.ReplaceAllString(osvers, "")
				createK3dCluster(logger, namespace, currentNode, deployment_keyword.Args)
			}
		}
	}
	anydbver_common.CreateSshKeysForContainers(logger, namespace)
	createNamespace(logger, ConvertStringToMap(osvers), ConvertStringToMap(privileged), provider, namespace)
	for nodeName, nodeDef := range nodeDefinitions {
		deployHost(nodeProvider[nodeName], logger, namespace, nodeName, ansible_hosts_run_file, nodeDef)
	}

	user := anydbver_common.GetUser(logger) 
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}


	cmd_args := []string{
		"docker", "run", "-i", "--rm",
		"--name", prefix + "-ansible",
		"-v", ansible_hosts_run_file + ":/vagrant/ansible_hosts_run",
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"--network", prefix + "-anydbver",
		"--hostname", user + "-ansible",
		anydbver_common.GetDockerImageName("ansible", user),
 "bash", "-c", "cd /vagrant;until ansible -m ping -i ansible_hosts_run all &>/dev/null ; do sleep 1; done ; ANSIBLE_FORCE_COLOR=True ansible-playbook -i ansible_hosts_run --forks 16 playbook.yml",
	}

	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunPipe(logger, cmd_args, errMsg, ignoreMsg, true, env)
}

func main() {
	var provider string
	var namespace string


	logger := log.New(os.Stdout, "", log.LstdFlags)

	var rootCmd = &cobra.Command{
		Use:   "anydbver",
		Short: "A tool for database environments automation",
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			if provider == "" {
				provider = "docker"
			}
		},
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


	nsCreateCmd.Flags().StringP("os", "o", "", "Operating system of containers: node0=osver,node1=osver...")
	nsCreateCmd.Flags().StringP("privileged", "", "", "Whether the container should be privileged: node0=true,node1=true...")

	namespaceCmd.AddCommand(nsCreateCmd)
	namespaceCmd.AddCommand(listNsCmd)
	namespaceCmd.AddCommand(deleteNsCmd)
	rootCmd.AddCommand(namespaceCmd)
	rootCmd.AddCommand(destroyCmd)

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
			if ! keep {
				deleteNamespace(logger, provider, namespace)
			}
			deployHosts(logger, anydbver_common.GetAnsibleInventory(logger, namespace), provider, namespace, args)
		},
	}
	deployCmd.Flags().BoolP("keep", "", false, "do not remove existing containers and network")

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


	containerCmd.AddCommand(listCmd)
	containerCmd.AddCommand(createCmd)
	rootCmd.AddCommand(containerCmd)


	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
