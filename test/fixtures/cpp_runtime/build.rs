fn main() {
    cc::Build::new()
        .cpp(true)
        .file("cpp_runtime.cc")
        .compile("cargokit_cpp_runtime");
    println!("cargo:rustc-link-lib=c++_shared");
}
