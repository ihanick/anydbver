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
	} else 
	if cmd == "pmm-server" {
		if args["docker-image"] == "" {
			args["docker-image"] = "percona/pmm-server"
		}
		CreatePMMContainer(logger, namespace, name, cmd, args)
	}
}

