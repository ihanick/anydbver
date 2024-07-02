package unmodifieddocker;

import (
	"log"
	"regexp"
	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
)

func CreatePMMContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	user := anydbver_common.GetUser(logger)
	prefix := user
	if namespace != "" {
		prefix = namespace + "-" + prefix
	}

	node_name := prefix + "-" + name

	cmd_args := []string{
		"docker", "run",
		"--name", node_name,
		"-d",
		"--network", prefix + "-anydbver",
		"--hostname", name, }
	if mem, ok := args["memory"]; ok {
		cmd_args = append(cmd_args, "--memory=" + mem,)
	}

	if port, ok := args["port"]; ok {
		cmd_args = append(cmd_args, "-p", port + ":443",)
	} else {
		cmd_args = append(cmd_args, "-p", ":443",)
	}

	cmd_args = append(cmd_args, args["docker-image"] + ":" + args["version"],)

	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

	runtools.RunFatal(logger, []string{
		"docker", "exec", node_name, "bash", "-c", "sleep 30;grafana-cli --config /etc/grafana/grafana.ini --homepath /usr/share/grafana --configOverrides cfg:default.paths.data=/srv/grafana admin reset-admin-password " + anydbver_common.ANYDBVER_DEFAULT_PASSWORD,
	}, "Error changing password", ignoreMsg, true, env)
}


