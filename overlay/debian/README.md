# Debian overlay

This directory is reserved for small, reviewable changes applied after the
published Debian source package is extracted:

- arm64 flavour pruning
- unsigned image generation
- `+deb13o6n` ABI identity
- unique O6N image and header metapackages

`scripts/lib/prepare_kernel_packaging.py` applies those transformations after
the Debian source package is extracted. Generated Debian source does not
belong in git. The O6N metapackage templates in this directory are copied into
the extracted tree.
