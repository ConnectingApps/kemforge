Now that the module path is updated and committed, here's how to create and push a version tag:

### Step 1: Make sure your changes are committed and pushed

```bash
cd /path/to/KemForge
git add go.mod
git commit -m "Update module path for go install support"
git push origin main
```

### Step 2: Create a version tag

Since your code already references `version 1.0.0` (in `main.go` lines 22 and 89), it makes sense to tag it as `v1.0.0`:

```bash
git tag v1.0.0
```

If you want to add a message/annotation to the tag (recommended for releases):

```bash
git tag -a v1.0.0 -m "First release: curl-compatible CLI with post-quantum cryptography support"
```

### Step 3: Push the tag to GitHub

```bash
git push origin v1.0.0
```

### That's it!

After pushing the tag, users can install KemForge with:

```bash
go install github.com/ConnectingApps/KemForge@v1.0.0
```

or simply:

```bash
go install github.com/ConnectingApps/KemForge@latest
```

### Future versions

When you release new versions, just increment the tag:

```bash
git add .
git commit -m "Bump version to 1.3.1"
git tag -a v1.3.1 -m "Version 1.3.1"
git push origin main
git push origin v1.3.1
```

Go follows [Semantic Versioning](https://semver.org/): `vMAJOR.MINOR.PATCH` — e.g., `v1.0.1` for a bugfix, `v1.1.0` for a new feature, `v2.0.0` for breaking changes.

### Optional: Create a GitHub Release

You can also create a formal GitHub Release (with release notes, binary downloads, etc.) by going to **https://github.com/ConnectingApps/KemForge/releases/new**, selecting your `v1.0.0` tag, and filling in the release details. This is optional but gives users a nicer experience on the GitHub page.