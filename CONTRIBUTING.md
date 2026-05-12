# Contributing

Thank you for your interest in contributing to qcom-sec-tools-wrapper.
Contributions of all kinds (bug reports, documentation improvements,
new features and bug fixes) are welcome.

## Reporting issues

Please report bugs and feature requests via
[GitHub Issues](https://github.com/qualcomm-linux/qcom-sec-tools-wrapper/issues).

Before opening a new issue:

* Search the existing issues to avoid duplicates.
* Include enough information to reproduce the problem: host
  distribution, sectools version, the wrapper script and command line
  used, and the full output of the failing run.
* For security-sensitive issues, **do not** open a public issue. Follow
  the process described in [SECURITY.md](SECURITY.md) instead.

## Code of Conduct

By participating in this project you agree to abide by the
[Code of Conduct](CODE-OF-CONDUCT.md).

## Developer Certificate of Origin (DCO)

This project uses the
[Developer Certificate of Origin](https://developercertificate.org) to
certify that contributors have the right to submit the code they are
contributing. Every commit must carry a Signed-off-by trailer that
matches the commit author:

```
Signed-off-by: Your Name <your.email@example.com>
```

Add it automatically by passing `-s` to `git commit`:

```
git commit -s -m "component: brief description of the change"
```

If you forget the sign-off on one or more existing commits on your
branch, you can fix them in bulk with:

```
git rebase --signoff <base-branch>
git push --force-with-lease
```

Pull requests that contain commits without a valid Signed-off-by
trailer will be blocked by the DCO check and cannot be merged until
every commit is signed off.

## Submitting changes

1. Fork the repository on GitHub and create a topic branch from `main`.
2. Make your change. Keep commits small and focused: one logical change
   per commit makes review easier and helps `git bisect` later.
3. Write a clear commit message. The first line should be a short
   summary in the form `prefix: subject`, followed by a blank line and
   a body that explains why the change is needed, not just what it
   does.
4. Make sure every commit is signed off (see DCO above).
5. Verify your change locally:
   * Shell scripts pass `shellcheck`.
   * The scripts you touched still run end-to-end against the
     documented workflow in [README.md](README.md).
6. Push your branch to your fork and open a pull request against
   `main`.
7. Respond to review feedback by pushing additional commits or
   rebasing as appropriate. Avoid force-pushing once review has
   started unless asked to do so.

## Style

* Shell scripts target POSIX `/bin/sh` unless otherwise stated. Avoid
  Bash-isms unless the existing file already uses them.
* Quote variables (`"$var"`) and prefer `printf` over `echo -e` for
  portability.
* Add `SPDX-License-Identifier: BSD-3-Clause-Clear` to any new source
  file. See existing files for the expected header format.
* Match the indentation and quoting style of the file you are editing.

## License

By contributing to this repository, you agree that your contributions
will be licensed under [The Clear BSD License](LICENSE).
