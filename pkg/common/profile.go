package common

import (
    "bufio"
    "log"
    "os"
    "path/filepath"
    "strings"
)

func GetUser(logger *log.Logger) string {
    programrcPath := ".anydbver"
    if _, err := os.Stat(programrcPath); os.IsNotExist(err) {
        xdgConfigHome := os.Getenv("XDG_CONFIG_HOME")
        if xdgConfigHome == "" {
            // If XDG_CONFIG_HOME is not set, use $HOME/.config
            homeDir, err := os.UserHomeDir()
            if err != nil {
                logger.Println("Error: Could not determine user's home directory")
                return ""
            }
            xdgConfigHome = filepath.Join(homeDir, ".config")
        }
        programrcPath = filepath.Join(xdgConfigHome, "anydbver", "config")
    }

    programrcFile, err := os.Open(programrcPath)
    if err != nil {
        logger.Println("Error: Could not open .programrc file")
        return ""
    }
    defer programrcFile.Close()

    scanner := bufio.NewScanner(programrcFile)
    var profile string
    for scanner.Scan() {
        line := scanner.Text()
        parts := strings.SplitN(line, "=", 2)
        if len(parts) != 2 {
            continue
        }
        if parts[0] == "PROFILE" || parts[0] == "LXD_PROFILE" {
            profile = strings.TrimSpace(parts[1])
            break
        }
    }
    if err := scanner.Err(); err != nil {
        logger.Println("Error reading .anydbver file:", err)
        return ""
    }

    if profile == "" {
        profile = os.Getenv("USER")
        if profile == "" {
            profile = "anydbver"
        }
    }

    return profile
}
