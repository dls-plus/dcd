# D Test Utils

This repository contains some small scripts intended for development and
automated testing use.

This repository should be used as submodule but only be used for development
purposes and not be part of a final distribution, as the download zip function
on GitHub (which DUB uses to fetch dependencies) does not include submodules. It
is fine to use this for testing and CI however, assuming the CI is setup to
clone recursively.

## `test_with_package.d`

Temporarily modifies the dub.json, replacing one dependency version with either
the minimum satisfiable version for a dub dependency or the maximum satisfiable
version for a dub dependency.

For example for packages supporting multiple libdparse versions such as
`=>0.13.0 <0.15.0` this script can be used to run any dub build or test command
or any other arbitrary commands using a dub.json which has the version either
pinned to `0.13.0` or to `<0.15.0`. A `dub upgrade` will always be called after
modification of the dub.json file.

Usage:
```sh
# run `dub test` with minimum specified libdparse version
rdmd ./test_with_package.d min libdparse
# run `dub test` with maximum specified libdparse version
rdmd ./test_with_package.d max libdparse

# try if compilation of executable works with both minimum and maximum
rdmd ./test_with_package.d both libdparse -- dub build --config=executable --compiler=$DC

# checking multiple packages
rdmd ./test_with_package.d libdparse -- rdmd ./test_with_package.d dsymbol
```

Example travis config:
```yml
sudo: false
language: d
d:
  - dmd
  - ldc
env:
  - VERSION=min
  - VERSION=max
script:
  - rdmd ./d-test-utils/test_with_package.d libdparse
```
This travis config will create 4 runs (dmd VERSION=min, dmd VERSION=max, ldc
VERSION=min and ldc VERSION=max) each running `dub test`


Example uses:
- [libddoc](https://github.com/dlang-community/libddoc/blob/master/.travis.yml)
