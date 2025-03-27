use std::{io::BufRead, path::PathBuf, process::Command};

pub fn main() -> eyre::Result<()> {
    let src_dir = std::env::current_dir()?;
    let out_dir = PathBuf::from(std::env::var("OUT_DIR")?);
    println!("cargo::rerun-if-changed=source/build.zig");
    println!("cargo::rerun-if-changed=source/build.zig.zon");
    println!("cargo::rerun-if-changed=source/src");

    let output = Command::new("zig")
        .args(&[
            "build",
            "-Doptimize=ReleaseFast",
            "--prefix",
            out_dir.display().to_string().as_str(),
        ])
        .current_dir(src_dir.join("source").display().to_string().as_str())
        .output()?;

    if output.status.success() {
        let lib_path = out_dir.join("lib");
        println!("cargo::rustc-link-search={}", lib_path.display());
        println!("cargo::rustc-link-lib=unicode-id");

        return Ok(());
    }

    for line in output.stderr.lines() {
        let line = line?;
        println!("cargo::error={line}");
    }

    Err(eyre::eyre!("zig build failed"))
}
