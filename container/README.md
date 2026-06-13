# MacOS Container

[container](https://github.com/apple/container) is a tool that you can use to create and run Linux containers as lightweight virtual machines on your Mac.

---

## Container Pull Age Verifier (`container-pull.sh`)

A bash script designed for macOS and Unix environments to safely pull container images from remote registries. It acts as a protective gatekeeper by checking the age of an image before pulling it down, ensuring you do not accidentally pull broken "too fresh" builds or dangerously outdated images without manual confirmation.

---

### Features

- __Multi-Registry Support:__ Automatically parses and checks image metadata across Docker Hub, GitHub Container Registry (`ghcr.io`), Google Container Registry (`gcr.io`), and Hardened Docker Images (`dhi.io`).
- __Intelligent Age Safeguards:__ Blocks or warns you based on the image's age using fully customisable thresholds.
- __Local Cache Comparison:__ Interrogates your local engine to see if the remote image is newer, identical, or older than your cached copy before downloading.
- __Native macOS Compatibility:__ Auto-detects BSD `date` (default on macOS) vs GNU `date` to ensure robust epoch parsing without crashing.
- __Resilient Logging:__ Plugs into an external logging framework if present, with a seamless standalone fallback mechanism.

---

### Pre-requisites

The script relies on a few common terminal utilities. Ensure they are installed on your Mac before execution:

1. __`jq`__: Lightweight and flexible command-line JSON processor.
2. __`curl`__: Used to query registry APIs.
3. __`container` CLI wrapper__: The script invokes `container image inspect` and `container image pull`. Ensure `container` is aliased or symlinked to your actual container runtime (e.g., `docker`, `podman`, or `lima`).

#### Installation via Homebrew

```bash
brew install jq curl

---
