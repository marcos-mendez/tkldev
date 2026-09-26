#!/usr/bin/env bats
# Tests for overlay/usr/local/sbin/tkldev-setup.
#
# Every external command the script runs (git, wget, apt-get, make,
# lsb_release, turnkey-version, dpkg, id, signature-verify) is replaced by a
# stub from tests/stubs that records its arguments in STUB_LOG, and every
# path the script writes is under a scratch directory. Nothing here touches
# the live system or the network.
#
# Two kinds of tests: "run_setup" executes the whole script (option parsing
# and the main body), "call" sources it inside a fresh "bash -e" and runs one
# function, as the script itself would.

setup() {
    TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT="$TESTS_DIR/../overlay/usr/local/sbin/tkldev-setup"
    SCRATCH="$BATS_TEST_TMPDIR"

    export PATH="$TESTS_DIR/stubs:$PATH"
    export STUB_LOG="$SCRATCH/calls.log"
    : > "$STUB_LOG"
    export STUB_REFS="19.x master"
    export STUB_GIT_BRANCH="19.x"
    unset STUB_GIT_STATUS STUB_GIT_FAIL STUB_WGET_FAIL STUB_MAKE_NO_BOOTSTRAP
    unset STUB_DISTRO STUB_CODENAME STUB_TKL_VERSION STUB_ARCH STUB_UID
    unset STUB_VERIFY_RC

    export FAB_PATH="$SCRATCH/fab"
    export BT_PATH="$SCRATCH/buildtasks"
    export TKLBAM_PATH="$SCRATCH/tklbam-profiles"
    unset RELEASE FAB_ARCH BRANCH GIT_DEPTH GIT_REMOTE_URL GIT_REMOTE_NAME
    unset BT_REFS TKLBAM_REFS COMMON_REFS APP_REFS CDROOTS_REFS
    unset DEBUG BT_DEBUG STRICT FORCE TRANSITION

    # buildtasks checked out, with the example config and the verify script
    make_git_dir "$BT_PATH"
    mkdir -p "$BT_PATH/config.example" "$BT_PATH/bin"
    echo 'BT_GPGKEY=DEADBEEF' > "$BT_PATH/config.example/common.cfg"
    cp "$TESTS_DIR/stubs/signature-verify" "$BT_PATH/bin/signature-verify"

    # variables the functions read when called on their own
    export RELEASE_UNDER_TEST="debian/trixie"
    export BOOTSTRAP_NAME="bootstrap-trixie-amd64"
    export BOOTSTRAP_PATH="$FAB_PATH/bootstraps/trixie-amd64"
    export BT_VERIFY="$BT_PATH/bin/signature-verify"
    export IMAGES="http://mirror.turnkeylinux.org/turnkeylinux/images"
    export GIT_REMOTE_URL="https://github.com/turnkeylinux"
    export APP_GIT_REMOTE_URL="https://github.com/turnkeylinux-apps"
    export GIT_DEPTH=1
}

make_git_dir() {
    mkdir -p "$1/.git"
}

make_bootstrap() {
    mkdir -p "$1/bin"
    echo '#!/bin/sh' > "$1/bin/bash"
}

# run the whole script
run_setup() {
    run "$SCRIPT" "$@"
}

# run one function of the script in a fresh bash -e, as the script does
call() {
    run bash -e -c 'source "$1"; shift; "$@"' tkldev-setup-test "$SCRIPT" "$@"
}

logged() {
    grep -qF -- "$1" "$STUB_LOG"
}

not_logged() {
    ! grep -qF -- "$1" "$STUB_LOG"
}

output_has() {
    [[ "$output" == *"$1"* ]]
}

# --- options ----------------------------------------------------------------

@test "-h prints the usage and exits 0" {
    run_setup -h
    [ "$status" -eq 0 ]
    output_has "Tool to initialize and maintain TKLDev"
    output_has "FAB_PATH        Fab PATH (default: $FAB_PATH)"
    output_has "TKLBAM_PATH     tklbam-profiles PATH (default: $TKLBAM_PATH)"
    not_logged "git clone"
}

@test "--help is the same as -h" {
    run_setup --help
    [ "$status" -eq 0 ]
    output_has "Options:"
    not_logged "git clone"
}

@test "without arguments core is the only appliance" {
    run_setup
    [ "$status" -eq 0 ]
    logged "git clone --branch 19.x --depth 1 https://github.com/turnkeylinux-apps/core.git $FAB_PATH/products/core"
    logged "https://github.com/turnkeylinux/tklbam-profiles.git $TKLBAM_PATH"
    logged "https://github.com/turnkeylinux/common.git $FAB_PATH/common"
    logged "https://github.com/turnkeylinux/cdroots.git $FAB_PATH/cdroots"
    [ "$(grep -c 'products/' "$STUB_LOG")" -eq 1 ]
}

@test "every argument is processed as an appliance" {
    run_setup foo bar
    [ "$status" -eq 0 ]
    logged "turnkeylinux-apps/foo.git $FAB_PATH/products/foo"
    logged "turnkeylinux-apps/bar.git $FAB_PATH/products/bar"
    not_logged "products/core"
}

@test "an unknown option is taken as an appliance name" {
    run_setup --bogus
    [ "$status" -eq 0 ]
    logged "turnkeylinux-apps/--bogus.git $FAB_PATH/products/--bogus"
}

@test "clones are shallow by default" {
    run_setup
    [ "$status" -eq 0 ]
    logged "git clone --branch 19.x --depth 1 https://github.com/turnkeylinux/common.git"
}

@test "-n clones without --depth" {
    run_setup -n
    [ "$status" -eq 0 ]
    logged "git clone --branch 19.x https://github.com/turnkeylinux/common.git"
    not_logged "--depth"
}

@test "--full-clone is the same as -n" {
    run_setup --full-clone
    [ "$status" -eq 0 ]
    not_logged "--depth"
}

@test "a dirty repo is skipped with a warning by default" {
    export STUB_GIT_STATUS=" M bin/signature-verify"
    run_setup
    [ "$status" -eq 0 ]
    output_has "WARNING [tkldev-setup]: $BT_PATH has uncommitted files, skipping."
}

@test "-s fails on a dirty repo instead of skipping" {
    export STUB_GIT_STATUS=" M bin/signature-verify"
    run_setup -s
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup]: $BT_PATH has uncommitted files"
    not_logged "git clone"
}

@test "--strict is the same as -s" {
    export STUB_GIT_STATUS=" M bin/signature-verify"
    run_setup --strict
    [ "$status" -eq 1 ]
}

@test "-f checks out the resolved branch when another one is checked out" {
    export STUB_GIT_BRANCH=master
    run_setup -f
    [ "$status" -eq 0 ]
    output_has "Force used - attempting to checkout 19.x"
    logged "git -C $BT_PATH checkout 19.x"
    logged "git -C $BT_PATH pull origin 19.x"
}

@test "--force is the same as -f" {
    export STUB_GIT_BRANCH=master
    run_setup --force
    [ "$status" -eq 0 ]
    logged "git -C $BT_PATH checkout 19.x"
}

@test "-t skips a bootstrap that cannot be downloaded" {
    export STUB_WGET_FAIL=all
    run_setup -t
    [ "$status" -eq 0 ]
    output_has "Failed download: bootstrap-trixie-amd64.tar.gz - skipping due to transition"
    not_logged "make"
}

@test "--transition is the same as -t" {
    export STUB_WGET_FAIL=all
    run_setup --transition
    [ "$status" -eq 0 ]
    not_logged "make"
}

# --- main body --------------------------------------------------------------

@test "fails when not run as root" {
    export STUB_UID=1000
    run_setup
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup]: Root user required."
    not_logged "lsb_release"
}

@test "DEBUG and BT_DEBUG turn on tracing" {
    DEBUG=1 run_setup
    [ "$status" -eq 0 ]
    BT_DEBUG=1 run_setup
    [ "$status" -eq 0 ]
}

@test "release and architecture come from the system" {
    export STUB_WGET_FAIL=all
    run_setup
    [ "$status" -eq 0 ]
    logged "wget -nc -nv $IMAGES/bootstrap/bootstrap-trixie-amd64.tar.gz"
    logged "make -C $SCRATCH/bootstrap install FAB_PATH=$FAB_PATH RELEASE=debian/trixie FAB_ARCH=amd64"
}

@test "a distro other than TurnKey or Debian keeps its own name" {
    export STUB_DISTRO=Ubuntu STUB_CODENAME=noble STUB_WGET_FAIL=all
    run_setup
    [ "$status" -eq 0 ]
    logged "RELEASE=Ubuntu/noble FAB_ARCH=amd64"
    logged "bootstrap-noble-amd64.tar.gz"
}

@test "the series branch comes from turnkey-version" {
    export STUB_TKL_VERSION=18.2 STUB_REFS="18.x"
    run_setup
    [ "$status" -eq 0 ]
    logged "git clone --branch 18.x --depth 1 https://github.com/turnkeylinux/common.git"
}

@test "on arm64 cdroots is not cloned" {
    export STUB_ARCH=arm64
    run_setup
    [ "$status" -eq 0 ]
    not_logged "cdroots"
    logged "bootstrap-trixie-arm64.tar.gz"
}

@test "the example config is copied when config is missing" {
    run_setup
    [ "$status" -eq 0 ]
    [ -f "$BT_PATH/config/common.cfg" ]
}

@test "an existing config is kept" {
    mkdir -p "$BT_PATH/config"
    echo 'BT_GPGKEY=CAFEBABE' > "$BT_PATH/config/common.cfg"
    run_setup
    [ "$status" -eq 0 ]
    grep -q CAFEBABE "$BT_PATH/config/common.cfg"
}

@test "fails when config/common.cfg is missing" {
    mkdir -p "$BT_PATH/config"
    run_setup
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup]: $BT_PATH config not found"
    not_logged "apt-get"
}

@test "a remote outside turnkeylinux is used unchanged for appliances" {
    export GIT_REMOTE_URL="https://[2001:db8::1]/mirror/"
    run_setup
    [ "$status" -eq 0 ]
    logged "https://[2001:db8::1]/mirror/common.git"
    logged "https://[2001:db8::1]/mirror/core.git"
    not_logged "mirror//"
    not_logged "mirror-apps"
}

@test "apt is updated and fab installed" {
    run_setup
    [ "$status" -eq 0 ]
    logged "apt-get update -qq"
    logged "apt-get install -y fab"
    output_has "INFO [tkldev-setup]: tkldev-setup complete."
}

# --- resolve_ref ------------------------------------------------------------

@test "resolve_ref returns the first candidate that exists on the remote" {
    export STUB_REFS="19.x-dev master"
    call resolve_ref "$GIT_REMOTE_URL/common" 19.x 19.x-dev master
    [ "$status" -eq 0 ]
    [ "$output" = "19.x-dev" ]
    logged "git ls-remote --exit-code --heads $GIT_REMOTE_URL/common 19.x"
    logged "git ls-remote --exit-code --heads $GIT_REMOTE_URL/common 19.x-dev"
    not_logged "common master"
}

@test "resolve_ref skips empty candidates and fails when none exists" {
    export STUB_REFS=""
    call resolve_ref "$GIT_REMOTE_URL/common" "" 19.x
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    not_logged "common $"
    logged "common 19.x"
}

# --- update_repo ------------------------------------------------------------

@test "update_repo fetches and pulls a clean repo on the right branch" {
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    logged "git -C $BT_PATH remote --verbose"
    logged "git -C $BT_PATH fetch origin"
    logged "git -C $BT_PATH pull origin 19.x"
    not_logged "checkout"
}

@test "update_repo skips a dirty repo with a warning" {
    export STUB_GIT_STATUS="?? new-file"
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "WARNING [tkldev-setup-test]: $BT_PATH has uncommitted files, skipping."
    not_logged "fetch"
}

@test "update_repo fails on a dirty repo with --strict" {
    export STUB_GIT_STATUS="?? new-file" STRICT=true
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: $BT_PATH has uncommitted files"
}

@test "update_repo skips when the fetch fails" {
    export STUB_GIT_FAIL=fetch
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "($BT_PATH) Fetching remote: origin failed, skipping."
    not_logged "pull"
}

@test "update_repo fails when the fetch fails with --strict" {
    export STUB_GIT_FAIL=fetch STRICT=true
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: ($BT_PATH) Fetching remote: origin failed"
}

@test "update_repo uses the current branch when none is given" {
    export STUB_GIT_BRANCH=master
    call update_repo "$BT_PATH" ""
    [ "$status" -eq 0 ]
    logged "git -C $BT_PATH pull origin master"
    not_logged "checkout"
}

@test "update_repo skips a repo on an alternate branch" {
    export STUB_GIT_BRANCH=my-feature
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "($BT_PATH) checked out branch is my-feature (not 19.x) so skipping"
    not_logged "pull"
}

@test "update_repo fails on an alternate branch with --strict" {
    export STUB_GIT_BRANCH=my-feature STRICT=true
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: ($BT_PATH) checked out branch is my-feature (not 19.x)"
}

@test "update_repo checks out the branch with --force" {
    export STUB_GIT_BRANCH=my-feature FORCE=y
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    logged "git -C $BT_PATH checkout 19.x"
    not_logged "checkout 19.x-dev"
    logged "git -C $BT_PATH pull origin 19.x"
}

@test "update_repo with --force falls back to the -dev branch" {
    export STUB_GIT_BRANCH=my-feature FORCE=y STUB_GIT_FAIL="checkout:19.x"
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    logged "git -C $BT_PATH checkout 19.x-dev"
    logged "git -C $BT_PATH pull origin 19.x"
}

@test "update_repo with --force skips when neither checkout works" {
    export STUB_GIT_BRANCH=my-feature FORCE=y STUB_GIT_FAIL=checkout
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "($BT_PATH) Checking out '19.x' failed, skipping."
    not_logged "pull"
}

@test "update_repo moves from the series dev branch to the release branch" {
    export STUB_GIT_BRANCH=19.x-dev
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "current checked out branch is 19.x-dev  attempting to checkout 19.x"
    logged "git -C $BT_PATH checkout 19.x"
    logged "git -C $BT_PATH pull origin 19.x"
}

@test "update_repo skips when leaving the dev branch fails" {
    export STUB_GIT_BRANCH=19.x-dev STUB_GIT_FAIL=checkout
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "($BT_PATH) checkout failed - skipping"
    not_logged "pull"
}

@test "update_repo fails when leaving the dev branch fails with --strict" {
    export STUB_GIT_BRANCH=19.x-dev STUB_GIT_FAIL=checkout STRICT=true
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: ($BT_PATH) checkout failed"
}

@test "update_repo pulls the requested branch from another series without checkout" {
    export STUB_GIT_BRANCH=18.x
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    not_logged "checkout"
    logged "git -C $BT_PATH pull origin 19.x"
}

@test "update_repo skips when the pull fails" {
    export STUB_GIT_FAIL=pull
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 0 ]
    output_has "($BT_PATH) Updating '19.x' failed, skipping."
}

@test "update_repo fails when the pull fails with --strict" {
    export STUB_GIT_FAIL=pull STRICT=true
    call update_repo "$BT_PATH" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: ($BT_PATH) Updating '19.x' failed"
}

# --- clone_or_update --------------------------------------------------------

@test "clone_or_update updates an existing git checkout" {
    call clone_or_update buildtasks "$BT_PATH" 19.x master
    [ "$status" -eq 0 ]
    output_has "INFO [tkldev-setup-test]: Resolved buildtasks to ref: 19.x"
    output_has "$BT_PATH exists and is a git repo, attempting update."
    logged "git -C $BT_PATH pull origin 19.x"
    not_logged "clone"
}

@test "clone_or_update fails when the destination is not a git repo" {
    mkdir -p "$SCRATCH/plain"
    call clone_or_update common "$SCRATCH/plain" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: $SCRATCH/plain exists, but is not a git repo."
}

@test "clone_or_update clones a missing destination with the resolved ref and depth" {
    call clone_or_update common "$FAB_PATH/common" 19.x master
    [ "$status" -eq 0 ]
    output_has "Attempting to clone $GIT_REMOTE_URL/common into $FAB_PATH/common."
    logged "git clone --branch 19.x --depth 1 $GIT_REMOTE_URL/common.git $FAB_PATH/common"
    [ -d "$FAB_PATH/common/.git" ]
}

@test "clone_or_update clones fully when GIT_DEPTH is full" {
    export GIT_DEPTH=full
    call clone_or_update common "$FAB_PATH/common" 19.x
    [ "$status" -eq 0 ]
    logged "git clone --branch 19.x $GIT_REMOTE_URL/common.git $FAB_PATH/common"
}

@test "clone_or_update falls back to the default branch when no ref resolves" {
    export STUB_REFS=""
    call clone_or_update common "$FAB_PATH/common" 19.x master
    [ "$status" -eq 0 ]
    output_has "Could not resolve preferred refs for common; falling back to repo default branch."
    logged "git clone --depth 1 $GIT_REMOTE_URL/common.git $FAB_PATH/common"
}

@test "clone_or_update fails when no ref resolves with --strict" {
    export STUB_REFS="" STRICT=true
    call clone_or_update common "$FAB_PATH/common" 19.x master
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: Could not resolve preferred refs for common"
    not_logged "clone"
}

@test "clone_or_update uses the apps remote for _APP_" {
    call clone_or_update _APP_ core "$FAB_PATH/products/core" 19.x
    [ "$status" -eq 0 ]
    logged "git clone --branch 19.x --depth 1 $APP_GIT_REMOTE_URL/core.git $FAB_PATH/products/core"
}

@test "clone_or_update fails when the clone fails" {
    export STUB_GIT_FAIL=clone
    call clone_or_update common "$FAB_PATH/common" 19.x
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: Cloning $FAB_PATH/common failed."
}

# --- setup_bootstrap and build_bootstrap -------------------------------------

@test "setup_bootstrap skips the download when the bootstrap exists" {
    make_bootstrap "$BOOTSTRAP_PATH"
    call setup_bootstrap
    [ "$status" -eq 0 ]
    output_has "$BOOTSTRAP_PATH exists, skipping download."
    not_logged "wget"
}

@test "setup_bootstrap fails when the directory is not a bootstrap" {
    mkdir -p "$BOOTSTRAP_PATH"
    call setup_bootstrap
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: $BOOTSTRAP_PATH exists, but does not appear to be a bootstrap"
}

@test "setup_bootstrap downloads, verifies and unpacks the bootstrap" {
    call setup_bootstrap
    [ "$status" -eq 0 ]
    output_has "INFO [tkldev-setup-test]: Downloading bootstrap-trixie-amd64"
    logged "wget -nc -nv $IMAGES/bootstrap/bootstrap-trixie-amd64.tar.gz"
    logged "wget -nc -nv $IMAGES/bootstrap/bootstrap-trixie-amd64.tar.gz.hash"
    logged "signature-verify --force-gpg $FAB_PATH/bootstraps/bootstrap-trixie-amd64.tar.gz $FAB_PATH/bootstraps/bootstrap-trixie-amd64.tar.gz.hash"
    output_has "Unpacking bootstrap-trixie-amd64"
    [ -f "$BOOTSTRAP_PATH/bin/bash" ]
    not_logged "make"
}

@test "setup_bootstrap fails when the verify script is missing" {
    export BT_VERIFY="$SCRATCH/no-such-verify"
    call setup_bootstrap
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: $BT_VERIFY script not found, unable to verify downloaded files."
    [ ! -d "$BOOTSTRAP_PATH" ]
}

@test "setup_bootstrap stops when verification fails" {
    export STUB_VERIFY_RC=3
    call setup_bootstrap
    [ "$status" -eq 3 ]
    [[ "$output" != *"Unpacking"* ]]
    [ ! -d "$BOOTSTRAP_PATH" ]
}

@test "setup_bootstrap builds locally when the download fails" {
    export STUB_WGET_FAIL=all RELEASE="$RELEASE_UNDER_TEST" FAB_ARCH=amd64
    call setup_bootstrap
    [ "$status" -eq 0 ]
    output_has "WARNING [tkldev-setup-test]: Failed download: bootstrap-trixie-amd64.tar.gz - building it locally instead"
    logged "git clone --branch master --depth 1 $GIT_REMOTE_URL/bootstrap.git $SCRATCH/bootstrap"
    output_has "Building bootstrap-trixie-amd64 locally (from $SCRATCH/bootstrap)"
    logged "make -C $SCRATCH/bootstrap clean"
    logged "make -C $SCRATCH/bootstrap install FAB_PATH=$FAB_PATH RELEASE=debian/trixie FAB_ARCH=amd64"
    [ -f "$BOOTSTRAP_PATH/bin/bash" ]
}

@test "setup_bootstrap removes a partial download before building" {
    export STUB_WGET_FAIL=hash RELEASE="$RELEASE_UNDER_TEST" FAB_ARCH=amd64
    call setup_bootstrap
    [ "$status" -eq 0 ]
    [ ! -e "$FAB_PATH/bootstraps/bootstrap-trixie-amd64.tar.gz" ]
    logged "make -C $SCRATCH/bootstrap install"
}

@test "setup_bootstrap fails on a missing download with --strict" {
    export STUB_WGET_FAIL=all STRICT=true
    call setup_bootstrap
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: Failed download: bootstrap-trixie-amd64.tar.gz"
    not_logged "make"
}

@test "setup_bootstrap skips a missing download with --transition, even with --strict" {
    export STUB_WGET_FAIL=all STRICT=true TRANSITION=true
    call setup_bootstrap
    [ "$status" -eq 0 ]
    output_has "WARNING [tkldev-setup-test]: Failed download: bootstrap-trixie-amd64.tar.gz - skipping due to transition"
    not_logged "make"
}

@test "build_bootstrap fails when the local build produces no bootstrap" {
    export STUB_MAKE_NO_BOOTSTRAP=1 RELEASE="$RELEASE_UNDER_TEST" FAB_ARCH=amd64
    call build_bootstrap
    [ "$status" -eq 1 ]
    output_has "FATAL [tkldev-setup-test]: Local build of bootstrap-trixie-amd64 did not create $BOOTSTRAP_PATH"
}
