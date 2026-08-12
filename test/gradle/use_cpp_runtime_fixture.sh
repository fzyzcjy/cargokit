#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <hello_rust_ffi_plugin-root>" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture_dir="$script_dir/../fixtures/cpp_runtime"
crate_dir="$1/rust"

cp "$fixture_dir/Cargo.toml" "$crate_dir/Cargo.toml"
cp "$fixture_dir/build.rs" "$crate_dir/build.rs"
cp "$fixture_dir/cpp_runtime.cc" "$crate_dir/cpp_runtime.cc"
cp "$fixture_dir/lib.rs" "$crate_dir/src/lib.rs"
