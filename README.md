# Update Homebrew Formula

A GitHub Action that synchronizes a Homebrew formula with a GitHub release.

> 🚧 This is still in development, and not ready for general use.

Add this action to a workflow
to update a corresponding [Homebrew formula](https://brew.sh) in your tap repository
whenever you create a new [GitHub release](https://docs.github.com/en/free-pro-team@latest/github/administering-a-repository/about-releases).
Your Homebrew formula will be updated with the tag and revision of the release.
Any assets associated with the release whose name matches the
[expected pattern](https://github.com/NSHipster/update-homebrew-formula-action/blob/e1551f21a97c71feba4202ab613f460f008807cb/entrypoint.rb#L65)
will be added as pre-built binary artifacts,
or [bottles](https://www.rubydoc.info/github/Homebrew/brew/Formula#bottle-class_method).

To better understand what this action does and why it's useful,
consider the following scenario:

* * *

Mona has a project `mona/hello` with source code
for building an executable named `hello`.
To make it easier to install,
Mona provides the following Homebrew [formula](https://docs.brew.sh/Formula-Cookbook)
in a [tap](https://docs.brew.sh/Formula-Cookbook#homebrew-terminology)
that she hosts in a repository named `mona/homebrew-formulae`:

```ruby
class Hello < Formula
  desc "👋"
  homepage "https://github.com/mona/hello"
  url "https://github.com/mona/hello.git", tag: "1.0.0", revision: "d95b2990f6186523cda25cea4f9d45bc1fde069f"

  depends_on xcode: ["12.0", :build]

  def install
    system "make", "install", "prefix=#{prefix}"
  end

  test do
    system bin/"hello"
  end
end
```

This allows anyone with Homebrew installed
to install the `hello` command with a single command:

```terminal
$ brew install mona/formulae/hello
```

However, this convenience for the user comes at a cost to Mona
(beyond the fixed cost of creating a formula in the first place).
Whenever Mona wants to release a new version of `hello`,
she must do the following:

- [x] Create and push a new tag
- [x] Create a new release on GitHub
- [x] Build and upload a pre-built binary for the release
- [x] Calculate the SHA256 checksum for the binary
- [x] Update the Homebrew formula with the new
      version, tag, revision, and asset checksums

If she forgets to do all of these steps
(or makes a mistake),
her users won't get the latest version when they install `hello`.

This action automates the manual, error-prone process described above,
streamlining the release of any tool you distribute via
your own Homebrew tap.

Let's say Mona tags a new `1.0.1` version
after setting up a workflow [like the one described below](#usage).
When `update-homebrew-formula-action` runs,
it updates the formula with a new tag and revision:

```diff
  class Hello < Formula
    desc "👋"
    homepage "https://github.com/mona/hello"
-   version "1.0.0"
+   version "1.0.1"
-   url "https://github.com/mona/hello.git", tag: "1.0.0", revision: "d95b2990f6186523cda25cea4f9d45bc1fde069f"
+   url "https://github.com/mona/hello.git", tag: "1.0.1", revision: "5aa05bf843ef74f6c3e5ed6d504d6f305e0945d1"
```

## Usage

### Authentication

This action requires the `GH_PERSONAL_ACCESS_TOKEN` environment variable
to be set with a [Github personal access token](https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/creating-a-personal-access-token)
that has "repo" authorization for the repository containing
the formula you want to update.

> **Important**:
> GitHub automatically creates a `GITHUB_TOKEN` secret to use in your workflow,
> but it lacks the permissions necessary to run this action successfully.
> For more information, see
> ["Authentication in a workflow"](https://docs.github.com/en/free-pro-team@latest/actions/reference/authentication-in-a-workflow).

To generate one,
navigate to the [Personal access tokens](https://github.com/settings/tokens) page
in your GitHub account settings
(Settings > Developer settings > Personal access tokens)
and click the "Generate a new token" button.

In the "New personal access token" form,
provide a descriptive comment in the "Note" field, like "Wiki Management".
Under "Select scopes",
enable all of the entries under "repo" perms.

Next,
click the "Generate token" button at the bottom of the form.

![GitHub Personal Access Token Select Scopes](https://user-images.githubusercontent.com/7659/72726210-9f9a7d80-3b3c-11ea-81b4-528de92fb9fa.png)

Finally,
copy your generated personal access token to your clipboard
and navigate to your settings page for your repository or organization.
Navigate to the "Secrets" page,
click "Add a new secret",
and fill in the form by
entering `GH_PERSONAL_ACCESS_TOKEN` into the "Name" field and
pasting your token into the "Value" field.

> **Note**:
> You can use any name for this secret,
> so long as it's passed to this action as `GH_PERSONAL_ACCESS_TOKEN`.

### Inputs

- `repository`:
  **Required**.
  The project repository (e.g. mona/hello).
- `tap`:
  **Required**.
  The Homebrew tap repository (e.g. mona/homebrew-formulae).
- `formula`:
  **Required**.
  The path to the formula in the tap repository (e.g. Formula/hello.rb).
- `name`:
  _Optional_.
  Overrides the name of the formula, if it differs from the github repository (eg. hello); if not sets, defaults to the repository name
- `message`:
  _Optional_.
  The message of the commit updating the formula. (e.g. "Update hello to 1.0.1")

### Example Workflows

#### Updating a Homebrew formula in response to creating a new release

We recommend running this action as part of a workflow that triggers on
[release events](https://docs.github.com/en/free-pro-team@latest/actions/reference/events-that-trigger-workflows#release)
with the `created` activity type.
This way, any release that's created —
whether manually or programmatically
(such as with [actions/create-release](https://github.com/actions/create-release)) —
will benefit from the same automation.

```yml
# .github/workflows/release.yml
name: Release

on:
  release:
    types:
      - created

jobs:
  formula:
    name: Update Homebrew formula
    runs-on: ubuntu-latest
    steps:
      - name: Update the Homebrew formula with latest release
        uses: NSHipster/update-homebrew-formula-action@main
        with:
          repository: mona/hello
          tap: mona/homebrew-formulae
          formula: Formula/hello.rb
        env:
          GH_PERSONAL_ACCESS_TOKEN: ${{ secrets.GH_PERSONAL_ACCESS_TOKEN }}
```

#### Updating a formula with a bottle

For extra credit,
you can extend your workflow to create a release for the new tag
and build bottles once the formula is updated.
It's a bit involved,
but your users will appreciate your going the extra mile.

Here's the order of operations:

1. Update the formula for the latest release, like before
2. Once that's finished,
   use Homebrew to build a bottle using the updated formula.
3. Upload the bottle to the release on GitHub
4. Update the formula again, this time to add the bottle

```yml
# .github/workflows/release.yml
name: Release

on:
  release:
    types:
      - created

jobs:
  update_formula_version:
    name: Update the Homebrew formula with latest release
    runs-on: ubuntu-latest
    steps:
      - uses: NSHipster/update-homebrew-formula-action@main
        with:
          repository: mona/hello
          tap: mona/homebrew-formulae
          formula: Formula/hello.rb
        env:
          GH_PERSONAL_ACCESS_TOKEN: ${{ secrets.GH_PERSONAL_ACCESS_TOKEN }}
  upload_bottle:
    name: Build and distribute Homebrew bottle for macOS Catalina
    runs-on: macos-10.15
    needs: [update_formula_version]
    steps:
      - name: Build a bottle using Homebrew
        run: |
          brew tap mona/formulae
          brew install --build-bottle --verbose hello
          brew bottle hello
      - name: Upload the bottle to the GitHub release
        uses: actions/upload-release-asset@v1.0.1
        env:
          GH_PERSONAL_ACCESS_TOKEN: ${{ secrets.GH_PERSONAL_ACCESS_TOKEN }}
        with:
          upload_url: ${{ github.event.release.upload_url }}
          #Note: When using `name` to override the formula name, you need to also use it here (where it says "hello" here)
          asset_path: ./hello--${{ github.event.release.tag_name }}.catalina.bottle.tar.gz
          asset_name: hello-${{ github.event.release.tag_name }}.catalina.bottle.tar.gz
          asset_content_type: application/gzip
  update_formula_bottle:
    name: Update the Homebrew formula again with bottle
    runs-on: ubuntu-latest
    needs: [upload_bottle]
    steps:
      - uses: NSHipster/update-homebrew-formula-action@main
        with:
          repository: mona/hello
          tap: mona/homebrew-formulae
          formula: Formula/hello.rb
          message: |
              Add bottle for hello ${{ github.event.release.tag_name }}
              on macOS Catalina
        env:
          GH_PERSONAL_ACCESS_TOKEN: ${{ secrets.GH_PERSONAL_ACCESS_TOKEN }}
```

> **Note**:
> Homebrew generates bottles with a double dash (`--`) in the resulting filename,
> but expects a single dash (`-`) when downloading the bottle.

After running this workflow,
your formula will have a `bottle` declaration like the following:

```diff
+   bottle do
+     root_url "https://github.com/mona/hello/releases/download/1.0.1"
+     cellar :any
+     sha256 "d7493440a64c3a11fac793fb0f28a21e6974e1f430fe246d603496b61a565ae9" => :catalina
+   end
```

* * *

For a real-world example of this action in use,
check out the release infrastructure for [swift-doc](https://github.com/SwiftDocOrg/swift-doc).

## License

MIT
