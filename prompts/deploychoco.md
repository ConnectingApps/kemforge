Create a GitHub Actions job named `deploychoco` that publishes a Chocolatey package to the official Chocolatey repository.

Requirements:

* The job depends on a previous job named `chocobuild`

* Runs on `windows-latest`

* Download the artifact produced by the build job:

  * Use `actions/download-artifact`
  * Artifact name: `choco-package`

* Install Chocolatey inside the runner

* Push the `.nupkg` file to Chocolatey using:

  * `choco push`
  * Source: https://push.chocolatey.org/
  * API key from GitHub Secrets: `CHOCO_API_KEY`

* Ensure the command works even if the exact filename is unknown (use wildcard if needed)

Security and control:

* Use an environment named `chocolatey` (for optional approval gates)
* The API key must only be referenced via `${{ secrets.CHOCO_API_KEY }}`
* Do not expose secrets in logs

Constraints:

* Do not rebuild anything in this job
* Only use the artifact from the previous job
* Use PowerShell syntax

Output:

* A complete GitHub Actions job YAML block (not the full workflow)
