package common

import (
	"os"
	"io"
	"log"
)

func ReadWholeFile(logger *log.Logger, filename string) string {
	file, err := os.Open(filename)
	if err != nil {
		logger.Printf("failed to open file: %s", err)
		return ""
	}

	defer file.Close()

	content, err := io.ReadAll(file)
	if err != nil {
		logger.Printf("failed to read file: %s", err)
		return ""
	}
	return string(content)
}
