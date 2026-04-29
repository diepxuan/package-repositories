#!/usr/bin/env bash
#!/bin/bash

set -e
# set -u

export DEBIAN_FRONTEND=noninteractive

# Usage:
#   error MESSAGE
error() {
    echo "::error::$*"
}

# Usage:
#   end_group
end_group() {
    echo "::endgroup::"
}

# Usage:
#   start_group GROUP_NAME
start_group() {
    echo "::group::$*"
}

env() {
    GITHUB_ENV=${GITHUB_ENV:-.env}
    param=$1
    value="${@:2}"
    grep -q "^$param=" $GITHUB_ENV &&
        sed -i "s|^$param=.*|$param=$value|" $GITHUB_ENV ||
        echo "$param=$value" >>$GITHUB_ENV
    export $param="$value"
    echo $param: $value
}
# SUDO=sudo
# command -v sudo &>/dev/null || SUDO=''
run_as_sudo() {
    _SUDO=sudo
    command -v sudo &>/dev/null || _SUDO=''
    echo "Running as sudo: $*"
    if [[ $EUID -ne 0 ]]; then
        $_SUDO $@
    else
        $@
    fi
}
SUDO=${SUDO:-'run_as_sudo'}

start_group Dynamically set environment variable
# directory
env source_dir $(dirname $(realpath "$BASH_SOURCE"))
env source_var $(realpath $source_dir/var)
env source_lib $(realpath $source_dir/var/lib)
env debian_dir $(realpath $source_dir/debian)
env build_dir $(realpath $source_dir/build)
env pwd_dir $(realpath $(dirname $source_dir))
env dists_dir $(realpath $pwd_dir/dists)
env ppa_dir $(realpath $pwd_dir/ppa)

# user evironment
env email ductn@diepxuan.com
env DEBEMAIL ductn@diepxuan.com
env EMAIL ductn@diepxuan.com
env DEBFULLNAME Tran Ngoc Duc
env NAME Tran Ngoc Duc
env GIT_COMMITTER_MESSAGE $GIT_COMMITTER_MESSAGE

# gpg key
env GPG_KEY_ID $GPG_KEY_ID
env GPG_KEY $GPG_KEY
env DEB_SIGN_KEYID $DEB_SIGN_KEYID

# debian
env changelog $(realpath $debian_dir/changelog)
env control $(realpath $debian_dir/control)
env controlin $(realpath $debian_dir/control.in)
env rules $(realpath $debian_dir/rules)
env timelog "$(Lang=C date -R)"

# plugin
env repository ${repository:-diepxuan/$MODULE}
env owner $(echo $repository | cut -d '/' -f1)
env project $(echo $repository | cut -d '/' -f2)
env module $(echo $project | sed 's/^php-//g')

REPO_URL="https://ppa.diepxuan.com/"

# os evironment
[[ -f /etc/os-release ]] && . /etc/os-release
[[ -f /etc/lsb-release ]] && . /etc/lsb-release
CODENAME=${CODENAME:-$DISTRIB_CODENAME}
CODENAME=${CODENAME:-$VERSION_CODENAME}
CODENAME=${CODENAME:-$UBUNTU_CODENAME}

RELEASE=${RELEASE:-$(echo $DISTRIB_DESCRIPTION | awk '{print $2}')}
RELEASE=${RELEASE:-$(echo $VERSION | awk '{print $1}')}
RELEASE=${RELEASE:-$(echo $PRETTY_NAME | awk '{print $2}')}
RELEASE=${RELEASE:-${DISTRIB_RELEASE}}
RELEASE=${RELEASE:-${VERSION_ID}}
# RELEASE=$(echo "$RELEASE" | awk -F. '{print $1"."$2}')
RELEASE=$(echo "$RELEASE" | cut -d. -f1-2)
RELEASE=$(echo "$RELEASE" | tr '[:upper:]' '[:lower:]')
RELEASE=${RELEASE//[[:space:]]/}
RELEASE=${RELEASE%.}

DISTRIB=${DISTRIB:-$DISTRIB_ID}
DISTRIB=${DISTRIB:-$ID}
DISTRIB=$(echo "$DISTRIB" | tr '[:upper:]' '[:lower:]')

env CODENAME $CODENAME
env RELEASE $RELEASE
env DISTRIB $DISTRIB
end_group

cd $source_dir

start_group Install Build Source Dependencies
APT_CONF_FILE=/etc/apt/apt.conf.d/50build-deb-action

cat | $SUDO tee "$APT_CONF_FILE" <<-EOF
APT::Get::Assume-Yes "yes";
APT::Install-Recommends "no";
Acquire::Languages "none";
quiet "yes";
EOF

# debconf has priority “required” and is indirectly depended on by some
# essential packages. It is reasonably safe to blindly assume it is installed.
printf "man-db man-db/auto-update boolean false\n" | $SUDO debconf-set-selections

$SUDO apt update || true
$SUDO apt-get install -y build-essential debhelper fakeroot gnupg reprepro wget curl git sudo locales
$SUDO apt-get install -y lsb-release ca-certificates curl jq

$SUDO apt update || true
# In theory, explicitly installing dpkg-dev would not be necessary. `apt-get
# build-dep` will *always* install build-essential which depends on dpkg-dev.
# But let’s be explicit here.
# shellcheck disable=SC2086
$SUDO apt install -y debhelper-compat dpkg-dev libdpkg-perl dput tree devscripts
$SUDO apt install -y libdistro-info-perl
$SUDO apt install $INPUT_APT_OPTS -- $INPUT_EXTRA_BUILD_DEPS

# shellcheck disable=SC2086
# Copy control.in to control if exists
[[ -f $controlin ]] && cat $controlin | tee $control
$SUDO apt build-dep $INPUT_APT_OPTS -- "$source_dir" || true
end_group

start_group "GPG/SSH Configuration"
if ! gpg --list-keys --with-colons | grep -q "fpr"; then
    echo "$GPG_KEY====" | tr -d '\n' | fold -w 4 | sed '$ d' | tr -d '\n' | fold -w 76 | base64 -di | gpg --batch --import || true
fi

# Lặp qua từng key và chỉnh sửa
# Cập nhật expiration date của subkey
gpg --batch --command-fd 0 --edit-key "$GPG_KEY_ID" <<EOF
key 1
expire
0
save
EOF

# Cập nhật expiration date của key chính
gpg --batch --command-fd 0 --edit-key "$GPG_KEY_ID" <<EOF
expire
0
save
EOF

# Đặt key thành Ultimate Trust
gpg --batch --command-fd 0 --edit-key "$GPG_KEY_ID" <<EOF
trust
5
save
EOF

gpg --list-secret-keys --keyid-format=long
mkdir -p "$source_dir/usr/share/keyrings"
gpg --export "$GPG_KEY_ID" > "$source_dir/usr/share/keyrings/diepxuan.gpg"

if gpg --list-secret-keys --keyid-format=long | grep -q "sec"; then
    export DEB_SIGN_KEYID=$(gpg --list-keys --with-colons --fingerprint | awk -F: '/fpr:/ {print $10; exit}')
fi
gpg --list-secret-keys --keyid-format=long
end_group

start_group Update APT Source
mkdir -p "$source_dir/etc/apt/sources.list.d"
echo "deb [signed-by=/usr/share/keyrings/diepxuan.gpg] $REPO_URL $CODENAME main" | $SUDO tee $source_dir/etc/apt/sources.list.d/diepxuan.list
end_group

start_group View Source Code
echo $source_dir
ls -la $source_dir
echo $debian_dir
ls -la $debian_dir
end_group

start_group Update Package Configuration in Changelog
# Determine release_tag and package_clog from GitHub events or fallback to changelog

# Helper function to check if string is empty or only contains whitespace
is_empty_or_whitespace() {
    local str="$1"
    [[ -z "${str// }" ]] && [[ -z "${str//\t}" ]] && [[ -z "${str//\n}" ]] && return 0
    return 1
}

# Check if triggered by GitHub release event
if [[ -n "$GITHUB_EVENT_NAME" ]]; then
    if [[ "$GITHUB_EVENT_NAME" == "release" ]] || [[ "$GITHUB_EVENT_NAME" == "push" ]] || [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]; then
        # Try to get release info from GitHub API
        REPO_OWNER=$(echo $repository | cut -d '/' -f1)
        REPO_NAME=$(echo $repository | cut -d '/' -f2)
        
        # Get latest release or specific release
        if [[ -n "$GITHUB_REF" && "$GITHUB_REF" == refs/tags/* ]]; then
            TAG_NAME=${GITHUB_REF#refs/tags/}
            RELEASE_INFO=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${TAG_NAME}")
        else
            RELEASE_INFO=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest")
        fi
        
        # Extract release_tag (version) from release
        if [[ -n "$RELEASE_INFO" ]]; then
            RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//')
            # RELEASE_TAG=$(echo "$RELEASE_INFO" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4 | sed 's/^v//')
            RELEASE_BODY=$(echo "$RELEASE_INFO" | jq -r '.body // empty' 2>/dev/null || echo "")
            # RELEASE_BODY=${RELEASE_BODY:-$(echo "$RELEASE_INFO" | grep -o '"body": "[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g; s/\\r//g')}
            
            if ! is_empty_or_whitespace "$RELEASE_TAG"; then
                release_tag="$RELEASE_TAG"
                echo "release_tag from GitHub: $release_tag"
            fi
            
            if ! is_empty_or_whitespace "$RELEASE_BODY"; then
                package_clog="$RELEASE_BODY"
                echo "package_clog from GitHub release: $package_clog"
            fi
        fi
    fi
fi

# Fallback to changelog if not set
release_tag=${release_tag:-$(cat $changelog | head -n 1 | awk '{print $2}' | sed 's|[()]||g')}

# Get changelog notes (line 3 to before the -- line)
CHANGELOG_NOTES=$(cat $changelog | head -n 1 | sed -n '3,/-- /p' | sed '3,$d' | sed 's/^[ \t]*//;s/[ \t]*$//')
is_empty_or_whitespace "$package_clog" && package_clog=$CHANGELOG_NOTES
is_empty_or_whitespace "$package_clog" && package_clog='Update package'

echo "release_tag: $release_tag+$DISTRIB~$RELEASE"
echo "package_clog: $package_clog"
dch --newversion $release_tag+$DISTRIB~$RELEASE --distribution $CODENAME "$package_clog" -b
end_group

start_group Show log
echo $control
cat $control || true
echo $controlin
cat $controlin || true
echo $rules
cat $rules || true
end_group

start_group Show changelog
cat $changelog
end_group

start_group Show package changelog
echo $package_clog
end_group

start_group log GPG key before build
gpg --list-secret-keys --keyid-format=long
end_group

start_group Building package binary
dpkg-parsechangelog
# shellcheck disable=SC2086
dpkg-buildpackage --force-sign || dpkg-buildpackage --force-sign -d
# shellcheck disable=SC2086
dpkg-buildpackage --force-sign -S || dpkg-buildpackage --force-sign -S -d
end_group

start_group Move build artifacts
regex='^php.*(.deb|.ddeb|.buildinfo|.changes|.dsc|.tar.xz|.tar.gz|.tar.[[:alpha:]]+)$'
regex='.*(.deb|.ddeb|.buildinfo|.changes|.dsc|.tar.xz|.tar.gz|.tar.[[:alpha:]]+)$'
mkdir -p $dists_dir

while read -r file; do
    mv -vf "$source_dir/$file" "$dists_dir/" || true
done < <(ls $source_dir/ | grep -E $regex)

while read -r file; do
    mv -vf "$pwd_dir/$file" "$dists_dir/" || true
done < <(ls $pwd_dir/ | grep -E $regex)

ls -la $dists_dir
end_group

start_group Publish Package to Launchpad
cat | tee ~/.dput.cf <<-EOF
[caothu91ppa]
fqdn = ppa.launchpad.net
method = ftp
incoming = ~caothu91/ubuntu/ppa/
login = anonymous
allow_unsigned_uploads = 0
EOF

# package=$(ls -a $dists_dir | grep _source.changes | head -n 1)

# [[ -n $package ]] &&
#     package=$dists_dir/$package &&
#     [[ -f $package ]] &&
#     dput caothu91ppa $package || true

while read -r package; do
    dput caothu91ppa $dists_dir/$package || true
done < <(ls $dists_dir | grep -E '.*(_source.changes)$')
end_group
