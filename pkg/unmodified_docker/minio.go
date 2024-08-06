package unmodifieddocker

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"

	anydbver_common "github.com/ihanick/anydbver/pkg/common"
	"github.com/ihanick/anydbver/pkg/runtools"
)

const (
	MINIO_USER   = "UIdgE4sXPBTcBB4eEawU"
	MINIO_PASS   = "7UdlDzBF769dbIOMVILV"
	MINIO_BUCKET = "bucket1"
)

func CreateMinIOContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	access_key := MINIO_USER
	secret_key := MINIO_PASS
	bucket_name := MINIO_BUCKET

	cmd_args := []string{
		"docker", "run",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"-d",
		"--network", anydbver_common.MakeContainerHostName(logger, namespace, "anydbver"),
		"--hostname", anydbver_common.MakeContainerHostName(logger, namespace, name)}
	if mem, ok := args["memory"]; ok {
		cmd_args = append(cmd_args, "--memory="+mem)
	}
	if ak, ok := args["access-key"]; ok {
		access_key = ak
	}
	if sk, ok := args["secret-key"]; ok {
		secret_key = sk
	}
	if buc, ok := args["bucket"]; ok {
		bucket_name = buc
	}

	data_dir := filepath.Join(anydbver_common.GetCacheDirectory(logger), anydbver_common.MakeContainerHostName(logger, namespace, name+"-minio"))
	os.MkdirAll(data_dir, 0777)
	cmd_args = append(cmd_args, []string{
		"-e", "MINIO_ROOT_USER=" + access_key,
		"-e", "MINIO_ROOT_PASSWORD=" + secret_key,
		"-v", data_dir + ":/mnt/data",
	}...)
	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	cmd_args = append(cmd_args, []string{"server", "/data", "--console-address", ":9090"}...)

	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

	create_bucket := fmt.Sprintf(`until mc --insecure alias set local http://127.0.0.1:9000 "%s" "%s" ; do sleep 1; done;mc --insecure rb --force local/%s;mc --insecure mb local/%s`,
		access_key, secret_key, bucket_name, bucket_name)

	runtools.RunFatal(logger, []string{
		"docker", "exec", anydbver_common.MakeContainerHostName(logger, namespace, name), "bash", "-c", create_bucket,
	}, "Error creating bucket", ignoreMsg, true, env)

}
