# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=6

COREOS_GO_PACKAGE="github.com/docker/docker-ce"
COREOS_GO_VERSION="go1.10"

if [[ ${PV} = *9999* ]]; then
	# Docker cannot be fetched via "go get", thanks to autogenerated code
	EGIT_REPO_URI="https://${COREOS_GO_PACKAGE}.git"
	EGIT_CHECKOUT_DIR="${WORKDIR}/${P}/src/${COREOS_GO_PACKAGE}"
	inherit git-r3
	KEYWORDS="~amd64 ~arm64"
else
	inherit versionator
	if [ "$(get_version_component_count)" = 4 ]; then
		MY_PV="$(replace_version_separator 3 '-ce-')"
	else
		MY_PV="$PV-ce"
	fi
	DOCKER_GITCOMMIT="6d37f41"
	SRC_URI="https://${COREOS_GO_PACKAGE}/archive/v${MY_PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="amd64 arm64"
	[ "$DOCKER_GITCOMMIT" ] || die "DOCKER_GITCOMMIT must be added manually for each bump!"
fi
inherit bash-completion-r1 coreos-go-depend linux-info systemd udev user

DESCRIPTION="The core functions you need to create Docker images and run Docker containers"
HOMEPAGE="https://dockerproject.org"
LICENSE="Apache-2.0"
SLOT="0"
IUSE="apparmor aufs +btrfs +container-init +device-mapper hardened +overlay pkcs11 seccomp +journald +selinux"

# https://github.com/docker/docker/blob/master/project/PACKAGERS.md#build-dependencies
CDEPEND="
	>=dev-db/sqlite-3.7.9:3
	device-mapper? (
		>=sys-fs/lvm2-2.02.89[thin]
	)
	seccomp? ( >=sys-libs/libseccomp-2.2.1[static-libs] )
	apparmor? ( sys-libs/libapparmor )
"

DEPEND="
	${CDEPEND}

	btrfs? (
		>=sys-fs/btrfs-progs-3.16.1
	)
"

# For CoreOS builds coreos-kernel must be installed because this ebuild
# checks the kernel config. The kernel config is left by the kernel compile
# or an explicit copy when installing binary packages. See coreos-kernel.eclass
DEPEND+="sys-kernel/coreos-kernel"

# https://github.com/docker/docker/blob/master/project/PACKAGERS.md#runtime-dependencies
# https://github.com/docker/docker/blob/master/project/PACKAGERS.md#optional-dependencies
RDEPEND="
	${CDEPEND}
	>=net-firewall/iptables-1.4
	sys-process/procps
	>=dev-vcs/git-1.7
	>=app-arch/xz-utils-4.9
	dev-libs/libltdl
	~app-emulation/containerd-1.1.2
	~app-emulation/docker-runc-1.0.0_rc5_p22[apparmor?,seccomp?]
	~app-emulation/docker-proxy-0.8.0_p20180709
	container-init? ( >=sys-process/tini-0.13.1 )
"

RESTRICT="installsources strip"

S="${WORKDIR}/${P}/src/${COREOS_GO_PACKAGE}"

ENGINE_PATCHES=(
	"${FILESDIR}/${P}-fix-mount-labels.patch"
)

# see "contrib/check-config.sh" from upstream's sources
CONFIG_CHECK="
	~NAMESPACES ~NET_NS ~PID_NS ~IPC_NS ~UTS_NS
	~CGROUPS ~CGROUP_CPUACCT ~CGROUP_DEVICE ~CGROUP_FREEZER ~CGROUP_SCHED ~CPUSETS ~MEMCG
	~KEYS
	~VETH ~BRIDGE ~BRIDGE_NETFILTER
	~NF_NAT_IPV4 ~IP_NF_FILTER ~IP_NF_TARGET_MASQUERADE
	~NETFILTER_XT_MATCH_ADDRTYPE ~NETFILTER_XT_MATCH_CONNTRACK ~NETFILTER_XT_MATCH_IPVS
	~IP_NF_NAT ~NF_NAT ~NF_NAT_NEEDED
	~POSIX_MQUEUE

	~USER_NS
	~SECCOMP
	~CGROUP_PIDS
	~MEMCG_SWAP ~MEMCG_SWAP_ENABLED

	~BLK_CGROUP ~BLK_DEV_THROTTLING ~IOSCHED_CFQ ~CFQ_GROUP_IOSCHED
	~CGROUP_PERF
	~CGROUP_HUGETLB
	~NET_CLS_CGROUP
	~CFS_BANDWIDTH ~FAIR_GROUP_SCHED ~RT_GROUP_SCHED
	~IP_VS ~IP_VS_PROTO_TCP ~IP_VS_PROTO_UDP ~IP_VS_NFCT ~IP_VS_RR

	~VXLAN
	~CRYPTO ~CRYPTO_AEAD ~CRYPTO_GCM ~CRYPTO_SEQIV ~CRYPTO_GHASH ~XFRM_ALGO ~XFRM_USER
	~IPVLAN
	~MACVLAN ~DUMMY
"

ERROR_KEYS="CONFIG_KEYS: is mandatory"
ERROR_MEMCG_SWAP="CONFIG_MEMCG_SWAP: is required if you wish to limit swap usage of containers"
ERROR_RESOURCE_COUNTERS="CONFIG_RESOURCE_COUNTERS: is optional for container statistics gathering"

ERROR_BLK_CGROUP="CONFIG_BLK_CGROUP: is optional for container statistics gathering"
ERROR_IOSCHED_CFQ="CONFIG_IOSCHED_CFQ: is optional for container statistics gathering"
ERROR_CGROUP_PERF="CONFIG_CGROUP_PERF: is optional for container statistics gathering"
ERROR_CFS_BANDWIDTH="CONFIG_CFS_BANDWIDTH: is optional for container statistics gathering"
ERROR_XFRM_ALGO="CONFIG_XFRM_ALGO: is optional for secure networks"
ERROR_XFRM_USER="CONFIG_XFRM_USER: is optional for secure networks"

pkg_setup() {
	if kernel_is lt 3 10; then
		ewarn ""
		ewarn "Using Docker with kernels older than 3.10 is unstable and unsupported."
		ewarn " - http://docs.docker.com/engine/installation/binaries/#check-kernel-dependencies"
	fi

	if kernel_is le 3 18; then
		CONFIG_CHECK+="
			~RESOURCE_COUNTERS
		"
	fi

	if kernel_is le 3 13; then
		CONFIG_CHECK+="
			~NETPRIO_CGROUP
		"
	else
		CONFIG_CHECK+="
			~CGROUP_NET_PRIO
		"
	fi

	if kernel_is lt 4 5; then
		CONFIG_CHECK+="
			~MEMCG_KMEM
		"
		ERROR_MEMCG_KMEM="CONFIG_MEMCG_KMEM: is optional"
	fi

	if kernel_is lt 4 7; then
		CONFIG_CHECK+="
			~DEVPTS_MULTIPLE_INSTANCES
		"
	fi

	if use aufs; then
		CONFIG_CHECK+="
			~AUFS_FS
			~EXT4_FS_POSIX_ACL ~EXT4_FS_SECURITY
		"
		ERROR_AUFS_FS="CONFIG_AUFS_FS: is required to be set if and only if aufs-sources are used instead of aufs4/aufs3"
	fi

	if use btrfs; then
		CONFIG_CHECK+="
			~BTRFS_FS
			~BTRFS_FS_POSIX_ACL
		"
	fi

	if use device-mapper; then
		CONFIG_CHECK+="
			~BLK_DEV_DM ~DM_THIN_PROVISIONING ~EXT4_FS ~EXT4_FS_POSIX_ACL ~EXT4_FS_SECURITY
		"
	fi

	if use overlay; then
		CONFIG_CHECK+="
			~OVERLAY_FS ~EXT4_FS_SECURITY ~EXT4_FS_POSIX_ACL
		"
	fi

	linux-info_pkg_setup

	# create docker group for the code checking for it in /etc/group
	enewgroup docker
}

src_unpack() {
	if [ -n "$DOCKER_GITCOMMIT" ]; then
		mkdir -p "${S}"
		tar --strip-components=1 -C "${S}" -xf "${DISTDIR}/${A}"
		DOCKER_BUILD_DATE=$(date --reference="${S}/VERSION" +%s)
	else
		git-r3_src_unpack
		DOCKER_GITCOMMIT=$(git -C "${S}" rev-parse HEAD | head -c 7)
		DOCKER_BUILD_DATE=$(git -C "${S}" log -1 --format="%ct")
	fi
	[ "${#ENGINE_PATCHES[@]}" -gt 0 ] && eapply -d"${S}"/components/engine "${ENGINE_PATCHES[@]}"
}

src_compile() {
	local -x DISABLE_WARN_OUTSIDE_CONTAINER=1
	go_export
	export GOPATH="${WORKDIR}/${P}"

	# setup CFLAGS and LDFLAGS for separate build target
	# see https://github.com/tianon/docker-overlay/pull/10
	export CGO_CFLAGS="${CGO_CFLAGS} -I${ROOT}/usr/include"
	export CGO_LDFLAGS="${CGO_LDFLAGS} -L${ROOT}/usr/$(get_libdir)"

	# if we're building from a tarball, we need the GITCOMMIT value
	[ "$DOCKER_GITCOMMIT" ] && export DOCKER_GITCOMMIT

	# fake golang layout
	ln -s docker-ce/components/engine ../docker || die
	ln -s docker-ce/components/cli ../cli || die

	# let's set up some optional features :)
	export DOCKER_BUILDTAGS=''
	for gd in aufs btrfs device-mapper overlay; do
		if ! use $gd; then
			DOCKER_BUILDTAGS+=" exclude_graphdriver_${gd//-/}"
		fi
	done

	for tag in apparmor pkcs11 seccomp selinux journald; do
		if use $tag; then
			DOCKER_BUILDTAGS+=" $tag"
		fi
	done

	pushd components/engine || die

	if use hardened; then
		sed -i "s#EXTLDFLAGS_STATIC='#&-fno-PIC $LDFLAGS #" hack/make.sh || die
		grep -q -- '-fno-PIC' hack/make.sh || die 'hardened sed failed'
		sed  "s#LDFLAGS_STATIC_DOCKER='#&-extldflags \"-fno-PIC $LDFLAGS\" #" \
			-i hack/make/dynbinary-daemon || die
		grep -q -- '-fno-PIC' hack/make/dynbinary-daemon || die 'hardened sed failed'
	fi

	# build daemon
	SOURCE_DATE_EPOCH="${DOCKER_BUILD_DATE}" \
	VERSION="$(<../../VERSION)" \
	./hack/make.sh dynbinary || die 'dynbinary failed'

	popd || die # components/engine

	pushd components/cli || die

	# Imitating https://github.com/docker/docker-ce/blob/v18.06.2-ce/components/cli/scripts/build/.variables#L7
	CLI_BUILDTIME="$(date -d "@${DOCKER_BUILD_DATE}" --utc --rfc-3339 ns 2> /dev/null | sed -e 's/ /T/')"
	# build cli
	emake \
		BUILDTIME="${CLI_BUILDTIME}" \
		LDFLAGS="$(usex hardened "-extldflags \"-fno-PIC $LDFLAGS\"" '')" \
		VERSION="$(cat ../../VERSION)" \
		GITCOMMIT="${DOCKER_GITCOMMIT}" \
		DISABLE_WARN_OUTSIDE_CONTAINER=1 \
		dynbinary || die

	popd || die # components/cli
}

src_install() {
	dosym containerd /usr/bin/docker-containerd
	dosym containerd-shim /usr/bin/docker-containerd-shim
	dosym runc /usr/bin/docker-runc
	use container-init && dosym tini /usr/bin/docker-init

	pushd components/engine || die
	newbin "$(readlink -f bundles/latest/dynbinary-daemon/dockerd)" dockerd

	newinitd contrib/init/openrc/docker.initd docker
	newconfd contrib/init/openrc/docker.confd docker

	exeinto /usr/lib/coreos
	# Create /usr/lib/coreos/dockerd for backwards compatibility
	doexe "${FILESDIR}/dockerd"

	systemd_dounit "${FILESDIR}/docker.service"
	systemd_dounit "${FILESDIR}/docker.socket"

	insinto /usr/lib/systemd/network
	doins "${FILESDIR}"/50-docker.network
	doins "${FILESDIR}"/90-docker-veth.network

	udev_dorules contrib/udev/*.rules

	dodoc AUTHORS CONTRIBUTING.md CHANGELOG.md NOTICE README.md
	dodoc -r docs/*

	insinto /usr/share/vim/vimfiles
	doins -r contrib/syntax/vim/ftdetect
	doins -r contrib/syntax/vim/syntax
	popd || die # components/engine

	pushd components/cli || die

	newbin build/docker-* docker

	dobashcomp contrib/completion/bash/*
	insinto /usr/share/zsh/site-functions
	doins contrib/completion/zsh/_*
	popd || die # components/cli
}

pkg_postinst() {
	udev_reload

	elog
	elog "To use Docker, the Docker daemon must be running as root. To automatically"
	elog "start the Docker daemon at boot, add Docker to the default runlevel:"
	elog "  rc-update add docker default"
	elog "Similarly for systemd:"
	elog "  systemctl enable docker.service"
	elog
	elog "To use Docker as a non-root user, add yourself to the 'docker' group:"
	elog "  usermod -aG docker youruser"
	elog
}
