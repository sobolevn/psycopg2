#!/bin/bash

# Build psycopg2-binary wheel packages for Apple M1 (cpNNN-macosx_arm64)
#
# This script is designed to run on Scaleway Apple Silicon machines.
#
# The script cannot be run as sudo (installing brew fails), but requires sudo,
# so it can pretty much only be executed by a sudo user as it is.

set -euo pipefail
set -x

python_versions="3.8.10 3.9.13 3.10.5"
postgres_version=14

# Move to the root of the project
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${dir}/../../"

# Add /usr/local/bin to the path. It seems it's not, in non-interactive sessions
if ! (echo $PATH | grep -q '/usr/local/bin'); then
    export PATH=/usr/local/bin:$PATH
fi

# Install brew, if necessary. Otherwise just make sure it's in the path
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    command -v brew > /dev/null || (
        # Not necessary: already installed
        # xcode-select --install
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL \
            https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    )
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install PostgreSQL, if necessary
command -v pg_config > /dev/null || (
    brew install postgresql@${postgres_version}
    brew services start postgresql
)

# Install the Python versions we want to build
for ver3 in $python_versions; do
    ver2=$(echo $ver3 | sed 's/\([^\.]*\)\(\.[^\.]*\)\(.*\)/\1\2/')
    command -v python${ver2} > /dev/null || (
        (cd /tmp &&
            curl -fsSl -O \
                https://www.python.org/ftp/python/${ver3}/python-${ver3}-macos11.pkg)
        sudo installer -pkg /tmp/python-${ver3}-macos11.pkg -target /
    )
done

# Create a virtualenv where to work
if [[ ! -x .venv/bin/python ]]; then
    python3 -m venv .venv
fi

source .venv/bin/activate
pip install cibuildwheel

# Build the binary packages
export CIBW_PLATFORM=macos
export CIBW_ARCHS=arm64
export CIBW_BUILD='cp{38,39,310}-*'
export CIBW_TEST_COMMAND='python -c "import tests; tests.unittest.main(defaultTest=\"tests.test_suite\")"'

export PSYCOPG2_TESTDB=postgres
export PYTHONPATH=$(pwd)

# For some reason, cibuildwheel tests says that psycopg2 is already installed,
# refuses to install, then promptly fails import. So, please, seriously,
# install this thing.
export PIP_FORCE_REINSTALL=1

# Replace the package name
sed -i .bak 's/^setup(name="psycopg2"/setup(name="psycopg2-binary"/' setup.py

cibuildwheel
