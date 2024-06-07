package common

func GetDockerImageName(osver string, user string) string {
	imageMap := map[string]string{
		"el7":   "centos:7-sshd-systemd",
		"el8":   "rockylinux:8-sshd-systemd",
		"el9":   "rockylinux:9-sshd-systemd",
		"jammy": "ubuntu:jammy-sshd-systemd",
		"20.04": "ubuntu:jammy-sshd-systemd",
		"ubuntu-20.04": "ubuntu:jammy-sshd-systemd",
		"ubuntu20.04": "ubuntu:jammy-sshd-systemd",
	}

	imageName, ok := imageMap[osver]
	if !ok {
		return "ihanick/rockylinux:8-ssh-systemd-anydbver" + "-0.1.0"
	}

	return imageName + "-" + user
}
