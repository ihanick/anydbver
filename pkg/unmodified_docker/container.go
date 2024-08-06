package unmodifieddocker

import (
	"log"
	"strings"
)

func CreateContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	if strings.Contains(args["docker-image"], ":") {
		parts := strings.SplitN(args["docker-image"], ":", 2)
		args["docker-image"] = parts[0]
		args["version"] = parts[1]
	}
	if cmd == "postgresql" {
		if args["docker-image"] == "" {
			args["docker-image"] = "postgres"
		}
		CreatePostgresqlContainer(logger, namespace, name, cmd, args)
	} else if cmd == "pmm-server" {
		if args["docker-image"] == "" {
			args["docker-image"] = "percona/pmm-server"
		}
		CreatePMMContainer(logger, namespace, name, cmd, args)
	} else if cmd == "pmm-client" {
		if args["docker-image"] == "" {
			args["docker-image"] = "percona/pmm-client"
		}
		CreatePMMClientContainer(logger, namespace, name, cmd, args)
	} else if cmd == "mysql" {
		if args["docker-image"] == "" {
			args["docker-image"] = "container-registry.oracle.com/mysql/community-server"
		}
		CreateMySqlContainer(logger, namespace, name, cmd, args)
	} else if cmd == "percona-server" {
		if args["docker-image"] == "" {
			args["docker-image"] = "percona/percona-server"
		}
		CreateMySqlContainer(logger, namespace, name, cmd, args)
	} else if cmd == "mariadb" {
		if args["docker-image"] == "" {
			args["docker-image"] = "mariadb"
		}
		CreateMySqlContainer(logger, namespace, name, cmd, args)
	} else if cmd == "percona-server-mongodb" {
		if args["docker-image"] == "" {
			args["docker-image"] = "percona/percona-server-mongodb"
		}
		CreatePerconaServerMongoDBContainer(logger, namespace, name, cmd, args)
	} else if cmd == "valkey" {
		if args["docker-image"] == "" {
			args["docker-image"] = "valkey/valkey"
		}
		CreateValKeyContainer(logger, namespace, name, cmd, args)
	} else if cmd == "minio" {
		if args["docker-image"] == "" {
			args["docker-image"] = "minio/minio"
		}
		CreateMinIOContainer(logger, namespace, name, cmd, args)
	}
}

func SetupContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	if cmd == "percona-server-mongodb" {
		SetupPerconaServerMongoDBContainer(logger, namespace, name, cmd, args)
	}

}
