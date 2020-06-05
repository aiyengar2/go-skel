#!/bin/bash
set -e

usage() {
  echo "Usage: $0 [-fhn] <full-package-name>"
  exit 1
}

improper_pkg_name() {
  echo "Use full package name like github.com/rancher/widget"
  usage
}

unknown_flag() {
  echo "Unknown flag provided"
  usage
}

if [ $# -eq 0 ]; then
  usage
fi

while :; do
  case $1 in
    -f|--force)
      USE_FORCE=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -n|--non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    -*)
      unknown_flag
      ;;
    */*)
      # Check if more than one package was provided
      [ ! -z $PKG ] && usage
      PKG=$1
      shift
      ;;
    *)
      # Check if something unexpected was provided
      [ ! -z $1 ] && improper_pkg_name
      # Check if package name has been parsed
      [ -z $PKG ] && improper_pkg_name
      break
  esac
done

BASE=$(dirname $0)
APP=$(basename $PKG)
REPO=$(basename $(dirname $PKG))
IMAGE=$REPO/$APP
FILES="
./Dockerfile.dapper
./.dockerignore
./.golangci.json
./.drone.yml
./.gitignore
./LICENSE
./main.go
./Makefile
./package/Dockerfile
./README.md.in
./scripts/boilerplate.go.txt
./scripts/build
./scripts/ci
./scripts/default
./scripts/entry
./scripts/package
./scripts/release
./scripts/test
./scripts/validate
./scripts/validate-ci
./scripts/version
./pkg/apis/some.api.group/v1/types.go
./pkg/codegen/cleanup/main.go
./pkg/codegen/main.go
./pkg/foo/controller.go
./go.mod
"

confirm_deletion() {
  [ ! -z ${NON_INTERACTIVE} ] && return 1
  read -p "Overwrite existing directory at $APP? [y/N] " confirmation
  case $confirmation in
    [yY][eE][sS]|[yY])
      return 0
      ;;
    *)
      return 1
  esac
}

if [ -d "$APP" ] && [ -z ${USE_FORCE} ] && ! confirm_deletion; then
  echo "Failed to delete $APP"
  exit 1
fi

rm -rf $APP
mkdir -p $APP

for i in $FILES; do
    mkdir -p $APP/$(dirname $i)
    echo Creating $APP/$i
    sed \
        -e "s!%REPO%!$REPO!g" \
        -e "s!%PKG%!$PKG!g" \
        -e "s!%APP%!$APP!g" \
        -e "s!%IMAGE%!$IMAGE!g" \
        $BASE/$i > $APP/$i
    if echo $i | grep -q scripts; then
        echo chmod +x $APP/$i
        chmod +x $APP/$i
    fi
done

cd ./$APP
go generate
go mod tidy
go mod vendor
make .dapper
./.dapper -m bind goimports -w .
./.dapper -m bind rm -rf .cache dist bin

git init
git add -A
git commit -m "Initial Commit"
while ! git gc; do
    sleep 2
done

make ci

echo Created $APP in ./$APP
