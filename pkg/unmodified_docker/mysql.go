package unmodifieddocker

import (
	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
	"log"
	"path/filepath"
	"regexp"
	"runtime"
)

func CreateMySqlContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	tools_dir := anydbver_common.GetToolsDirectory(logger, namespace)

	cmd_args := []string{
		"docker", "run",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"--platform", "linux/" + runtime.GOARCH,
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-v", tools_dir + ":/vagrant/tools",
		"-d", "--cgroupns=host", "--tmpfs", "/tmp",
		"--network", anydbver_common.MakeContainerHostName(logger, namespace, "anydbver"),
		"-e", "MYSQL_ROOT_PASSWORD=" + anydbver_common.ANYDBVER_DEFAULT_PASSWORD,
		"-e", "MYSQL_ROOT_HOST=%",
		"--hostname", name}

	if _, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "--entrypoint=/bin/sh")
	}

	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	if ent, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "-c", anydbver_common.ReadWholeFile(logger, ent))
	}
	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

}
