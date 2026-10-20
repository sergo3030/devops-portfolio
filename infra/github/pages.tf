# The site is built and deployed by a GitHub Actions workflow (task 13).
# Until the first deployment the site URL returns 404.

resource "github_repository_pages" "this" {
  repository = github_repository.this.name
  build_type = "workflow"
}
