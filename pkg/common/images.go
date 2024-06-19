package common

const (
	USE_LOCAL_IMAGES = false
	RELEASE_VERSION = "0.1.1"
	IMAGE_PUBLISHER = "ihanick"
)

func GetDockerImageName(osver string, user string) string {
	imageMap := map[string]string{
		"el7":   IMAGE_PUBLISHER + "/centos:7-sshd-systemd-" + RELEASE_VERSION,
		"el8":   IMAGE_PUBLISHER + "/rockylinux:8-sshd-systemd-" + RELEASE_VERSION,
		"el9":   IMAGE_PUBLISHER + "/rockylinux:9-sshd-systemd-" + RELEASE_VERSION,
		"jammy": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION,
		"20.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION,
		"ubuntu-20.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION,
		"ubuntu20.04": IMAGE_PUBLISHER + "/ubuntu:jammy-sshd-systemd-" + RELEASE_VERSION,
		"ansible": IMAGE_PUBLISHER + "/rockylinux:8-anydbver-ansible-" + RELEASE_VERSION,
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
