package unmodifieddocker;

import (
	"log"
	"regexp"
	"path/filepath"
	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
)

func CreatePostgresqlContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	user := anydbver_common.GetUser(logger)
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}

	cmd_args := []string{
		"docker", "run",
		"--name", prefix + "-" + name,
		"--platform", "linux/amd64",
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-d", "--cgroupns=host", "--tmpfs", "/tmp",
		"--network", prefix + "-anydbver",
		"--tmpfs", "/run", "--tmpfs", "/run/lock", 
		"-v", "/sys/fs/cgroup:/sys/fs/cgroup",
		"-e", "POSTGRES_PASSWORD=" + anydbver_common.ANYDBVER_DEFAULT_PASSWORD,
		"--hostname", name, }
	cmd_args = append(cmd_args, args["docker-image"] + ":" + args["version"],)
	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

}



