package unmodifieddocker

import (
	"fmt"
	"log"
	"os"
  "strings"
	"path/filepath"
	"regexp"

	anydbver_common "github.com/zelmario/anydbver/pkg/common"
	"github.com/zelmario/anydbver/pkg/runtools"
)

func CreateMinIOContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	access_key := anydbver_common.ANYDBVER_MINIO_USER
	secret_key := anydbver_common.ANYDBVER_MINIO_PASS
	bucket_name := anydbver_common.ANYDBVER_MINIO_BUCKET

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

	if admin_port, ok := args["admin-port"]; ok {
		cmd_args = append(cmd_args, []string{"-p", admin_port}...)
	}
	cmd_args = anydbver_common.AppendExposeParams(cmd_args, args)
	cmd_args = append(cmd_args, args["docker-image"]+":"+args["version"])

	cmd_args = append(cmd_args, []string{"server", "/data", "--console-address", ":9090"}...)

	schema := "http"
	if _, ok := args["certs"]; !ok || args["certs"] != "none" {
		MakeSelfSignedCerts(logger, namespace, name+"-create-certs", data_dir,
      anydbver_common.MakeContainerHostName(logger, namespace, name),
			[]string{"localhost", "minio-*.example.net", "172.17.0.1", name, anydbver_common.MakeContainerHostName(logger, namespace, name)})
		cmd_args = append(cmd_args, []string{"--certs-dir", "/mnt/data/certs"}...)
		schema = "https"
	}

	env := map[string]string{}
	errMsg := "Error creating container"
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, errMsg, ignoreMsg, true, env)

	create_bucket := fmt.Sprintf(`until mc --insecure alias set local %s://127.0.0.1:9000 "%s" "%s" ; do sleep 1; done;mc --insecure rb --force local/%s;mc --insecure mb local/%s`,
		schema, access_key, secret_key, bucket_name, bucket_name)

	runtools.RunFatal(logger, []string{
		"docker", "exec", anydbver_common.MakeContainerHostName(logger, namespace, name), "bash", "-c", create_bucket,
	}, "Error creating bucket", ignoreMsg, true, env)

}

func MakeSelfSignedCerts(logger *log.Logger, namespace string, name string, destdir string, cname string, domains []string) {
  quotedDomains := make([]string, len(domains))
  for i, domain := range domains {
    quotedDomains[i] = `"` + domain + `"`
  }
  domainsStr := strings.Join(quotedDomains, ",")

	create_script := `
[ -f /data/certs/private.key ] && exit 0
mkdir -p /data/certs
cd /data/certs
cat <<EOF | cfssl gencert -initca - | cfssljson -bare ca
  {
    "CN": "Root CA",
    "names": [
      {
        "O": "Support"
      }
    ],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF
cat <<EOF > ca-config.json
  {
    "signing": {
      "default": {
        "expiry": "87600h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"]
      }
    }
  }
EOF

cat <<EOF | cfssl gencert -ca=ca.pem  -ca-key=ca-key.pem -config=./ca-config.json - | cfssljson -bare server
  {
    "hosts": [ `+ domainsStr +` ],
    "CN": "` + cname + `",
    "names": [
      {
        "O": "Support"
      }
    ],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF
cfssl bundle -ca-bundle=ca.pem -cert=server.pem | cfssljson -bare server
cp server.pem public.crt
cp server-key.pem private.key
  `
	cmd_args := []string{
		"docker", "run",
		"--name", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"--network", anydbver_common.MakeContainerHostName(logger, namespace, "anydbver"),
		"--hostname", anydbver_common.MakeContainerHostName(logger, namespace, name),
		"-v", destdir + ":/data",
		"--entrypoint=/bin/bash",
		"cfssl/cfssl",
		"-x",
		"-c", create_script,
	}

	env := map[string]string{}
	ignoreMsg := regexp.MustCompile("ignore this")
	runtools.RunFatal(logger, cmd_args, "Error creating certificate", ignoreMsg, true, env)
}
