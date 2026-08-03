use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let embed_dir = manifest_dir
        .join("..")
        .join("katago_embed")
        .canonicalize()
        .unwrap_or_else(|_| manifest_dir.join("..").join("katago_embed"));

    let lib_dir = env::var("CITY_KATAGO_NATIVE_LIB_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            // Default: MSVC multi-config RelWithDebInfo output from tools/build_city_katago.ps1
            embed_dir.join("build").join("RelWithDebInfo")
        });

    println!("cargo:rerun-if-env-changed=CITY_KATAGO_NATIVE_LIB_DIR");
    println!("cargo:rerun-if-changed={}", embed_dir.join("include").join("katago_c_api.h").display());
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=dylib=city_katago_native");
}
