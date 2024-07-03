package unmodifieddocker;

import (
	"log"
	"regexp"
	"path/filepath"
	"runtime"
	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
)

func CreatePostgresqlContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	user := anydbver_common.GetUser(logger)
	tools_dir := anydbver_common.GetToolsDirectory(logger, namespace) 
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}

	cmd_args := []string{
		"docker", "run",
		"--name", prefix + "-" + name,
		"--platform", "linux/" + runtime.GOARCH,
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-v", tools_dir + ":/vagrant/tools",
		"-d", "--cgroupns=host", "--tmpfs", "/tmp",
		"--network", prefix + "-anydbver",
		"--tmpfs", "/run", "--tmpfs", "/run/lock", 
		"-v", "/sys/fs/cgroup:/sys/fs/cgroup",
		"-e", "POSTGRES_PASSWORD=" + anydbver_common.ANYDBVER_DEFAULT_PASSWORD,
		"--hostname", name, }
	if mstr, ok := args["master"]; ok {
		args["entrypoint"] = filepath.Join(tools_dir, "setup_postgresql_replication_docker.sh") 
		cmd_args = append(cmd_args, "-e", "POSTGRES_PRIMARY_HOST=" + prefix + "-" + mstr)
	} else {
		args["entrypoint"] = filepath.Join(tools_dir, "setup_pg_hba.sh") 
	}


	if _, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "--entrypoint=/bin/sh",)
	}

	cmd_args = append(cmd_args, args["docker-image"] + ":" + args["version"],)

	if ent, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "-c", anydbver_common.ReadWholeFile(logger, ent),)
	}
	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

}



