# Test coverage baseline

Measured on 2026-09-24 against upstream master (6b42342), following the
project decision 0003 (90 percent floor per repository, 95 percent for every
file our changes touch).

## Baseline: 0 percent, nothing measured

This repository has no test suite and no coverage tool wired up. The figure
below is therefore not an estimate: nothing is measured. Line counts are
lines that are neither blank nor comment.

Inventory command (shebang or extension decides the kind):

    find . -type f -not -path './.git/*' -not -path './debian/*' \
      | while read f; do head -1 "$f" | grep -qE '^#!.*(ba)?sh' \
      && echo "$(grep -cvE '^\s*(#|$)' "$f") $f"; done

| File | Kind | Lines | Measured |
|------|------|-------|----------|
| overlay/usr/local/sbin/tkldev-setup | shell | 291 | 0 percent, no test |
| conf.d/main | shell | 45 | 0 percent, no test |
| overlay/usr/lib/inithooks/firstboot.d/20regen-proxy-cert | shell | 21 | 0 percent, no test |
| overlay/usr/local/sbin/tkldev-squid-refresh | shell | 18 | 0 percent, no test |
| overlay/usr/lib/inithooks/firstboot.d/40tkldev | shell | 1 | 0 percent, no test |

Total: 5 shell files, 376 lines, 0 percent measured. No Python.

## Our branches and the 95 percent bar

| Branch | File touched | Automated test |
|--------|--------------|----------------|
| fix/build-missing-bootstrap | overlay/usr/local/sbin/tkldev-setup | None. The two commits (verify the downloaded bootstrap tarball, build the bootstrap locally when the download fails) were verified by hand on a VM. The file is at 0 percent, below the 95 percent bar. |

## Plan to reach 90 percent per file

Method for shell: a `tests/` directory with shell test files that run each
script against a scratch root, with `PATH` pointing at stub commands (`git`,
`wget`, `fab-bootstrap`, `apt-get`, `systemctl`, `openssl`) that record
their arguments. Coverage is counted from `bash -x` traces, with `kcov`
when the decision 0003 open item settles on it. Every exit code and every
`fatal` path gets one test.

Priority order (size: small under 30 lines of test, medium under 150,
large above):

1. `overlay/usr/local/sbin/tkldev-setup` (large). Target 95 percent. The
   script is one flow with helpers (`tkl_remote`, `resolve_ref`,
   `update_repo`, `clone_or_update`, the `APPS` loop) and an option parser.
   Tests: option parsing and `usage` exit code; distro detection for
   turnkey and debian; remote URL selection; `resolve_ref` for a tag, a
   branch and a missing ref; `update_repo` on a clean and a dirty checkout;
   bootstrap present, downloaded and verified, download fails and the local
   build runs, verification fails and `fatal` exits 1; `DEBUG` tracing.
   The helpers should move into a sourceable file so the tests load them
   without running the main flow.
2. `overlay/usr/lib/inithooks/firstboot.d/20regen-proxy-cert` (small).
   First-boot path. Stub `openssl`, assert the key and certificate paths,
   file modes and that a second run regenerates.
3. `overlay/usr/lib/inithooks/firstboot.d/40tkldev` (small). One line, one
   invocation test.
4. `overlay/usr/local/sbin/tkldev-squid-refresh` (small). Stub `squid` and
   `systemctl`, assert the reload order and the exit code when the config
   check fails.
5. `conf.d/main` (medium). Build-time script that runs in the chroot with
   `apt-get`, `systemctl` and the `NO_PROXY` switch. Run it against a
   scratch root with stubs; assert the proxy configuration written under
   `etc/`, the disabled services and the purged packages, in both proxy
   modes. Any host address used in fixtures is IPv6, for example
   `[2001:db8::10]:3128` for the squid proxy.

When all five are in place, the repository total is measured with the
same trace counting and the number replaces the 0 percent above.
