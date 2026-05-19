.PHONY: test unit-test docker-test package

test: docker-test

unit-test:
	bash tests/run.sh

docker-test:
	bash tests/docker/run.sh

package:
	bash packaging/build-tarball.sh
