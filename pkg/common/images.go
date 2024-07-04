package common

import "runtime"

const (
	USE_LOCAL_IMAGES = false
	RELEASE_VERSION = "0.1.3"
	IMAGE_PUBLISHER = "ihanick"
)

func GetDockerImageName(osver string, user string) string {
	platform_tag := ""
	if runtime.GOARCH == "arm64" {
		platform_tag = "-arm64"
	}
	imageMap := map[string]string{
		"el7":   IMAGE_PUBLISHER + "/centos:7-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"el8":   IMAGE_PUBLISHER + "/rockylinux:8-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"el9":   IMAGE_PUBLISHER + "/rockylinux:9-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"jammy": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"20.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu-20.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu20.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ansible": IMAGE_PUBLISHER + "/rockylinux:8-anydbver-ansible-" + RELEASE_VERSION + platform_tag,
	}

	if USE_LOCAL_IMAGES {
		imageMap = map[string]string{
			"el7":   "centos:7-sshd-systemd-" + user,
			"el8":   "rockylinux:8-sshd-systemd-" + user,
			"el9":   "rockylinux:9-sshd-systemd-" + user,
			"jammy": "ubuntu:jammy-sshd-systemd-" + user,
			"20.04": "ubuntu:jammy-sshd-systemd-" + user,
			"ubuntu-20.04": "ubuntu:jammy-sshd-systemd-" + user,
			"ubuntu20.04": "ubuntu:jammy-sshd-systemd-" + user,
			"ansible":   "rockylinux:8-anydbver-ansible-" + user,
		}
	}

	imageName, ok := imageMap[osver]
	if !ok {
		return imageMap["el8"]
	}

	return imageName
}
