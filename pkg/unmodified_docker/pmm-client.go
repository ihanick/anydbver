package unmodifieddocker

import (
	"fmt"
	anydbver_common "github.com/zelmario/anydbver/pkg/common"
	"github.com/zelmario/anydbver/pkg/runtools"
	"log"
	"regexp"
)

func CreatePMMClientContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	cmd_args := []string{
		"docker", "run",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"-d",
		"--network", anydbver_common.MakeContainerHostName(logger, namespace, "anydbver"),
		"--hostname", anydbver_common.MakeContainerHostName(logger, namespace, name)}
	if mem, ok := args["memory"]; ok {
		cmd_args = append(cmd_args, "--memory="+mem)
	}

	if pmm_server, ok := args["server"]; ok {
		if ip, err := anydbver_common.ResolveNodeIp("docker", logger, namespace, pmm_server); err == nil {
			pmm_server = ip
		} else {
			logger.Println("Problem getting ip for pmm-server: ", err)
		}
		pmm_server_args := []string{
			"-e", "PMM_AGENT_SERVER_ADDRESS=" + pmm_server,
			"-e", "PMM_AGENT_SERVER_USERNAME=admin",
			"-e", "PMM_AGENT_SERVER_PASSWORD=" + anydbver_common.ANYDBVER_DEFAULT_PASSWORD,
			"-e", "PMM_AGENT_SERVER_INSECURE_TLS=1",
			"-e", "PMM_AGENT_SETUP=1",
			"-e", "PMM_AGENT_CONFIG_FILE=config/pmm-agent.yaml",
		}
		cmd_args = append(cmd_args, pmm_server_args...)
	}

	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

	if mysql, ok := args["mysql"]; ok {
		setup_mysql_pmm_client := fmt.Sprintf("until pmm-admin add mysql --query-source=perfschema --username=%s --password=\"%s\" --host=%s; do sleep 1 ; done",
			"root", anydbver_common.ANYDBVER_DEFAULT_PASSWORD, anydbver_common.MakeContainerHostName(logger, namespace, mysql))

		runtools.RunFatal(logger, []string{
			"docker", "exec", anydbver_common.MakeContainerHostName(logger, namespace, name), "bash", "-c", setup_mysql_pmm_client,
		}, "Error changing password", ignoreMsg, true, env)

	}

}
