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
	}
}

