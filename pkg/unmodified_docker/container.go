package unmodifieddocker;

import (
	"log"
)

func CreateContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
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
	}
}


func SetupContainer(logger *log.Logger, namespace string, name string, cmd string, args map[string]string) {
	if cmd == "percona-server-mongodb" {
		SetupPerconaServerMongoDBContainer(logger, namespace, name, cmd, args)
	}

}

