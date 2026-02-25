package unmodifieddocker

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	anydbver_common "github.com/zelmario/anydbver/pkg/common"
	"github.com/zelmario/anydbver/pkg/runtools"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
)

func GenerateRandomAndEncodeBase64() (string, error) {
	data := make([]byte, 756)

	_, err := rand.Read(data)
	if err != nil {
		return "", err
	}

	encoded := base64.StdEncoding.EncodeToString(data)

	return encoded, nil
}

func GenerateMonoDBKeyFile(logger *log.Logger, replSet string) {
	keyFilePath := filepath.Join(filepath.Dir(anydbver_common.GetConfigPath(logger)), fmt.Sprintf("secret/%s-keyfile", replSet))
	if _, err := os.Stat(keyFilePath); os.IsNotExist(err) {
		randomBase64, err := GenerateRandomAndEncodeBase64()
		if err != nil {
			logger.Println("FATAL: can't generate random mongo keyfile", err)
			return
		}
		file, err := os.OpenFile(keyFilePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			logger.Println("Error opening file:", err)
			return
		}
		defer file.Close()

		_, err = file.WriteString(randomBase64)
		if err != nil {
			logger.Println("Error writing config file file:", err)
			return
		}

	}
}

func SetupMongoKeyFiles(logger *log.Logger, namespace string, hostname string, args map[string]string) []string {

	var mongo_args []string

	if _, ok := args["cluster"]; !ok {
		args["cluster"] = "cluster1"
	}

	if replSet, ok := args["replica-set"]; ok {
		GenerateMonoDBKeyFile(logger, args["cluster"])

		mongo_args = append(
			mongo_args,
			"--replSet", replSet, "--keyFile", fmt.Sprintf("/vagrant/secret/%s-keyfile-docker", replSet),
			"--bind_ip", "localhost,"+hostname)
		create_repl_set_key_cmd := fmt.Sprintf("cp /vagrant/secret/%s-keyfile /vagrant/secret/%s-keyfile;cp /vagrant/secret/%s-keyfile /vagrant/secret/%s-keyfile-docker;chown 1001 /vagrant/secret/%s-keyfile-docker;chmod 0600 /vagrant/secret/%s-keyfile-docker", args["cluster"], replSet, args["cluster"], replSet, replSet, replSet)
		volumes := []string{"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret"}
		anydbver_common.RunCommandInBaseContainer(logger, namespace, create_repl_set_key_cmd, volumes, "Can't copy mongodb keyfile", false)
	}

	return mongo_args
}

func CreatePerconaServerMongoDBContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	user := anydbver_common.GetUser(logger)
	tools_dir := anydbver_common.GetToolsDirectory(logger, namespace)
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}

	hostname := anydbver_common.MakeContainerHostName(logger, namespace, name)

	mongo_args := SetupMongoKeyFiles(logger, namespace, hostname, args)
	cmd_args := []string{
		"docker", "run",
		"--name", hostname,
		"--platform", "linux/" + runtime.GOARCH,
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-v", tools_dir + ":/vagrant/tools",
		"-d",
		"--network", anydbver_common.MakeContainerHostName(logger, namespace, "anydbver"),
		"-e", "MONGO_INITDB_ROOT_USERNAME=admin",
		"-e", "MONGO_INITDB_ROOT_PASSWORD=" + anydbver_common.ANYDBVER_DEFAULT_PASSWORD,
		"--restart=always",
		"--hostname", hostname}

	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	cmd_args = append(cmd_args, mongo_args...)

	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)
}

func SetupPerconaServerMongoDBContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	encoded_pass := url.QueryEscape(anydbver_common.ANYDBVER_DEFAULT_PASSWORD)
	if replSet, ok := args["replica-set"]; ok {
		if mstr, ok := args["master"]; ok {
			master_host := anydbver_common.MakeContainerHostName(logger, namespace, mstr)
			hostname := anydbver_common.MakeContainerHostName(logger, namespace, name)
			mongo_uri := fmt.Sprintf("mongodb://admin:%s@%s:27017/admin", encoded_pass, master_host)
			script_js := fmt.Sprintf(`rs.add({ host:"%s"})`, hostname)

			mongo_cmd := fmt.Sprintf("mongosh '%s' --eval '%s'", mongo_uri, script_js)

			runtools.ExecCommandInContainer(logger, master_host, mongo_cmd, "Can't add replica to set")

		} else {
			master_host := anydbver_common.MakeContainerHostName(logger, namespace, name)
			mongo_uri := fmt.Sprintf("mongodb://admin:%s@%s:27017/admin", encoded_pass, master_host)
			script_js := fmt.Sprintf(
				`rs.initiate( { _id : "%s", configsvr: false, members: [ { _id: 0, host: "%s:27017" }, ] })`,
				replSet, master_host)

			mongo_wait_ready_cmd := fmt.Sprintf(`until mongosh %s --eval 'print("waited for connection")' &>/dev/null ; do sleep 2 ; done`, mongo_uri)
			mongo_cmd := fmt.Sprintf("%s;mongosh '%s' --eval '%s'", mongo_wait_ready_cmd, mongo_uri, script_js)
			runtools.ExecCommandInContainer(logger, master_host, mongo_cmd, "Can't init replica set")
		}
	}
}
