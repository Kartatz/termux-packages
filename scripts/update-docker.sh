#!/bin/sh
set -e -u

CONTAINER=termux-package-builder
IMAGE=ghcr.io/termux/package-builder

docker pull $IMAGE

LATEST=$(docker inspect --format "{{.Id}}" $IMAGE)

if ! docker container inspect $CONTAINER >/dev/null 2>&1; then
	echo "Container '$CONTAINER' does not exist - nothing to update"
	exit 0
fi

RUNNING=$(docker inspect --format "{{.Image}}" $CONTAINER)

if [ "$LATEST" = "$RUNNING" ]; then
	echo "Image '$IMAGE' used in the container '$CONTAINER' is already up to date"
else
	echo "Image '$IMAGE' used in the container '$CONTAINER' has been updated - removing the outdated container"
	docker stop $CONTAINER
	docker rm -f $CONTAINER
fi

