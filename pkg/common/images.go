package common

import "runtime"

const (
	USE_LOCAL_IMAGES = false
	IMAGE_PUBLISHER  = "zelmar"
)

var RELEASE_VERSION = "0.1.23"
var ANSIBLE_VERSION = "0.1.30"

func GetDockerImageName(osver string, user string) string {
	platform_tag := ""
	if runtime.GOARCH == "arm64" {
		platform_tag = "-arm64"
	}
	imageMap := map[string]string{
		"el7":          IMAGE_PUBLISHER + "/centos:7-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"el8":          IMAGE_PUBLISHER + "/rockylinux:8-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"el9":          IMAGE_PUBLISHER + "/rockylinux:9-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"el10":         IMAGE_PUBLISHER + "/rockylinux:10-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"focal":        IMAGE_PUBLISHER + "/ubuntu:focal-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"20.04":        IMAGE_PUBLISHER + "/ubuntu:focal-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu-20.04": IMAGE_PUBLISHER + "/ubuntu:focal-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu20.04":  IMAGE_PUBLISHER + "/ubuntu:focal-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"jammy":        IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"22.04":        IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu-22.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu22.04":  IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"noble":        IMAGE_PUBLISHER + "/ubuntu:noble-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"24.04":        IMAGE_PUBLISHER + "/ubuntu:noble-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu-24.04": IMAGE_PUBLISHER + "/ubuntu:noble-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ubuntu24.04":  IMAGE_PUBLISHER + "/ubuntu:noble-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"bookworm":     IMAGE_PUBLISHER + "/debian:bookworm-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"debian-12":    IMAGE_PUBLISHER + "/debian:bookworm-sshd-systemd-" + RELEASE_VERSION + platform_tag,
		"ansible":      IMAGE_PUBLISHER + "/rockylinux:8-anydbver-ansible-" + ANSIBLE_VERSION + platform_tag,
	}

	if USE_LOCAL_IMAGES {
		imageMap = map[string]string{
			"el7":          "centos:7-sshd-systemd-" + user,
			"el8":          "rockylinux:8-sshd-systemd-" + user,
			"el9":          "rockylinux:9-sshd-systemd-" + user,
			"el10":         "rockylinux:10-sshd-systemd-" + user,
			"focal":        "ubuntu:focal-sshd-systemd-" + user,
			"20.04":        "ubuntu:focal-sshd-systemd-" + user,
			"ubuntu-20.04": "ubuntu:focal-sshd-systemd-" + user,
			"ubuntu20.04":  "ubuntu:focal-sshd-systemd-" + user,
			"jammy":        "ubuntu:jammy-sshd-systemd-" + user,
			"22.04":        "ubuntu:jammy-sshd-systemd-" + user,
			"ubuntu-22.04": "ubuntu:jammy-sshd-systemd-" + user,
			"ubuntu22.04":  "ubuntu:jammy-sshd-systemd-" + user,
			"noble":        "ubuntu:noble-sshd-systemd-" + user,
			"24.04":        "ubuntu:noble-sshd-systemd-" + user,
			"ubuntu-24.04": "ubuntu:noble-sshd-systemd-" + user,
			"ubuntu24.04":  "ubuntu:noble-sshd-systemd-" + user,
			"bookworm":     "debian:bookworm-sshd-systemd-" + user,
			"debian-12":    "debian:bookworm-sshd-systemd-" + user,
			"ansible":      "rockylinux:8-anydbver-ansible-" + user,
		}
	}

	imageName, ok := imageMap[osver]
	if !ok {
		return imageMap["el8"]
	}

	return imageName
}
