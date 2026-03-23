Create a GitHub Actions job named `build` that runs on `windows-latest` and prepares a Chocolatey package for a Go CLI application.

Requirements:

* The workflow is triggered by a git tag in the format `v*` (e.g. v1.2.3)

* Extract the version number from the tag (strip the leading `v`)

* Build a Windows binary using Go:

  * GOOS=windows
  * GOARCH=amd64
  * Output file: `kemforge.exe`

* Create the Chocolatey package structure:

  * Directory: `kemforge/tools`
  * Copy `kemforge.exe` into `tools`

* Generate a valid `kemforge.nuspec` file dynamically:

  * id: kemforge
  * version: extracted from tag
  * title: My App
  * authors: placeholder
  * description: My Go CLI tool

* Create `tools/chocolateyInstall.ps1`:

  * Use `Install-BinFile` to register `kemforge.exe`

* Install Chocolatey inside the runner

* Run `choco pack` inside the `kemforge` directory to generate the `.nupkg`

* Upload the generated `.nupkg` as an artifact using:

  * `actions/upload-artifact`
  * artifact name: `choco-package`

Constraints:

* The job must not use any secrets
* The job must be fully reproducible
* Use PowerShell syntax for scripting steps
* Ensure paths and encoding are correct for Windows

Output:

* A complete GitHub Actions job YAML block (not the full workflow, only the job)
