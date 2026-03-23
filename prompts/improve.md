Update the existing GitHub Actions build job that creates the Chocolatey package for the Go CLI application so that the package passes Chocolatey automated validation.

Important constraints:

* Do not change the existing build logic
* Do not change the existing version extraction logic
* Do not change the existing `choco pack` logic
* Do not change the existing artifact upload logic
* Do not add deployment logic
* Keep the changes minimal and targeted
* Preserve the current package structure unless a missing required file must be added

Assume the current workflow already:

* builds `kemforge.exe`
* creates the Chocolatey package
* uploads the `.nupkg`

Only fix the package compliance issues that caused Chocolatey automated validation to fail.

Make the following changes.

1. Add `tools/LICENSE.txt`

* This file is mandatory because the package embeds a binary
* The file must identify the license that applies to the software packaged as `kemforge.exe`
* If the repository already contains a LICENSE file, reference the canonical GitHub LICENSE URL derived from the repository context
* Do not invent a new license
* Do not make legal claims beyond identifying the applicable license and its source

2. Add `tools/VERIFICATION.txt`

* This file is mandatory because the package embeds a binary
* The file must include:

    * the GitHub repository URL derived from the workflow context
    * the exact commit hash using `${{ github.sha }}`
    * a clear statement that `kemforge.exe` was built from source during the workflow and was not downloaded
    * the build command used to produce the binary:
      `go build -o kemforge.exe`
* Write the file as plain text suitable for Chocolatey moderators

3. Add `tools/chocolateyUninstall.ps1`

* This is required because `Install-BinFile` is used during install
* The uninstall script must contain:
  `Uninstall-BinFile -Name "kemforge"`

4. Verify or update `tools/chocolateyInstall.ps1`

* Ensure it uses `Install-BinFile -Name "kemforge"` for `kemforge.exe`
* Keep the existing install behavior unchanged apart from what is needed for compliance

5. Update the `.nuspec` only where needed

* Add these fields if they are missing:

    * `<summary>`
    * `<releaseNotes>`
    * `<packageSourceUrl>`
* `releaseNotes` may point to the GitHub Releases page
* `packageSourceUrl` should point to the GitHub repository
* Do not remove or rewrite existing valid metadata unnecessarily

Implementation requirements:

* Use PowerShell syntax for file generation if the workflow currently generates files dynamically
* Ensure generated text files use UTF-8 encoding
* Use repository context values instead of hardcoded placeholders where possible
* Do not output the entire workflow
* Output only the relevant updated YAML steps and the exact contents of the new or changed package files

Goal:

Produce the smallest safe set of changes required for the Chocolatey package to pass automated validation after re-publishing the same package version.
