package runtools

import (
	"bytes"
	"bufio"
	"errors"
	"io"
	"log"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

const (
	COMMAND_TIMEOUT = 600
	ANYDBVER_ERROR_NOT_CONFIGURED = 2
	ANYDBVER_ERROR_BACKEND_PROBLEM = 3
	ANYDBVER_ANSIBLE_PROBLEM = 4
)

func HandleDockerProblem(logger *log.Logger, err error) {
		if strings.Contains(err.Error(), "permission denied while trying to connect") {
			logger.Println("The user is not allowed to run docker command, https://docs.docker.com/engine/install/linux-postinstall/")
			os.Exit(ANYDBVER_ERROR_NOT_CONFIGURED)
		}
}

func RunFatal(logger *log.Logger, args []string, errMsg string, ignoreMsg *regexp.Regexp, printCmd bool, env map[string]string) int {
	envVars := make([]string, 0)
	for k, v := range env {
		envVars = append(envVars, k+"="+v)
	}

	if printCmd {
		cmd := strings.Join(append(envVars, args...), " ")
		logger.Println(cmd)
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Env = append(envVars, os.Environ()...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	if err := cmd.Start(); err != nil {
		logger.Println(err)
		return 1
	}

	done := make(chan error)
	go func() { done <- cmd.Wait() }()

	select {
	case <-time.After(COMMAND_TIMEOUT * time.Second):
		cmd.Process.Kill()
		logger.Println("Command timed out")
		return 1
	case err := <-done:
		if err != nil {
			if ignoreMsg != nil && ignoreMsg.Match(out.Bytes()) {
				return 1
			}
			logger.Println(out.String())
			logger.Fatalf("%s '%s'", errMsg, strings.Join(args, " "))
			return 1
		}
		return 0
	}
}

func RunPipe(logger *log.Logger, args []string, errMsg string, ignoreMsg *regexp.Regexp, printCmd bool, env map[string]string) (string, error) {
	envVars := make([]string, 0)
	for k, v := range env {
		envVars = append(envVars, k+"="+v)
	}

	if printCmd {
		cmd := strings.Join(append(envVars, args...), " ")
		logger.Println(cmd)
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Env = append(envVars, os.Environ()...)

	stdoutPipe, _ := cmd.StdoutPipe()
	stderrPipe, _ := cmd.StderrPipe()

	if err := cmd.Start(); err != nil {
		logger.Println(err)
		return "",err
	}

	full_output :=  ""
	// Function to copy the output from the pipes to the logger
	copyOutput := func(r io.Reader, prefix string) {
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			output_chunk := scanner.Text()
			full_output = full_output + "\n" + output_chunk
			logger.Println(prefix, output_chunk)
		}
		if err := scanner.Err(); err != nil {
			logger.Println("Error reading from pipe:", err)
		}
	}

	go copyOutput(stdoutPipe, "")
	go copyOutput(stderrPipe, "")

	done := make(chan error)
	go func() { done <- cmd.Wait() }()

	select {
	case <-time.After(COMMAND_TIMEOUT * time.Second):
		cmd.Process.Kill()
		logger.Println("Command timed out")
		return full_output, errors.New("Command timed out")
	case err := <-done:
		if err != nil {
			if ignoreMsg != nil && ignoreMsg.Match([]byte(full_output)) {
				return full_output,nil
			}
			logger.Printf("%s '%s'", errMsg, strings.Join(args, " "))
			return full_output, errors.New("not ignoring errors")
		}
		return full_output, nil
	}
}


func RunGetOutput(logger *log.Logger, args []string, errMsg string, ignoreMsg *regexp.Regexp, printCmd bool, env map[string]string) (string, error) {
	envVars := make([]string, 0)
	for k, v := range env {
		envVars = append(envVars, k+"="+v)
	}

	if printCmd {
		cmd := strings.Join(append(envVars, args...), " ")
		logger.Println(cmd)
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Env = append(envVars, os.Environ()...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	if err := cmd.Start(); err != nil {
		logger.Println(err)
		return out.String(), err
	}

	done := make(chan error)
	go func() { done <- cmd.Wait() }()

	select {
	case <-time.After(COMMAND_TIMEOUT * time.Second):
		cmd.Process.Kill()
		logger.Println("Command timed out")
		return out.String(), errors.New("timeout")
	case err := <-done:
		if err != nil {
			if ignoreMsg != nil && ignoreMsg.Match(out.Bytes()) {
				return out.String(), nil
			}
			return out.String(), errors.New("not ignoring: " + out.String())
		}
		return out.String(), nil
	}
}
