# Debian overlay

This directory is reserved for small, reviewable changes applied after the
published Debian source package is extracted:

- arm64 flavour pruning
- unsigned image generation
- `+deb13o6n` ABI identity
- unique O6N image and header metapackages

Gate 2 keeps those transformations in scripts. Generated Debian source does not
belong in git.
