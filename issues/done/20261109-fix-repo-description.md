# Fix the ubuntu-core-desktop repo description

## Impact / Priority

None user-facing: the repository's registered description is
technically incorrect (says "Ubuntu Core 22") and version-specific, so
it misdescribes the project and needs updating with every version.
Impact derived from the original note's symptoms.

    canonical-repo-automation/groups/ubuntu-engineering/desktop/repos/ubuntu-core-desktop/terragrunt.hcl:
    This directory contains an image of Ubuntu Core 22 with the GDM display
    manager loaded into the boot file system.

The above description is technically incorrect. It's not Ubuntu Core
22. Description should be generic and not need updating with versions.
e.g. "This directory contains an image of Ubuntu Core Desktop"

Check the other repositories descriptions are appropriate too
