FROM registry.redhat.io/rhtas/cosign-rhel9:1.1.1@sha256:3cd261cd4fed03688c6fd3c6161ae1ec69e908bbb6593ec279415414c7422535 as cosign

FROM registry.redhat.io/rhtas/ec-rhel9:0.5@sha256:3d330b4c742f584be63cf11e451f7822863a5960976a721e18bd8b2e9f1c0038 as ec

FROM brew.registry.redhat.io/rh-osbs/openshift-golang-builder:v1.23@sha256:ca0c771ecd4f606986253f747e2773fe2960a6b5e8e7a52f6a4797b173ac7f56 as go-builder

WORKDIR /build

COPY ./tools .

ENV GOBIN=/usr/local/bin/

RUN \
  cd yq && \
  go install -trimpath --mod=readonly github.com/mikefarah/yq/v4 && \
  yq --version

RUN \
  cd syft && \
  go install -trimpath --mod=readonly github.com/anchore/syft/cmd/syft && \
  syft version

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.5@sha256:66b99214cb9733e77c4a12cc3e3cbbe76769a213f4e2767f170a4f0fdf9db490

RUN \
  microdnf upgrade --assumeyes --nodocs --setopt=keepcache=0 --refresh && \
  microdnf -y --nodocs --setopt=keepcache=0 install which git-core jq python3.11 podman buildah podman fuse-overlayfs findutils && \
  ln -s /usr/bin/python3.11 /usr/bin/python3

COPY --from=cosign /usr/local/bin/cosign /usr/bin/cosign
COPY --from=ec /usr/local/bin/ec /usr/bin/ec
COPY --from=go-builder /usr/local/bin/yq /usr/bin/yq
COPY --from=go-builder /usr/local/bin/syft /usr/bin/syft

WORKDIR /work

COPY ./rhtap ./rhtap/

CMD ["/bin/bash"]
