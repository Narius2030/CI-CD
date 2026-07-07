# CI/CD Template — Node.js/TypeScript → Docker (GitHub Actions)

Template CI/CD chuẩn production để copy sang dự án Node.js khác. App mẫu là một Fastify
service tối giản; điều đáng giá là **pipeline** xung quanh nó.

## Có gì trong này

| Thành phần          | Công cụ                                                                           |
| ------------------- | --------------------------------------------------------------------------------- |
| App                 | TypeScript + Fastify (`/health`, `/ready`)                                        |
| Quality             | ESLint (flat config), Prettier, `tsc --noEmit`, Vitest + coverage (threshold 80%) |
| SAST                | GitHub CodeQL                                                                     |
| Dependency/CVE scan | Trivy (fs) + `dependency-review-action`                                           |
| Container           | Dockerfile multi-stage, non-root, `HEALTHCHECK`                                   |
| Image scan          | Trivy (image)                                                                     |
| Supply-chain        | SBOM + SLSA provenance (buildx) + chữ ký **cosign keyless**                       |
| Registry            | GHCR (`ghcr.io`) qua `GITHUB_TOKEN`                                               |
| Deploy              | staging (auto) → production (approval gate) qua GitHub Environments               |
| Bảo trì             | Dependabot (npm + actions + docker), CODEOWNERS, PR template                      |

## Chạy local

```bash
npm ci
npm run lint && npm run typecheck && npm test   # quality gate
npm run build && npm start                       # chạy service
curl localhost:3000/health                        # -> {"status":"ok"}
```

## Docker local

```bash
docker build -t ci-cd .
docker run -p 3000:3000 ci-cd
curl localhost:3000/health
```

## Pipeline

- **`ci.yml`** — chạy trên PR & push nhánh non-main: quality gate + CodeQL + dependency
  review + Trivy fs scan.
- **`cd.yml`** — chạy trên push `main` và tag `v*`: quality gate → build image (buildx,
  cache, SBOM, provenance) → Trivy image scan → cosign sign → deploy staging → deploy
  production.
- **`reusable-node-ci.yml`** — quality gate dùng chung (`workflow_call`). Repo khác có thể
  tái dùng: `uses: <owner>/ci-cd/.github/workflows/reusable-node-ci.yml@main`.

## Thiết lập trên GitHub (bắt buộc cho phần deploy)

1. **Environments** — Settings → Environments, tạo `staging` và `production`.
2. **Approval gate** — ở environment `production`, bật **Required reviewers** để pipeline
   dừng chờ duyệt trước khi deploy prod.
3. **GHCR** — không cần secret; `GITHUB_TOKEN` đã đủ quyền push (đã khai báo
   `packages: write`). Package tạo lần đầu ở chế độ private — chỉnh visibility nếu cần.
4. **Deploy thật** — thay bước placeholder trong `cd.yml` (đánh dấu `ponytail:`) bằng lệnh
   thật (`kubectl` / `helm` / `ssh`) và thêm secret tương ứng (vd `KUBE_CONFIG`) vào từng
   environment.

## Verify chữ ký image

```bash
cosign verify \
  --certificate-identity-regexp "https://github.com/<owner>/ci-cd/.github/workflows/cd.yml@.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/<owner>/ci-cd@<digest>
```

## Tái dùng cho dự án khác

Thay thư mục `src/` bằng app thật của bạn, đổi `IMAGE_NAME` nếu muốn tên image khác (mặc
định lấy theo `github.repository`), giữ nguyên phần workflow. Các bước quality/security
chạy y hệt.
