// SPDX-License-Identifier: AGPL-3.0-or-later

use crate::desktop::build_desktop;
use crate::proc::{RunOptions, run_command};
use anyhow::Result;
use std::env;
use std::path::Path;

fn task_run(args: &[&str]) -> Result<()> {
    run_command(
        args,
        RunOptions {
            load_default_env: false,
            ..RunOptions::default()
        },
    )
    .map(drop)
}

fn test_env() -> Vec<(String, Option<String>)> {
    let nats_url = env::var("FLUXER_NATS_URL").unwrap_or_else(|_| default_test_nats_url());
    vec![
        ("FLUXER_NATS_URL".to_owned(), Some(nats_url.clone())),
        (
            "FLUXER_NATS_CORE_URL".to_owned(),
            Some(env::var("FLUXER_NATS_CORE_URL").unwrap_or_else(|_| nats_url.clone())),
        ),
        (
            "FLUXER_NATS_JETSTREAM_URL".to_owned(),
            Some(env::var("FLUXER_NATS_JETSTREAM_URL").unwrap_or(nats_url)),
        ),
    ]
}

fn default_test_nats_url() -> String {
    let host = if Path::new("/.dockerenv").exists() {
        "nats"
    } else {
        "127.0.0.1"
    };
    format!("nats://{host}:4222")
}

fn run_generators(for_typecheck: bool) -> Result<()> {
    task_run(&["bun", "--filter", "@fluxer/schema", "generate"])?;
    if for_typecheck {
        return task_run(&["bun", "--filter", "@fluxer/i18n", "generate:types"]);
    }
    task_run(&["bun", "--filter", "fluxer_app", "i18n:compile"])
}

pub fn run_typecheck() -> Result<i32> {
    run_generators(true)?;
    task_run(&["bun", "--filter", "*", "--if-present", "typecheck"])?;
    Ok(0)
}

pub fn run_test() -> Result<i32> {
    run_generators(false)?;
    let mut args = vec!["bun".to_owned(), "--filter".to_owned(), "*".to_owned()];
    // Bun has no numeric equivalent of pnpm's `--workspace-concurrency=N`; the closest
    // safe approximation to bounding parallelism on a constrained CI runner is
    // `--sequential` (concurrency of 1). We only opt into it when an explicit override
    // was requested, so local/default runs keep bun's normal full-parallel behavior.
    if env::var("PNPM_TEST_WORKSPACE_CONCURRENCY").is_ok() {
        args.push("--sequential".to_owned());
    }
    args.extend(
        [
            "--filter",
            "!fluxer_api",
            "--filter",
            "!fluxer",
            "--filter",
            "!fluxer_desktop",
            "--if-present",
            "test",
        ]
        .into_iter()
        .map(str::to_owned),
    );
    let env = test_env();
    run_command(
        &args.iter().map(String::as_str).collect::<Vec<_>>(),
        RunOptions {
            env: env.clone(),
            load_default_env: false,
            ..RunOptions::default()
        },
    )?;
    task_run(&[
        "cargo",
        "test",
        "--manifest-path",
        "fluxer_desktop/native/rust/Cargo.toml",
    ])?;
    run_command(
        &["bun", "--filter", "fluxer_api", "test"],
        RunOptions {
            env,
            load_default_env: false,
            ..RunOptions::default()
        },
    )?;
    Ok(0)
}

pub fn run_build() -> Result<i32> {
    run_generators(false)?;
    task_run(&["bun", "--filter", "fluxer_app", "build"])?;
    build_desktop(false)?;
    Ok(0)
}

pub fn run_lint() -> Result<i32> {
    task_run(&["bunx", "biome", "ci"])?;
    task_run(&["bunx", "eslint", ".", "--max-warnings", "0"])?;
    Ok(0)
}

pub fn run_knip() -> Result<i32> {
    task_run(&["bun", "--filter", "fluxer_app", "i18n:compile"])?;
    task_run(&["bunx", "knip"])?;
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_nats_url_switches_inside_container() {
        let expected_host = if Path::new("/.dockerenv").exists() {
            "nats"
        } else {
            "127.0.0.1"
        };
        assert_eq!(
            default_test_nats_url(),
            format!("nats://{expected_host}:4222")
        );
    }
}
