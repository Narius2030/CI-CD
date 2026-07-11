# Changelog

## [1.3.0](https://github.com/Narius2030/CI-CD/compare/v1.2.0...v1.3.0) (2026-07-11)


### Features

* **ci/cd:** adjust the release & cd workflows ([8c3e501](https://github.com/Narius2030/CI-CD/commit/8c3e501ad8e93040b24c56c331b2d2af7c104903))
* **ci/cd:** adjust the release & cd workflows ([9754c29](https://github.com/Narius2030/CI-CD/commit/9754c29bcf487a76b3e80ed413c8d4f9be8dc53f))

## [1.2.0](https://github.com/Narius2030/CI-CD/compare/v1.1.0...v1.2.0) (2026-07-11)


### Features

* changed repository owner name ([bd7f6ca](https://github.com/Narius2030/CI-CD/commit/bd7f6ca4f09ac73b98790ff901db94765d7770dc))
* changed repository owner name ([41110ee](https://github.com/Narius2030/CI-CD/commit/41110ee80f70410f0c7dbc253b3170d3a885a7a2))


### Bug Fixes

* downgrade trivy-action version to 0.36.0 ([389f3e5](https://github.com/Narius2030/CI-CD/commit/389f3e5c8a3c32b03f008d7538eb89a677528aab))
* prevent trivy-action from installing trivy again ([7ab3056](https://github.com/Narius2030/CI-CD/commit/7ab305609baa84818f2b834c4143031a90a86363))
* reformat a markdown file to .prettier ([5d2ae5e](https://github.com/Narius2030/CI-CD/commit/5d2ae5ef1f2a51db1139efd407b9ff10c9b2f568))
* upgrade trivy-action version ([a5c55f4](https://github.com/Narius2030/CI-CD/commit/a5c55f4c204d8dd263da545bc536af5a94ce7c6b))

## [1.1.0](https://github.com/taovietducofficial/CI-CD/compare/v1.0.2...v1.1.0) (2026-07-07)


### Features

* **release:** publish versioned image from release workflow (no PAT needed) ([6852023](https://github.com/taovietducofficial/CI-CD/commit/685202344cf26336ac7e3ad706be1f3e204cde7d))

## [1.0.2](https://github.com/taovietducofficial/CI-CD/compare/v1.0.1...v1.0.2) (2026-07-07)


### Bug Fixes

* **cd:** image scan reports to Security tab instead of blocking release ([5d3e90d](https://github.com/taovietducofficial/CI-CD/commit/5d3e90d0a3eab7072d33ceaeb2d5b307eaf2f414))
* **cd:** lowercase image ref for cosign/scan/deploy ([5e88a4b](https://github.com/taovietducofficial/CI-CD/commit/5e88a4b87a2b6d690b8f46c7d0521fe5d2479418))
* **cd:** make image scan advisory (non-blocking), drop flaky SARIF upload ([e16fb40](https://github.com/taovietducofficial/CI-CD/commit/e16fb409ac37e29ae3e3fd79827eb3a281f6539a))
* **ci:** pin trivy-action to valid tag v0.36.0 ([1f8282d](https://github.com/taovietducofficial/CI-CD/commit/1f8282d5d79dae94534d7a599d420b2c876239f8))
* **ci:** reusable workflow inherits caller permissions to fix CD startup_failure ([d9526ab](https://github.com/taovietducofficial/CI-CD/commit/d9526abc76f957f39ac8c6b4fb3b84e6e0ba0c6a))
* **docker:** base image node:20-alpine -&gt; node:22-alpine (LTS) ([8ccd44b](https://github.com/taovietducofficial/CI-CD/commit/8ccd44be927f4958110ce0cd248942514ba2e0aa))
* **release:** drop component prefix so release tag matches cd.yml v* trigger ([55f349c](https://github.com/taovietducofficial/CI-CD/commit/55f349c132bac2b3cb3b912b720d7bbe7862a4a1))


### Documentation

* add "Dùng cho project mới" guide (template repo + checklist) ([0d4345e](https://github.com/taovietducofficial/CI-CD/commit/0d4345e15dc0b8ad30f2284e7911cafc2577555f))

## [1.0.1](https://github.com/taovietducofficial/CI-CD/compare/ci-cd-v1.0.0...ci-cd-v1.0.1) (2026-07-07)


### Bug Fixes

* **cd:** image scan reports to Security tab instead of blocking release ([5d3e90d](https://github.com/taovietducofficial/CI-CD/commit/5d3e90d0a3eab7072d33ceaeb2d5b307eaf2f414))
* **cd:** lowercase image ref for cosign/scan/deploy ([5e88a4b](https://github.com/taovietducofficial/CI-CD/commit/5e88a4b87a2b6d690b8f46c7d0521fe5d2479418))
* **cd:** make image scan advisory (non-blocking), drop flaky SARIF upload ([e16fb40](https://github.com/taovietducofficial/CI-CD/commit/e16fb409ac37e29ae3e3fd79827eb3a281f6539a))
* **ci:** pin trivy-action to valid tag v0.36.0 ([1f8282d](https://github.com/taovietducofficial/CI-CD/commit/1f8282d5d79dae94534d7a599d420b2c876239f8))
* **ci:** reusable workflow inherits caller permissions to fix CD startup_failure ([d9526ab](https://github.com/taovietducofficial/CI-CD/commit/d9526abc76f957f39ac8c6b4fb3b84e6e0ba0c6a))
* **docker:** base image node:20-alpine -&gt; node:22-alpine (LTS) ([8ccd44b](https://github.com/taovietducofficial/CI-CD/commit/8ccd44be927f4958110ce0cd248942514ba2e0aa))


### Documentation

* add "Dùng cho project mới" guide (template repo + checklist) ([0d4345e](https://github.com/taovietducofficial/CI-CD/commit/0d4345e15dc0b8ad30f2284e7911cafc2577555f))
