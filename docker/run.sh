#!/bin/bash
set -e
VERSION=$1

if [ "$#" -ne 1 ]; then
    echo "illegal number of parameters"
    exit 1
fi

MAJOR=$(echo "$VERSION" | awk -F \. {'print $1'})
MINOR=$(echo "$VERSION" | awk -F \. {'print $2'})
PATCH=$(echo "$VERSION" | awk -F \. {'print $3'})
DEST="${PWD}/build/${VERSION}"
PORT="87${MAJOR}${MINOR}"
mkdir -p $DEST

docker run --rm -p ${PORT}:8700 -v ${DEST}:/build "richfitz/buildr:${VERSION}" --expose --root=/build --port=8700
