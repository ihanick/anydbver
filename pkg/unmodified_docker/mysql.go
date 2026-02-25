package unmodifieddocker

import (
	"fmt"
	"log"
	"net/url"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"

	anydbver_common "github.com/zelmario/anydbver/pkg/common"
	"github.com/zelmario/anydbver/pkg/runtools"
)

const (
	DEFAULT_SERVER_ID = 50
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
		"--restart=always",
		"--hostname", name}

	if _, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "--entrypoint=/bin/sh")
	}

	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	if ent, ok := args["entrypoint"]; ok {
		cmd_args = append(cmd_args, "-c", anydbver_common.ReadWholeFile(logger, ent))
	}

	if entrypoint_args, ok := args["args"]; ok {
		r_shell_quotted := regexp.MustCompile("'.+'|\".+\"|\\S+")
		m := r_shell_quotted.FindAllString(entrypoint_args, -1)
		cmd_args = append(cmd_args, m...)
	}
	if _, ok := args["group-replication"]; ok {
		server_id := DEFAULT_SERVER_ID + 1
		if _, ok := args["server-id"]; !ok {
			if node_num, err := strconv.Atoi(strings.ReplaceAll(name, "node", "")); err == nil {
				server_id += node_num
			}
		}
		innodb_buffer_pool_size := "512M"
		if mem_size, ok := args["memory"]; ok {
			innodb_buffer_pool_size = mem_size
		}

		cmd_args = append(
			cmd_args,
			[]string{
				fmt.Sprintf("--server-id=%d", server_id),
				fmt.Sprintf("--innodb-buffer-pool-size=%s", innodb_buffer_pool_size),
				fmt.Sprintf("--report-host=%s", name),
				"--log-bin=mysqld-bin",
				"--binlog-checksum=NONE",
				"--enforce-gtid-consistency=ON",
				"--gtid-mode=ON",
				"--loose-log-slave-updates",
				"--loose-log-replica-updates=ON",
				"--loose-transaction_write_set_extraction=XXHASH64",
				"--loose-master_info_repository=TABLE",
				"--loose-relay_log_info_repository=TABLE",
				"--loose-binlog_transaction_dependency_tracking=WRITESET",
				"--loose-slave_parallel_type=LOGICAL_CLOCK",
				"--loose-slave_preserve_commit_order=ON",
				"--loose-mysql_native_password=ON",
			}...)
	}
	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

}

func SetupMysqlContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	node_name := anydbver_common.MakeContainerHostName(logger, namespace, name)
	cluster_name := "cluster1"
	if args_cluster_name, ok := args["cluster-name"]; ok {
		cluster_name = args_cluster_name
	}
	if _, ok := args["group-replication"]; ok {
		if master, ok := args["master"]; ok {
			master_node_name := anydbver_common.MakeContainerHostName(logger, namespace, master)
			cmd_args := []string{
				"docker", "exec", master_node_name,
				"bash", "-c",
				fmt.Sprintf(
					"mysqlsh --js --host=%s --user=root --password=$MYSQL_ROOT_PASSWORD -e \"var c=dba.getCluster();c.addInstance('root:%s@%s:3306', {recoveryMethod: 'clone', label: '%s'})\"; until mysql -N -uroot -p\"$MYSQL_ROOT_PASSWORD\" -e \"select MEMBER_STATE from performance_schema.replication_group_members where member_host='%s'\"|grep -q ONLINE ; do sleep 1 ; done",
					master_node_name,
					url.QueryEscape(anydbver_common.ANYDBVER_DEFAULT_PASSWORD),
					anydbver_common.MakeContainerHostName(logger, namespace, name),
					anydbver_common.MakeContainerHostName(logger, namespace, name),
					name,
				),
			}
			env := map[string]string{}
			errMsg := "Can't set up first Group replication node"
			ignoreMsg := regexp.MustCompile("is shutting down")
			runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)
		} else {
			cmd_args := []string{
				"docker", "exec", node_name,
				"bash", "-c",
				fmt.Sprintf(
					"until mysqlsh --js --user=root --password=$MYSQL_ROOT_PASSWORD -e \"dba.createCluster('%s', {})\" ; do sleep 1; done",
					cluster_name),
			}
			env := map[string]string{}
			errMsg := "Can't set up first Group replication node"
			ignoreMsg := regexp.MustCompile("ignore this")
			runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)
		}
	}
}
