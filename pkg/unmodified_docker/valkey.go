package unmodifieddocker

import (
	"fmt"
	"log"
	"path/filepath"
	"regexp"
	"runtime"

	anydbver_common "github.com/zelmario/anydbver/pkg/common"
	"github.com/zelmario/anydbver/pkg/runtools"
)

func CreateValKeyContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	tools_dir := anydbver_common.GetToolsDirectory(logger, namespace)

	master_hostname := anydbver_common.MakeContainerHostName(logger, namespace, name)

	cmd_args := []string{
		"docker", "run",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"--platform", "linux/" + runtime.GOARCH,
		"-v", filepath.Dir(anydbver_common.GetConfigPath(logger)) + "/secret:/vagrant/secret",
		"-v", anydbver_common.GetCacheDirectory(logger) + "/data/nfs:/nfs",
		"-v", tools_dir + ":/vagrant/tools",
		"-d", "--tmpfs", "/tmp",
		"--network", anydbver_common.MakeContainerHostName(logger, namespace, "anydbver"),
		"--hostname", name}

	if mem, ok := args["memory"]; ok {
		cmd_args = append(cmd_args, "--memory="+mem)
	}

	password := anydbver_common.ANYDBVER_DEFAULT_PASSWORD
	if pass, ok := args["password"]; ok {
		password = pass
	}

	repl_conf := ""
	if master, ok := args["master"]; ok {
		master_hostname = anydbver_common.MakeContainerHostName(logger, namespace, master)
		repl_conf = fmt.Sprintf("replicaof %s 6379", master_hostname)
	}

	cluster_conf := ""
	if _, ok := args["cluster"]; ok {
		cluster_conf = `cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000`
	}

	sentinel_conf := ""
	if _, ok := args["sentinel"]; ok {
		sentinel_conf = fmt.Sprintf(`cat > /data/sentinel.conf <<EOF
bind 0.0.0.0
port 26379
sentinel resolve-hostnames yes
sentinel monitor mymaster %s 6379 2
sentinel auth-pass mymaster %s
sentinel auth-user mymaster default
sentinel down-after-milliseconds mymaster 10000
EOF
valkey-sentinel /data/sentinel.conf &
`,
			master_hostname, password)

	}

	args["entrypoint"] = fmt.Sprintf(`[ -f /data/valkey.conf ] || cat > /data/valkey.conf <<EOF
requirepass %s
masterauth %s
%s
%s
EOF
%s
exec valkey-server /data/valkey.conf
`,
		password, password, repl_conf, cluster_conf, sentinel_conf)

	if _, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "--entrypoint=/bin/sh")
	}

	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	if ent, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "-c", ent)
	}
	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

}
