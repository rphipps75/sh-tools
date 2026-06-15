#!/bin/bash

PY_VERSION="${1:-$(python3 --version | grep -oP '\d+\.\d+')}"

rm -rf .venv

"python${PY_VERSION}" -m venv .venv
source .venv/bin/activate
which python
python --version