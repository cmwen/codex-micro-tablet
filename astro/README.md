# Codex Micro Tablet website

Astro product site for Codex Micro Tablet. Source lives in `src/`; static output
is `dist/`. Use Node24 and run `npm ci`, `npm run build`, and `npm run preview`.

Canonical URL: https://cmwen.dev/codex-micro-tablet/ (GitHub Pages).
The project base is `/codex-micro-tablet`; internal routes and screenshot assets
must keep that prefix. The screenshot is a Flutter render with sample data.

The website deploys through `.github/workflows/deploy-website.yml` after a
published release, a matching successful release workflow, or manual dispatch.
The repository Pages source must be GitHub Actions (`build_type: workflow`).

The download page points to an explicit beta tag because GitHub's `/latest`
route excludes prereleases. Update that tag and APK name together for each beta.
