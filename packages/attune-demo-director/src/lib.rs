use std::collections::{BTreeMap, HashSet};
use std::env;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::os::unix::fs::{FileTypeExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command as ProcessCommand, ExitStatus, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{bail, ensure, Context, Result};
use clap::{Args, CommandFactory, Parser, Subcommand, ValueEnum};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

pub const STAGE_CONFIRMATION: &str = "RECORD-CAMPAIGN-A-STAGE-ONLY";
pub const LAUNCH_CONFIRMATION: &str = "LAUNCH-CAMPAIGN-A-PAID-RUN";
pub const LAUNCH_CONFIRMATION_SHA256: &str =
    "2b81a2f8e8479322f25a384d89edb9771aa7a5e971452da5d81bed76eeaf0f1c";
pub const EMERGENCY_CONFIRMATION: &str = "STOP-CAPTURE-LEAVE-CAMPAIGN-RUNNING";
pub const SPOTIFY_TRACK_ID: &str = "4uXRGIjbWgpYO9R1bIqQ1h";
pub const DEFAULT_AUDIO_DEVICE: &str = "@DEFAULT_AUDIO_SINK@.monitor";

const WIDTH: i64 = 3840;
const HEIGHT: i64 = 2160;
const FPS: i64 = 30;
const NOTEBOOK_HOST: &str = "127.0.0.1";
const NOTEBOOK_PORT: u16 = 2718;
const NOTEBOOK_ORIGIN: &str = "http://127.0.0.1:2718/";
const CHROMIUM_DEBUG_PORT: u16 = 9223;
const WAYVNC_PORT: u16 = 5907;
const FIXTURE_EPOCH_UNIX_MS: u64 = 1_786_795_200_000;
const MIN_FREE_BYTES: u64 = 12 * 1024 * 1024 * 1024;
const ACTIVE_STATE_RELATIVE: &str = ".attune/demo/campaign-a-active.json";
const RECORDINGS_RELATIVE: &str = ".attune/demo/recordings";
const GUTTER_RELATIVE: &str = ".attune/session/campaign-a-gutter.json";

#[derive(Parser, Debug)]
#[command(
    name = "attune-demo-director",
    version,
    about = "Fail-closed 4K Campaign A demo compositor and capture director",
    long_about = None
)]
struct Cli {
    #[command(subcommand)]
    command: Option<CliCommand>,
}

#[derive(Subcommand, Debug)]
enum CliCommand {
    /// Print the bounded choreography. Never launches a process.
    Plan(RepoArg),
    /// Check the live prerequisites without creating windows or playback.
    Doctor(DoctorArgs),
    /// Record a live, separately authorized Campaign A session.
    Record(RecordArgs),
    /// Record the same stage without authority to launch paid Campaign A work.
    Rehearse(RehearseArgs),
    /// Typed Codex handoff: create Marimo/Chromium, preflight, and optionally launch.
    StartRun(SessionArgs),
    /// Present one allowlisted notebook scene, with a temporary compositor enlargement.
    Present(PresentArgs),
    /// Mark an explicit bounded wait interval for derived editing.
    Wait(WaitArgs),
    /// Stop only director-owned capture/UI processes.
    Stop(StopArgs),
    /// Derive a wait-skipping edit plan without touching the master.
    CutPlan(CutArgs),
    /// Render the derived edit while retaining the untouched master.
    Render(RenderArgs),
    #[command(hide = true)]
    TerminalExec(TerminalExecArgs),
}

#[derive(Args, Debug, Clone)]
struct RepoArg {
    /// Attune checkout. Defaults to the current directory.
    #[arg(long)]
    repo: Option<PathBuf>,
}

#[derive(Args, Debug)]
struct DoctorArgs {
    #[command(flatten)]
    repo: RepoArg,
    /// Explicit PipeWire/Pulse source passed to wf-recorder.
    #[arg(long, default_value = DEFAULT_AUDIO_DEVICE)]
    audio_device: String,
    /// Also require loopback `WayVNC` availability.
    #[arg(long)]
    vnc: bool,
}

#[derive(Args, Debug)]
struct RecordArgs {
    #[command(flatten)]
    common: StageArgs,
    /// Independent paid Campaign A authority. The phrase is checked then discarded.
    #[arg(long)]
    launch_confirm: String,
}

#[derive(Args, Debug)]
struct RehearseArgs {
    #[command(flatten)]
    common: StageArgs,
    /// Use deterministic, session-owned Campaign A presentation fixtures.
    #[arg(long, value_enum, requires = "fake_time")]
    fixture: Option<FixtureProfile>,
    /// Require the fixture's fixed presentation clock rather than wall time.
    #[arg(long, requires = "fixture")]
    fake_time: bool,
}

#[derive(Args, Debug)]
struct StageArgs {
    #[command(flatten)]
    repo: RepoArg,
    /// Exact authority to create and record the isolated stage.
    #[arg(long)]
    confirm: String,
    /// Wallpaper painted on the private headless output.
    #[arg(long)]
    wallpaper: Option<PathBuf>,
    /// Explicit PipeWire/Pulse source passed to wf-recorder.
    #[arg(long, default_value = DEFAULT_AUDIO_DEVICE)]
    audio_device: String,
    /// Disable the loopback-only `WayVNC` server.
    #[arg(long)]
    no_vnc: bool,
    /// Seconds the Spotify TUI remains in the three-window composition.
    #[arg(long, default_value_t = 30, value_parser = clap::value_parser!(u64).range(10..=60))]
    spotify_seconds: u64,
}

#[derive(Args, Debug)]
struct SessionArgs {
    #[command(flatten)]
    repo: RepoArg,
    #[arg(long)]
    session: String,
}

#[derive(Args, Debug)]
struct PresentArgs {
    #[command(flatten)]
    session: SessionArgs,
    #[arg(long, value_enum)]
    scene: Scene,
}

#[derive(Args, Debug)]
struct WaitArgs {
    #[command(flatten)]
    session: SessionArgs,
    #[arg(value_enum)]
    boundary: WaitBoundary,
    #[arg(long, value_enum)]
    reason: WaitReason,
}

#[derive(Args, Debug)]
struct StopArgs {
    #[command(flatten)]
    repo: RepoArg,
    /// Exact phrase for capture-only teardown while Campaign A remains active.
    #[arg(long)]
    emergency_confirm: Option<String>,
}

#[derive(Args, Debug)]
struct CutArgs {
    /// One director-owned recording directory.
    #[arg(long)]
    recording_dir: PathBuf,
    /// Seconds retained on each side of an explicit wait.
    #[arg(long, default_value_t = 1.5)]
    handle_seconds: f64,
}

#[derive(Args, Debug)]
struct RenderArgs {
    #[command(flatten)]
    repo: RepoArg,
    #[arg(long)]
    recording_dir: PathBuf,
    #[arg(long, default_value_t = 1.5)]
    handle_seconds: f64,
}

#[derive(Args, Debug)]
struct TerminalExecArgs {
    #[arg(long)]
    window_id_file: Option<PathBuf>,
    #[arg(long, value_enum)]
    role: TerminalRole,
    #[arg(long)]
    repo: Option<PathBuf>,
    #[arg(long)]
    session: Option<String>,
    #[arg(long, value_enum)]
    mode: Option<SessionMode>,
}

#[derive(ValueEnum, Debug, Clone, Copy, PartialEq, Eq)]
enum TerminalRole {
    Spotify,
    Codex,
}

#[derive(ValueEnum, Debug, Clone, Copy, PartialEq, Eq)]
enum SessionMode {
    Rehearsal,
    LiveCampaignA,
}

#[derive(ValueEnum, Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
enum FixtureProfile {
    CampaignADemo,
}

#[derive(ValueEnum, Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
#[clap(rename_all = "kebab-case")]
pub enum Scene {
    EmptyMachine,
    StationMaterializes,
    FrozenContract,
    PreflightEvidence,
    LaunchThreshold,
    PopulationWakes,
    H1ColdQualification,
    H2ResidualComputation,
    H3AdaptiveSearch,
    SemanticDataQuality,
    SemanticRunGeometry,
    SemanticNeighborhoods,
    TraceDescent,
    DeterministicWitness,
    CapabilityContraction,
    H5CompositionWrench,
    ReturnToPopulation,
}

impl Scene {
    const fn as_str(self) -> &'static str {
        match self {
            Self::EmptyMachine => "empty-machine",
            Self::StationMaterializes => "station-materializes",
            Self::FrozenContract => "frozen-contract",
            Self::PreflightEvidence => "preflight-evidence",
            Self::LaunchThreshold => "launch-threshold",
            Self::PopulationWakes => "population-wakes",
            Self::H1ColdQualification => "h1-cold-qualification",
            Self::H2ResidualComputation => "h2-residual-computation",
            Self::H3AdaptiveSearch => "h3-adaptive-search",
            Self::SemanticDataQuality => "semantic-data-quality",
            Self::SemanticRunGeometry => "semantic-run-geometry",
            Self::SemanticNeighborhoods => "semantic-neighborhoods",
            Self::TraceDescent => "trace-descent",
            Self::DeterministicWitness => "deterministic-witness",
            Self::CapabilityContraction => "capability-contraction",
            Self::H5CompositionWrench => "h5-composition-wrench",
            Self::ReturnToPopulation => "return-to-population",
        }
    }
}

#[derive(ValueEnum, Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum WaitBoundary {
    Begin,
    End,
}

#[derive(ValueEnum, Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
enum WaitReason {
    CampaignProgress,
    NotebookReady,
    Qualification,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct ActiveState {
    schema_version: u32,
    status: String,
    repo: PathBuf,
    session_id: String,
    recording_started_unix_ms: u64,
    recording_dir: PathBuf,
    director_path: PathBuf,
    video_path: PathBuf,
    runtime_dir: PathBuf,
    workspace: String,
    output: OutputState,
    #[serde(default)]
    prior_focus: Option<HostFocusState>,
    #[serde(default)]
    fixture: Option<FixtureState>,
    processes: Vec<ProcessRecord>,
    windows: WindowState,
    gutter: Option<GutterState>,
    spotify_started_unix_ms: Option<u64>,
    spotify_seconds: u64,
    #[serde(rename = "launch_authority")]
    launch_authority: Option<LaunchAuthority>,
    #[serde(flatten)]
    extra: BTreeMap<String, Value>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct OutputState {
    physical_name: String,
    created_by_director: bool,
    width: i64,
    height: i64,
    fps: i64,
    x: i64,
    y: i64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct HostFocusState {
    monitor: String,
    workspace: String,
    cursor: CursorPosition,
    output_names: Vec<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct FixtureState {
    profile: FixtureProfile,
    fake_epoch_unix_ms: u64,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
struct CursorPosition {
    x: i64,
    y: i64,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
#[allow(clippy::struct_field_names)]
struct WindowState {
    spotify_address: Option<String>,
    terminal_address: Option<String>,
    browser_address: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct ProcessRecord {
    role: ProcessRole,
    pid: i32,
    process_group: i32,
    start_ticks: String,
    argv_sha256: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
enum ProcessRole {
    Wallpaper,
    Recorder,
    Wayvnc,
    SpotifyTerminal,
    CodexTerminal,
    Marimo,
    Chromium,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct LaunchAuthority {
    schema_version: u32,
    scope: String,
    confirmation_sha256: String,
    recording_started_unix_ms: u64,
    consumed_at: Option<Value>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct GutterState {
    descriptor_path: PathBuf,
    descriptor_sha256: String,
    socket_path: PathBuf,
    window_id_path: PathBuf,
    window_id: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct DirectorEvent {
    schema_version: u32,
    sequence: u64,
    unix_ms: u64,
    elapsed_ms: u64,
    #[serde(flatten)]
    kind: EventKind,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(tag = "event", rename_all = "snake_case")]
enum EventKind {
    RecordingStarted,
    EmptyWallpaper,
    SpotifyStarted { track_id: String },
    WindowMaterialized { role: ProcessRole, address: String },
    CodexStarted,
    MarimoReady,
    ThreeWindowComposition,
    SpotifyStopped,
    TwoUpRestored,
    PreflightRequested,
    CampaignLaunchRequested,
    CampaignLaunchDispatched,
    FixtureTimelineStarted { profile: FixtureProfile },
    FixtureGutterEvent { name: String },
    SceneStarted { scene: Scene },
    SceneCompleted { scene: Scene },
    WaitStarted { reason: WaitReason },
    WaitFinished { reason: WaitReason },
    TeardownStarted,
    RecordingStopped,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
struct CutSegment {
    start_seconds: f64,
    end_seconds: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct CutPlan {
    schema_version: u32,
    source_master: PathBuf,
    derived_only: bool,
    segments: Vec<CutSegment>,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct HyprMonitor {
    name: String,
    width: i64,
    height: i64,
    x: i64,
    y: i64,
    scale: f64,
    focused: bool,
    active_workspace: HyprWorkspaceRef,
}

#[derive(Deserialize, Debug, Clone)]
struct HyprWorkspaceRef {
    id: i64,
    name: String,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
struct HyprActiveWorkspace {
    id: i64,
    name: String,
    monitor: String,
}

#[derive(Deserialize, Debug, Clone)]
struct HyprClient {
    address: String,
    class: String,
    #[serde(rename = "initialClass")]
    initial_class: String,
}

/// Parse and execute one director CLI invocation.
///
/// # Errors
///
/// Returns an error when an invariant or external command fails. Live modes
/// are deliberately fail-closed; inspection modes never create UI state.
pub fn run() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        None => {
            Cli::command().print_help()?;
            println!();
            Ok(())
        }
        Some(CliCommand::Plan(args)) => plan(&resolve_repo(args.repo)?),
        Some(CliCommand::Doctor(args)) => doctor(args),
        Some(CliCommand::Record(args)) => {
            ensure!(
                args.launch_confirm == LAUNCH_CONFIRMATION,
                "live record requires exact --launch-confirm {LAUNCH_CONFIRMATION}"
            );
            start_stage(args.common, true, None)
        }
        Some(CliCommand::Rehearse(args)) => {
            let fixture = args.fixture.map(|profile| FixtureState {
                profile,
                fake_epoch_unix_ms: FIXTURE_EPOCH_UNIX_MS,
            });
            start_stage(args.common, false, fixture.as_ref())
        }
        Some(CliCommand::StartRun(args)) => start_run(args),
        Some(CliCommand::Present(args)) => present(args),
        Some(CliCommand::Wait(args)) => mark_wait(args),
        Some(CliCommand::Stop(args)) => stop(args),
        Some(CliCommand::CutPlan(args)) => write_cut_plan(&args.recording_dir, args.handle_seconds),
        Some(CliCommand::Render(args)) => render(args),
        Some(CliCommand::TerminalExec(args)) => terminal_exec(args),
    }
}

fn plan(repo: &Path) -> Result<()> {
    let plan = json!({
        "schema_version": 1,
        "inert": true,
        "repo": repo,
        "capture": {"width": WIDTH, "height": HEIGHT, "fps": FPS, "audio": "explicit PipeWire source"},
        "sequence": [
            "empty-wallpaper",
            "spotify-player:4uXRGIjbWgpYO9R1bIqQ1h",
            "codex-terminal",
            "typed-start-run",
            "chromeless-marimo:80-percent",
            "temporary-three-window-composition",
            "spotify-pause-and-exact-close",
            "stable-two-up",
            "allowlisted-semantic-presentations",
            "untouched-master-plus-derived-wait-cuts"
        ],
        "live_gates": [STAGE_CONFIRMATION, LAUNCH_CONFIRMATION],
    });
    println!("{}", serde_json::to_string_pretty(&plan)?);
    Ok(())
}

#[allow(clippy::too_many_lines)]
fn doctor(args: DoctorArgs) -> Result<()> {
    let repo = resolve_repo(args.repo.repo)?;
    let mut checks: Vec<(&str, bool, String)> = Vec::new();
    for command in [
        "hyprctl",
        "swaybg",
        "wf-recorder",
        "alacritty",
        "chromium",
        "deno",
        "spotify_player",
        "node",
        "codex",
        "ffmpeg",
    ] {
        let found = find_command(command);
        checks.push((
            command,
            found.is_some(),
            found.map_or_else(|| "not found".into(), |p| p.display().to_string()),
        ));
    }
    if args.vnc {
        let found = find_command("wayvnc");
        checks.push((
            "wayvnc",
            found.is_some(),
            found.map_or_else(|| "not found".into(), |p| p.display().to_string()),
        ));
    }

    let alacritty = ProcessCommand::new("alacritty")
        .args(["msg", "gutter-event", "--help"])
        .output();
    let gutter_ok = alacritty.as_ref().is_ok_and(|output| {
        output.status.success()
            && String::from_utf8_lossy(&output.stdout).contains("campaign-launch")
    });
    checks.push((
        "alacritty-gutter-event",
        gutter_ok,
        if gutter_ok {
            "bounded IPC vocabulary present".into()
        } else {
            "FAILED: installed Alacritty lacks patched `msg gutter-event`".into()
        },
    ));

    let recorder = ProcessCommand::new("wf-recorder").arg("--help").output();
    let recorder_help = recorder
        .as_ref()
        .map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
        .unwrap_or_default();
    let audio_ok = recorder
        .as_ref()
        .is_ok_and(|output| output.status.success())
        && recorder_help.contains("--audio")
        && recorder_help.contains("--audio-backend");
    checks.push((
        "capture-audio",
        audio_ok && !args.audio_device.trim().is_empty(),
        format!("PipeWire source: {}", args.audio_device),
    ));

    let repo_ok = repo.join("scripts/campaign-a-demo.mjs").is_file()
        && repo.join("research/attune_research.py").is_file();
    checks.push(("attune-adapter", repo_ok, repo.display().to_string()));
    let identities = run_adapter_plan(&repo);
    checks.push((
        "frozen-identities",
        identities.is_ok(),
        identities.err().map_or_else(
            || "exact Node plan passed".into(),
            |error| error.to_string(),
        ),
    ));
    let clean = git_status(&repo).is_ok_and(|status| status.is_empty());
    checks.push((
        "live-checkout-clean",
        clean,
        if clean {
            "clean".into()
        } else {
            "dirty; rehearsal only".into()
        },
    ));
    let hypr_ok = env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
        && checked_output("hyprctl", ["-j", "monitors", "all"]).is_ok();
    checks.push((
        "hyprland-session",
        hypr_ok,
        if hypr_ok { "live" } else { "not available" }.into(),
    ));
    let space = available_bytes(&repo).unwrap_or(0);
    checks.push((
        "recording-space",
        space >= MIN_FREE_BYTES,
        format!("{} GiB free; 12 GiB required", space / 1024_u64.pow(3)),
    ));

    let failed = checks.iter().any(|(_, ok, _)| !ok);
    for (name, ok, detail) in checks {
        println!(
            "{:<26} {:<6} {}",
            name,
            if ok { "green" } else { "FAILED" },
            detail
        );
    }
    ensure!(!failed, "doctor failed closed");
    Ok(())
}

fn resolve_repo(repo: Option<PathBuf>) -> Result<PathBuf> {
    let candidate = match repo {
        Some(path) => path,
        None => env::current_dir().context("read current directory")?,
    };
    let resolved = candidate
        .canonicalize()
        .with_context(|| format!("resolve Attune repository {}", candidate.display()))?;
    ensure!(
        resolved.is_dir(),
        "repository is not a directory: {}",
        resolved.display()
    );
    ensure!(
        resolved.join("scripts/campaign-a-demo.mjs").is_file(),
        "Attune semantic demo adapter is absent: {}",
        resolved.join("scripts/campaign-a-demo.mjs").display()
    );
    Ok(resolved)
}

fn active_state_path(repo: &Path) -> PathBuf {
    repo.join(ACTIVE_STATE_RELATIVE)
}

fn load_state(repo: &Path) -> Result<ActiveState> {
    let path = active_state_path(repo);
    let bytes = fs::read(&path).with_context(|| format!("read active state {}", path.display()))?;
    let state: ActiveState =
        serde_json::from_slice(&bytes).context("parse active director state")?;
    ensure!(state.schema_version == 1, "unsupported active-state schema");
    ensure!(
        state.repo == repo,
        "active state belongs to a different repository"
    );
    Ok(state)
}

fn update_state<F>(repo: &Path, update: F) -> Result<ActiveState>
where
    F: FnOnce(&mut ActiveState) -> Result<()>,
{
    let path = active_state_path(repo);
    let mut state = load_state(repo)?;
    update(&mut state)?;
    write_json_atomic(&path, &state)?;
    Ok(state)
}

fn write_json_atomic<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
        fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
    }
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)
        .with_context(|| format!("create {}", temporary.display()))?;
    serde_json::to_writer_pretty(&mut file, value)?;
    file.write_all(b"\n")?;
    file.sync_all()?;
    fs::rename(&temporary, path).with_context(|| format!("replace {}", path.display()))?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

fn append_event(repo: &Path, kind: EventKind) -> Result<DirectorEvent> {
    let state = load_state(repo)?;
    let sequence = if state.director_path.exists() {
        BufReader::new(File::open(&state.director_path)?)
            .lines()
            .map_while(Result::ok)
            .count() as u64
    } else {
        0
    };
    let unix_ms = now_ms()?;
    let event = DirectorEvent {
        schema_version: 1,
        sequence,
        unix_ms,
        elapsed_ms: unix_ms.saturating_sub(state.recording_started_unix_ms),
        kind,
    };
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(&state.director_path)?;
    let mut encoded = serde_json::to_vec(&event)?;
    encoded.push(b'\n');
    file.write_all(&encoded)?;
    file.flush()?;
    Ok(event)
}

fn now_ms() -> Result<u64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock predates Unix epoch")?
        .as_millis()
        .try_into()
        .context("timestamp exceeds u64")
}

fn find_command(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        let path = PathBuf::from(name);
        return path.is_file().then_some(path);
    }
    env::var_os("PATH").and_then(|value| {
        env::split_paths(&value)
            .map(|directory| directory.join(name))
            .find(|candidate| candidate.is_file())
    })
}

fn checked_output<I, S>(program: &str, args: I) -> Result<String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = ProcessCommand::new(program)
        .args(args)
        .output()
        .with_context(|| format!("run {program}"))?;
    ensure_status(program, output.status, &output.stderr)?;
    String::from_utf8(output.stdout).context("command output was not UTF-8")
}

fn checked_status<I, S>(program: &str, args: I, cwd: Option<&Path>) -> Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let mut command = ProcessCommand::new(program);
    command.args(args);
    if let Some(directory) = cwd {
        command.current_dir(directory);
    }
    let output = command.output().with_context(|| format!("run {program}"))?;
    ensure_status(program, output.status, &output.stderr)
}

fn ensure_status(program: &str, status: ExitStatus, stderr: &[u8]) -> Result<()> {
    ensure!(
        status.success(),
        "{program} failed ({status}): {}",
        String::from_utf8_lossy(stderr).trim()
    );
    Ok(())
}

fn available_bytes(path: &Path) -> Result<u64> {
    let path = std::ffi::CString::new(path.as_os_str().as_encoded_bytes())?;
    let mut stats = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    // SAFETY: `path` is NUL-terminated and `stats` points to writable storage.
    let result = unsafe { libc::statvfs(path.as_ptr(), stats.as_mut_ptr()) };
    ensure!(result == 0, "statvfs failed");
    // SAFETY: successful `statvfs` initialized the structure.
    let stats = unsafe { stats.assume_init() };
    Ok(stats.f_bavail.saturating_mul(stats.f_frsize))
}

#[allow(clippy::too_many_lines)]
fn start_stage(args: StageArgs, paid: bool, fixture: Option<&FixtureState>) -> Result<()> {
    ensure!(
        !paid || fixture.is_none(),
        "live Campaign A recording can never use a rehearsal fixture"
    );
    ensure!(
        args.confirm == STAGE_CONFIRMATION,
        "stage creation requires exact --confirm {STAGE_CONFIRMATION}"
    );
    ensure!(
        !args.audio_device.trim().is_empty(),
        "audio device cannot be empty"
    );
    ensure!(
        env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some(),
        "live Hyprland session is absent"
    );
    let repo = resolve_repo(args.repo.repo)?;
    let git_head = if paid {
        let status = git_status(&repo)?;
        ensure!(
            status.is_empty(),
            "live Campaign A recording requires an exactly clean checkout"
        );
        run_adapter_plan(&repo)?;
        Some(
            checked_output(
                "git",
                [
                    "-C",
                    repo.to_str().context("repo path is not UTF-8")?,
                    "rev-parse",
                    "HEAD",
                ],
            )?
            .trim()
            .to_owned(),
        )
    } else {
        None
    };
    ensure!(
        available_bytes(&repo)? >= MIN_FREE_BYTES,
        "recording requires at least 12 GiB free"
    );
    require_runtime_commands(args.no_vnc, fixture.is_none())?;
    require_gutter_event()?;
    ensure!(
        !campaign_worker_running(&repo)?,
        "Campaign A worker is already active; a new stage cannot be launched"
    );

    let active_path = active_state_path(&repo);
    ensure!(
        !repo.join(GUTTER_RELATIVE).exists(),
        "stale Campaign A gutter descriptor is present"
    );
    if active_path.exists() {
        let prior = load_state(&repo)?;
        let any_live = prior.processes.iter().any(process_identity_matches);
        ensure!(
            prior.status != "recording" || !any_live,
            "an exact director stage is already active"
        );
    }

    let wallpaper = args.wallpaper.unwrap_or_else(default_wallpaper);
    ensure!(
        wallpaper.is_file(),
        "wallpaper is absent: {}",
        wallpaper.display()
    );
    let monitors_before = hypr_monitors()?;
    let prior_focus = capture_host_focus(&monitors_before)?;
    let before_names: HashSet<_> = monitors_before
        .iter()
        .map(|item| item.name.clone())
        .collect();
    checked_status("hyprctl", ["output", "create", "headless"], None)?;
    let created = match wait_for_headless(&before_names, Duration::from_secs(10)) {
        Ok(created) => created,
        Err(error) => {
            cleanup_single_new_headless(&before_names, &prior_focus);
            return Err(error);
        }
    };
    let mut output_guard = CreatedOutputGuard::new(created.name.clone(), prior_focus.clone());
    let offscreen_x = monitors_before
        .iter()
        .filter(|monitor| monitor.scale.is_finite() && monitor.scale > 0.0)
        .map(|monitor| monitor.x + logical_dimension(monitor.width, monitor.scale))
        .max()
        .unwrap_or(0)
        + 256;
    let now = now_ms()?;
    let session_id = session_id(&repo, now);
    let workspace = format!("name:attune-demo-{session_id}");
    let recordings_root = repo.join(RECORDINGS_RELATIVE);
    fs::create_dir_all(&recordings_root)?;
    fs::set_permissions(&recordings_root, fs::Permissions::from_mode(0o700))?;
    let recording_dir = recordings_root.join(format!("{now}-{session_id}"));
    fs::create_dir(&recording_dir)?;
    fs::set_permissions(&recording_dir, fs::Permissions::from_mode(0o700))?;
    let runtime_dir = recording_dir.join("runtime");
    fs::create_dir(&runtime_dir)?;
    fs::set_permissions(&runtime_dir, fs::Permissions::from_mode(0o700))?;
    let director_path = recording_dir.join("director.jsonl");
    File::create(&director_path)?;
    fs::set_permissions(&director_path, fs::Permissions::from_mode(0o600))?;
    let video_path = recording_dir.join("campaign-a-master.mkv");

    let state = ActiveState {
        schema_version: 1,
        status: "recording".into(),
        repo: repo.clone(),
        session_id: session_id.clone(),
        recording_started_unix_ms: now,
        recording_dir: recording_dir.clone(),
        director_path,
        video_path: video_path.clone(),
        runtime_dir: runtime_dir.clone(),
        workspace: workspace.clone(),
        output: OutputState {
            physical_name: created.name.clone(),
            created_by_director: true,
            width: WIDTH,
            height: HEIGHT,
            fps: FPS,
            x: offscreen_x,
            y: 0,
        },
        prior_focus: Some(prior_focus.clone()),
        fixture: fixture.cloned(),
        processes: Vec::new(),
        windows: WindowState::default(),
        gutter: None,
        spotify_started_unix_ms: None,
        spotify_seconds: args.spotify_seconds,
        launch_authority: paid.then(|| LaunchAuthority {
            schema_version: 1,
            scope: "campaign-a-paid-run".into(),
            confirmation_sha256: LAUNCH_CONFIRMATION_SHA256.into(),
            recording_started_unix_ms: now,
            consumed_at: None,
        }),
        extra: git_head
            .map(|head| BTreeMap::from([("gitHead".into(), Value::String(head))]))
            .unwrap_or_default(),
    };
    write_json_atomic(&active_path, &state)?;
    output_guard.disarm();

    let setup = (|| -> Result<()> {
        checked_status(
            "hyprctl",
            [
                "keyword",
                "monitor",
                &format!(
                    "{},{}x{}@{},{}x0,1",
                    created.name, WIDTH, HEIGHT, FPS, offscreen_x
                ),
            ],
            None,
        )?;
        checked_status(
            "hyprctl",
            ["dispatch", "focusmonitor", created.name.as_str()],
            None,
        )?;
        checked_status(
            "hyprctl",
            ["dispatch", "workspace", workspace.as_str()],
            None,
        )?;
        restore_host_focus(&prior_focus)?;
        for class in [
            "attune-demo-spotify",
            "attune-demo-codex",
            "attune-demo-marimo",
        ] {
            install_stage_rule(class, &workspace)?;
        }

        let wallpaper_process = spawn_managed(
            &repo,
            &recording_dir,
            ProcessRole::Wallpaper,
            "swaybg",
            vec![
                "-o".into(),
                created.name.clone(),
                "-i".into(),
                wallpaper.display().to_string(),
                "-m".into(),
                "fill".into(),
            ],
        )?;
        push_process(&repo, wallpaper_process.clone())?;
        require_process_live(&wallpaper_process, Duration::from_millis(250))?;
        if !args.no_vnc {
            ensure_loopback_port_available(WAYVNC_PORT, "WayVNC preview")?;
            let wayvnc = spawn_managed(
                &repo,
                &recording_dir,
                ProcessRole::Wayvnc,
                "wayvnc",
                vec![
                    "--output".into(),
                    created.name.clone(),
                    "--disable-input".into(),
                    "127.0.0.1".into(),
                    WAYVNC_PORT.to_string(),
                ],
            )?;
            push_process(&repo, wayvnc.clone())?;
            wait_for_managed_tcp(
                &wayvnc,
                WAYVNC_PORT,
                "WayVNC preview",
                Duration::from_secs(5),
            )?;
        }
        let recorder = spawn_managed(
            &repo,
            &recording_dir,
            ProcessRole::Recorder,
            "wf-recorder",
            vec![
                "--output".into(),
                created.name.clone(),
                "-f".into(),
                video_path.display().to_string(),
                "--codec".into(),
                "libx264".into(),
                "--pixel-format".into(),
                "yuv420p".into(),
                "--framerate".into(),
                FPS.to_string(),
                "--no-damage".into(),
                "--audio-backend=pipewire".into(),
                format!("--audio={}", args.audio_device),
            ],
        )?;
        push_process(&repo, recorder.clone())?;
        require_process_live(&recorder, Duration::from_millis(750))?;
        append_event(&repo, EventKind::RecordingStarted)?;
        append_event(&repo, EventKind::EmptyWallpaper)?;
        thread::sleep(Duration::from_secs(3));

        let executable = env::current_exe()?.display().to_string();
        let spotify = spawn_managed(
            &repo,
            &recording_dir,
            ProcessRole::SpotifyTerminal,
            "alacritty",
            vec![
                "--class".into(),
                "attune-demo-spotify,attune-demo-spotify".into(),
                "--title".into(),
                "SPOTIFY — TRICKY — OVERCOME".into(),
                "--working-directory".into(),
                repo.display().to_string(),
                "-e".into(),
                executable.clone(),
                "terminal-exec".into(),
                "--role".into(),
                "spotify".into(),
                "--mode".into(),
                if paid { "live-campaign-a" } else { "rehearsal" }.into(),
                "--repo".into(),
                repo.display().to_string(),
                "--session".into(),
                session_id.clone(),
            ],
        )?;
        push_process(&repo, spotify)?;
        let spotify_window = wait_for_client("attune-demo-spotify", Duration::from_secs(20))?;
        validate_address(&spotify_window.address)?;
        place_window(
            &workspace,
            &spotify_window.address,
            Rect::spotify(offscreen_x),
        )?;
        set_window(
            &repo,
            ProcessRole::SpotifyTerminal,
            spotify_window.address.clone(),
        )?;
        append_event(
            &repo,
            EventKind::WindowMaterialized {
                role: ProcessRole::SpotifyTerminal,
                address: spotify_window.address,
            },
        )?;
        if fixture.is_none() {
            checked_status(
                "spotify_player",
                ["playback", "start", "track", "--id", SPOTIFY_TRACK_ID],
                Some(&repo),
            )?;
            thread::sleep(Duration::from_millis(900));
            let playback = checked_output("spotify_player", ["get", "key", "playback"])?;
            ensure!(
                playback.contains(SPOTIFY_TRACK_ID),
                "Spotify did not confirm exact track {SPOTIFY_TRACK_ID}; aborting before Campaign A launch"
            );
        }
        let spotify_started = now_ms()?;
        update_state(&repo, |fresh| {
            fresh.spotify_started_unix_ms = Some(spotify_started);
            Ok(())
        })?;
        append_event(
            &repo,
            EventKind::SpotifyStarted {
                track_id: SPOTIFY_TRACK_ID.into(),
            },
        )?;

        let gutter_dir = runtime_dir.join("codex-gutter");
        fs::create_dir(&gutter_dir)?;
        let socket_path = gutter_dir.join("alacritty.sock");
        let window_id_path = gutter_dir.join("window-id");
        let codex = spawn_managed(
            &repo,
            &recording_dir,
            ProcessRole::CodexTerminal,
            "alacritty",
            vec![
                "--socket".into(),
                socket_path.display().to_string(),
                "--class".into(),
                "attune-demo-codex,attune-demo-codex".into(),
                "--title".into(),
                "ATTUNE — CAMPAIGN A — CODEX".into(),
                "--working-directory".into(),
                repo.display().to_string(),
                "-e".into(),
                executable,
                "terminal-exec".into(),
                "--role".into(),
                "codex".into(),
                "--window-id-file".into(),
                window_id_path.display().to_string(),
                "--repo".into(),
                repo.display().to_string(),
                "--session".into(),
                session_id.clone(),
                "--mode".into(),
                if paid { "live-campaign-a" } else { "rehearsal" }.into(),
            ],
        )?;
        push_process(&repo, codex.clone())?;
        let codex_window = wait_for_client("attune-demo-codex", Duration::from_secs(20))?;
        validate_address(&codex_window.address)?;
        place_window(
            &workspace,
            &codex_window.address,
            Rect::codex_three(offscreen_x),
        )?;
        set_window(
            &repo,
            ProcessRole::CodexTerminal,
            codex_window.address.clone(),
        )?;
        append_event(
            &repo,
            EventKind::WindowMaterialized {
                role: ProcessRole::CodexTerminal,
                address: codex_window.address,
            },
        )?;
        let gutter = wait_for_gutter(&socket_path, &window_id_path, Duration::from_secs(8))?;
        let gutter_state = write_gutter_descriptor(&repo, &gutter, &codex)?;
        update_state(&repo, |fresh| {
            fresh.gutter = Some(gutter_state);
            Ok(())
        })?;
        append_event(&repo, EventKind::CodexStarted)?;
        Ok(())
    })();

    if let Err(error) = setup {
        if load_state(&repo)
            .is_ok_and(|state| state.fixture.is_none() && state.spotify_started_unix_ms.is_some())
        {
            let _ = checked_status("spotify_player", ["playback", "pause"], Some(&repo));
        }
        let _ = teardown_stage(&repo, true);
        return Err(error);
    }

    println!("stage:      {}", created.name);
    println!("recording:  {}", video_path.display());
    println!("session:    {session_id}");
    println!(
        "preview:    {}",
        if args.no_vnc {
            "disabled"
        } else {
            "vnc://127.0.0.1:5907"
        }
    );
    println!(
        "Codex received the exact typed handoff: attune-demo-director start-run --repo {} --session {session_id}",
        shell_quote(&repo.display().to_string())
    );
    Ok(())
}

fn require_runtime_commands(no_vnc: bool, require_spotify_player: bool) -> Result<()> {
    let mut required = vec![
        "hyprctl",
        "swaybg",
        "wf-recorder",
        "alacritty",
        "chromium",
        "deno",
        "node",
        "codex",
        "ffmpeg",
    ];
    if require_spotify_player {
        required.push("spotify_player");
    }
    if !no_vnc {
        required.push("wayvnc");
    }
    for command in required {
        ensure!(
            find_command(command).is_some(),
            "required command is unavailable: {command}"
        );
    }
    Ok(())
}

fn require_gutter_event() -> Result<()> {
    let output = ProcessCommand::new("alacritty")
        .args(["msg", "gutter-event", "--help"])
        .output()
        .context("probe Alacritty gutter-event")?;
    ensure!(
        output.status.success()
            && String::from_utf8_lossy(&output.stdout).contains("campaign-launch"),
        "installed Alacritty lacks the required bounded gutter-event IPC vocabulary"
    );
    Ok(())
}

fn default_wallpaper() -> PathBuf {
    env::var_os("HOME")
        .map_or_else(|| PathBuf::from("/home/becker"), PathBuf::from)
        .join("nixos-from-scratch/walls/wallpaper4.jpg")
}

fn git_status(repo: &Path) -> Result<String> {
    checked_output(
        "git",
        [
            "-C",
            repo.to_str().context("repo path is not UTF-8")?,
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
        ],
    )
}

struct CreatedOutputGuard {
    name: Option<String>,
    prior_focus: HostFocusState,
}

impl CreatedOutputGuard {
    fn new(name: String, prior_focus: HostFocusState) -> Self {
        Self {
            name: Some(name),
            prior_focus,
        }
    }

    fn disarm(&mut self) {
        self.name = None;
    }
}

impl Drop for CreatedOutputGuard {
    fn drop(&mut self) {
        if let Some(name) = self.name.take() {
            if let Err(error) = remove_created_output_safely(&name, &self.prior_focus) {
                eprintln!(
                    "refusing unsafe cleanup of {name}; restore the host before removing it: {error:#}"
                );
            }
        }
    }
}

fn session_id(repo: &Path, now: u64) -> String {
    let mut hash = Sha256::new();
    hash.update(repo.as_os_str().as_encoded_bytes());
    hash.update(now.to_le_bytes());
    hash.update(std::process::id().to_le_bytes());
    format!("{:x}", hash.finalize())[..12].to_owned()
}

fn codex_prompt(repo: &Path, session: &str, paid: bool) -> Result<String> {
    let executable = env::current_exe().context("resolve exact running director executable")?;
    codex_prompt_for_executable(repo, session, paid, &executable)
}

fn codex_prompt_for_executable(
    repo: &Path,
    session: &str,
    paid: bool,
    executable: &Path,
) -> Result<String> {
    let prompt_path = repo.join("docs/campaign-a-demo-agent-prompt.md");
    let tracked = fs::read_to_string(&prompt_path)
        .with_context(|| format!("read tracked demo prompt {}", prompt_path.display()))?;
    ensure!(
        tracked.contains("## Session mode and launch authority")
            && tracked.contains("Never click the Campaign A control by any other route")
            && tracked.contains("attune.campaign_worker launch"),
        "tracked demo prompt lost its permanent authority boundary"
    );
    let (mode, authority) = if paid {
        (
            "LIVE_CAMPAIGN_A",
            "This stage has a separately recorded Campaign A authorization.",
        )
    } else {
        (
            "REHEARSAL",
            "This is a rehearsal. It has no Campaign A launch authority; do not request paid work.",
        )
    };
    let repo_arg = shell_quote(&repo.display().to_string());
    let executable_arg = shell_quote(
        executable
            .to_str()
            .context("director executable path is not UTF-8")?,
    );
    Ok(format!(
        "{tracked}\n\n## Exact director handoff\n\n\
SESSION_MODE={mode}\n\
You are presenting the Attune Campaign A notebook from {repo}. {authority}\n\
Run this exact typed handoff now and wait for it to finish:\n\
{executable_arg} start-run --repo {repo_arg} --session {session}\n\
Do not call Python campaign workers directly. The handoff may use only Attune's fixed Node semantic adapter. \
After the handoff, remain at the terminal: the director controller owns the presentation moves. \
Its allowlisted scene commands are:\n\
{executable_arg} present --repo {repo_arg} --session {session} --scene frozen-contract\n\
{executable_arg} present --repo {repo_arg} --session {session} --scene population-wakes\n\
{executable_arg} present --repo {repo_arg} --session {session} --scene deterministic-witness\n\
Use bounded wait begin/end markers around real campaign idle periods. Never inspect secrets, change frozen inputs, launch smoke, or build paid embeddings.",
        repo = repo.display()
    ))
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn hypr_monitors() -> Result<Vec<HyprMonitor>> {
    let output = checked_output("hyprctl", ["-j", "monitors", "all"])?;
    serde_json::from_str(&output).context("parse Hyprland monitors")
}

fn hypr_active_workspace() -> Result<HyprActiveWorkspace> {
    let output = checked_output("hyprctl", ["-j", "activeworkspace"])?;
    serde_json::from_str(&output).context("parse Hyprland active workspace")
}

fn hypr_cursor() -> Result<CursorPosition> {
    let output = checked_output("hyprctl", ["-j", "cursorpos"])?;
    serde_json::from_str(&output).context("parse Hyprland cursor position")
}

fn workspace_selector(id: i64, name: &str) -> String {
    if id > 0 {
        id.to_string()
    } else if name.starts_with("special:") {
        name.to_owned()
    } else {
        format!("name:{name}")
    }
}

fn capture_host_focus(monitors: &[HyprMonitor]) -> Result<HostFocusState> {
    let active = hypr_active_workspace()?;
    ensure!(
        monitors
            .iter()
            .any(|monitor| monitor.name == active.monitor),
        "focused Hyprland monitor is absent from the pre-stage output set"
    );
    Ok(HostFocusState {
        monitor: active.monitor,
        workspace: workspace_selector(active.id, &active.name),
        cursor: hypr_cursor()?,
        output_names: monitors
            .iter()
            .map(|monitor| monitor.name.clone())
            .collect(),
    })
}

fn monitor_contains_cursor(monitor: &HyprMonitor, cursor: CursorPosition) -> bool {
    if !monitor.scale.is_finite() || monitor.scale <= 0.0 {
        return false;
    }
    let logical_width = logical_dimension(monitor.width, monitor.scale);
    let logical_height = logical_dimension(monitor.height, monitor.scale);
    cursor.x >= monitor.x
        && cursor.x < monitor.x + logical_width
        && cursor.y >= monitor.y
        && cursor.y < monitor.y + logical_height
}

#[allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]
fn logical_dimension(physical_pixels: i64, scale: f64) -> i64 {
    ((physical_pixels as f64) / scale).ceil() as i64
}

fn monitor_center(monitor: &HyprMonitor) -> CursorPosition {
    CursorPosition {
        x: monitor.x + logical_dimension(monitor.width, monitor.scale) / 2,
        y: monitor.y + logical_dimension(monitor.height, monitor.scale) / 2,
    }
}

fn monitor_focus_restore_required(active: &HyprActiveWorkspace, target: &HostFocusState) -> bool {
    active.monitor != target.monitor
}

fn workspace_restore_required(monitors: &[HyprMonitor], target: &HostFocusState) -> Result<bool> {
    let monitor_workspace = &monitors
        .iter()
        .find(|monitor| monitor.name == target.monitor)
        .with_context(|| format!("restored host monitor disappeared: {}", target.monitor))?
        .active_workspace;
    Ok(workspace_selector(monitor_workspace.id, &monitor_workspace.name) != target.workspace)
}

fn restore_host_focus(target: &HostFocusState) -> Result<()> {
    let monitors = hypr_monitors()?;
    ensure!(
        monitors
            .iter()
            .any(|monitor| monitor.name == target.monitor),
        "host monitor disappeared: {}",
        target.monitor
    );
    let active = hypr_active_workspace()?;
    if monitor_focus_restore_required(&active, target) {
        checked_status(
            "hyprctl",
            ["dispatch", "focusmonitor", target.monitor.as_str()],
            None,
        )?;
    }
    // `focusmonitor` updates raw monitor focus before `activeworkspace` catches
    // up. Read the destination monitor itself so workspace_back_and_forth
    // cannot turn an unnecessary restore into a switch to the previous desk.
    if workspace_restore_required(&hypr_monitors()?, target)? {
        checked_status(
            "hyprctl",
            ["dispatch", "workspace", target.workspace.as_str()],
            None,
        )?;
    }
    checked_status(
        "hyprctl",
        [
            "dispatch",
            "movecursor",
            &format!("{} {}", target.cursor.x, target.cursor.y),
        ],
        None,
    )?;
    wait_for_host_focus(target, Duration::from_secs(2))
}

fn host_focus_restored(
    monitors: &[HyprMonitor],
    cursor: CursorPosition,
    target: &HostFocusState,
) -> bool {
    monitors.iter().any(|item| {
        item.name == target.monitor
            && item.focused
            && workspace_selector(item.active_workspace.id, &item.active_workspace.name)
                == target.workspace
            && monitor_contains_cursor(item, cursor)
    })
}

fn wait_for_host_focus(target: &HostFocusState, timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let monitors = hypr_monitors()?;
        let cursor = hypr_cursor()?;
        if host_focus_restored(&monitors, cursor, target) {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(25));
    }
    bail!("Hyprland did not restore the host monitor/workspace/cursor")
}

fn current_host_focus(state: &ActiveState) -> Result<HostFocusState> {
    let prior = state
        .prior_focus
        .as_ref()
        .context("director state lacks its pre-stage host focus snapshot")?;
    let monitors = hypr_monitors()?;
    let host_monitors: Vec<_> = monitors
        .iter()
        .filter(|monitor| {
            monitor.name != state.output.physical_name && prior.output_names.contains(&monitor.name)
        })
        .collect();
    ensure!(
        !host_monitors.is_empty(),
        "no pre-stage host output remains"
    );
    let active = hypr_active_workspace()?;
    let target = host_monitors
        .iter()
        .copied()
        .find(|monitor| monitor.name == active.monitor)
        .or_else(|| {
            host_monitors
                .iter()
                .copied()
                .find(|monitor| monitor.name == prior.monitor)
        })
        .or_else(|| {
            host_monitors
                .iter()
                .copied()
                .find(|monitor| monitor.focused)
        })
        .unwrap_or(host_monitors[0]);
    let observed_cursor = hypr_cursor()?;
    let cursor = if host_monitors
        .iter()
        .any(|monitor| monitor_contains_cursor(monitor, observed_cursor))
    {
        observed_cursor
    } else if host_monitors
        .iter()
        .any(|monitor| monitor_contains_cursor(monitor, prior.cursor))
    {
        prior.cursor
    } else {
        monitor_center(target)
    };
    Ok(HostFocusState {
        monitor: target.name.clone(),
        workspace: workspace_selector(target.active_workspace.id, &target.active_workspace.name),
        cursor,
        output_names: prior.output_names.clone(),
    })
}

fn hypr_workspace_exists(selector: &str) -> Result<bool> {
    let output = checked_output("hyprctl", ["-j", "workspaces"])?;
    let workspaces: Vec<Value> =
        serde_json::from_str(&output).context("parse Hyprland workspaces")?;
    let expected_name = selector.strip_prefix("name:");
    Ok(workspaces.iter().any(|workspace| {
        expected_name
            .is_some_and(|name| workspace.get("name").and_then(Value::as_str) == Some(name))
            || workspace
                .get("id")
                .and_then(Value::as_i64)
                .is_some_and(|id| id.to_string() == selector)
    }))
}

fn hypr_clients() -> Result<Vec<HyprClient>> {
    let output = checked_output("hyprctl", ["-j", "clients"])?;
    serde_json::from_str(&output).context("parse Hyprland clients")
}

fn wait_for_headless(before: &HashSet<String>, timeout: Duration) -> Result<HyprMonitor> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let added: Vec<_> = hypr_monitors()?
            .into_iter()
            .filter(|monitor| !before.contains(&monitor.name))
            .collect();
        if added.len() == 1 && added[0].name.starts_with("HEADLESS-") {
            return Ok(added[0].clone());
        }
        ensure!(
            added.len() <= 1,
            "more than one output appeared while creating the stage"
        );
        thread::sleep(Duration::from_millis(100));
    }
    bail!("Hyprland did not expose exactly one new HEADLESS output")
}

fn wait_for_output_absent(name: &str, timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if !hypr_monitors()?.iter().any(|monitor| monitor.name == name) {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(100));
    }
    bail!("Hyprland output did not disappear: {name}")
}

fn remove_created_output_safely(name: &str, host_focus: &HostFocusState) -> Result<()> {
    restore_host_focus(host_focus).context("evacuate focus from director output")?;
    checked_status("hyprctl", ["output", "remove", name], None)?;
    wait_for_output_absent(name, Duration::from_secs(5))?;
    // Hyprland's disconnect path warps to a backup output. Restore the exact
    // pre-stage position only after that disconnect-time warp has completed.
    restore_host_focus(host_focus).context("restore host after director output removal")
}

fn cleanup_single_new_headless(before: &HashSet<String>, host_focus: &HostFocusState) {
    let Ok(monitors) = hypr_monitors() else {
        return;
    };
    let added: Vec<_> = monitors
        .iter()
        .filter(|monitor| !before.contains(&monitor.name) && monitor.name.starts_with("HEADLESS-"))
        .collect();
    if added.len() == 1 {
        let _ = remove_created_output_safely(&added[0].name, host_focus);
    }
}

fn wait_for_client(class: &str, timeout: Duration) -> Result<HyprClient> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Some(client) = hypr_clients()?
            .into_iter()
            .find(|client| client.class == class || client.initial_class == class)
        {
            return Ok(client);
        }
        thread::sleep(Duration::from_millis(120));
    }
    bail!("Hyprland client did not appear: {class}")
}

fn install_stage_rule(class: &str, workspace: &str) -> Result<()> {
    let rule = class.replace('-', "_");
    for (property, value) in [
        ("match:class", format!("^({class})$")),
        ("workspace", format!("{workspace} silent")),
        ("float", "on".into()),
        ("no_initial_focus", "on".into()),
        ("enable", "true".into()),
    ] {
        checked_status(
            "hyprctl",
            ["keyword", &format!("windowrule[{rule}]:{property}"), &value],
            None,
        )?;
    }
    Ok(())
}

fn remove_stage_rule(class: &str) {
    let rule = class.replace('-', "_");
    let _ = checked_status(
        "hyprctl",
        ["keyword", &format!("windowrule[{rule}]:enable"), "false"],
        None,
    );
}

#[derive(Clone, Copy)]
struct Rect {
    x: i64,
    y: i64,
    width: i64,
    height: i64,
}

impl Rect {
    const fn spotify(output_x: i64) -> Self {
        Self {
            x: output_x + 70,
            y: 150,
            width: 900,
            height: 1780,
        }
    }

    const fn codex_three(output_x: i64) -> Self {
        Self {
            x: output_x + 1010,
            y: 110,
            width: 1300,
            height: 1920,
        }
    }

    const fn browser_three(output_x: i64) -> Self {
        Self {
            x: output_x + 2350,
            y: 90,
            width: 1420,
            height: 1980,
        }
    }

    const fn codex_two(output_x: i64) -> Self {
        Self {
            x: output_x + 70,
            y: 90,
            width: 1740,
            height: 1980,
        }
    }

    const fn browser_two(output_x: i64) -> Self {
        Self {
            x: output_x + 1850,
            y: 90,
            width: 1920,
            height: 1980,
        }
    }

    const fn browser_present(output_x: i64) -> Self {
        Self {
            x: output_x + 520,
            y: 70,
            width: 3240,
            height: 2020,
        }
    }
}

fn validate_address(address: &str) -> Result<()> {
    ensure!(
        address.len() > 2
            && address.starts_with("0x")
            && address[2..].bytes().all(|byte| byte.is_ascii_hexdigit()),
        "unsafe Hyprland address: {address}"
    );
    Ok(())
}

fn place_window(workspace: &str, address: &str, rect: Rect) -> Result<()> {
    validate_address(address)?;
    let selector = format!("address:{address}");
    checked_status(
        "hyprctl",
        [
            "dispatch",
            "movetoworkspacesilent",
            &format!("{workspace},{selector}"),
        ],
        None,
    )?;
    checked_status("hyprctl", ["dispatch", "setfloating", &selector], None)?;
    checked_status(
        "hyprctl",
        [
            "dispatch",
            "movewindowpixel",
            &format!("exact {} {},{selector}", rect.x, rect.y),
        ],
        None,
    )?;
    checked_status(
        "hyprctl",
        [
            "dispatch",
            "resizewindowpixel",
            &format!("exact {} {},{selector}", rect.width, rect.height),
        ],
        None,
    )?;
    Ok(())
}

#[allow(clippy::needless_pass_by_value)]
fn spawn_managed(
    repo: &Path,
    recording_dir: &Path,
    role: ProcessRole,
    program: &str,
    args: Vec<String>,
) -> Result<ProcessRecord> {
    let label = role_label(role);
    let stdout = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(recording_dir.join(format!("{label}.stdout.log")))?;
    let stderr = OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(recording_dir.join(format!("{label}.stderr.log")))?;
    let mut command = ProcessCommand::new(program);
    command
        .args(&args)
        .current_dir(repo)
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr));
    command.process_group(0);
    let child = command.spawn().with_context(|| format!("spawn {label}"))?;
    let pid: i32 = child.id().try_into().context("child PID exceeds i32")?;
    let start_ticks = wait_for_start_ticks(pid, Duration::from_secs(2))?;
    let mut hash = Sha256::new();
    hash.update(program.as_bytes());
    for arg in &args {
        hash.update([0]);
        hash.update(arg.as_bytes());
    }
    Ok(ProcessRecord {
        role,
        pid,
        process_group: pid,
        start_ticks,
        argv_sha256: format!("{:x}", hash.finalize()),
    })
}

const fn role_label(role: ProcessRole) -> &'static str {
    match role {
        ProcessRole::Wallpaper => "wallpaper",
        ProcessRole::Recorder => "recorder",
        ProcessRole::Wayvnc => "wayvnc",
        ProcessRole::SpotifyTerminal => "spotify-terminal",
        ProcessRole::CodexTerminal => "codex-terminal",
        ProcessRole::Marimo => "marimo",
        ProcessRole::Chromium => "chromium",
    }
}

fn wait_for_start_ticks(pid: i32, timeout: Duration) -> Result<String> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Some(ticks) = process_start_ticks(pid) {
            return Ok(ticks);
        }
        thread::sleep(Duration::from_millis(10));
    }
    bail!("process {pid} disappeared before its Linux start time could be recorded")
}

fn process_start_ticks(pid: i32) -> Option<String> {
    if pid <= 1 {
        return None;
    }
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let close = stat.rfind(')')?;
    stat.get(close + 2..)?
        .split_whitespace()
        .nth(19)
        .map(ToOwned::to_owned)
}

fn process_identity_matches(record: &ProcessRecord) -> bool {
    record.pid > 1
        && record.process_group == record.pid
        && process_start_ticks(record.pid).as_deref() == Some(record.start_ticks.as_str())
}

fn require_process_live(record: &ProcessRecord, settle: Duration) -> Result<()> {
    thread::sleep(settle);
    ensure!(
        process_identity_matches(record),
        "{} exited during startup; inspect its exact recording log",
        role_label(record.role)
    );
    Ok(())
}

fn push_process(repo: &Path, record: ProcessRecord) -> Result<()> {
    update_state(repo, |fresh| {
        fresh.processes.push(record);
        Ok(())
    })?;
    Ok(())
}

fn set_window(repo: &Path, role: ProcessRole, address: String) -> Result<()> {
    update_state(repo, |fresh| {
        match role {
            ProcessRole::SpotifyTerminal => fresh.windows.spotify_address = Some(address),
            ProcessRole::CodexTerminal => fresh.windows.terminal_address = Some(address),
            ProcessRole::Chromium => fresh.windows.browser_address = Some(address),
            _ => bail!("role does not own a window"),
        }
        Ok(())
    })?;
    Ok(())
}

struct GutterTarget {
    socket_path: PathBuf,
    window_id_path: PathBuf,
    window_id: String,
}

fn wait_for_gutter(socket: &Path, window_id: &Path, timeout: Duration) -> Result<GutterTarget> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let socket_ready =
            fs::symlink_metadata(socket).is_ok_and(|metadata| metadata.file_type().is_socket());
        if socket_ready && window_id.is_file() {
            let id = fs::read_to_string(window_id)?.trim().to_owned();
            ensure!(
                !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit()) && id != "0",
                "invalid Alacritty window ID"
            );
            return Ok(GutterTarget {
                socket_path: socket.to_path_buf(),
                window_id_path: window_id.to_path_buf(),
                window_id: id,
            });
        }
        thread::sleep(Duration::from_millis(50));
    }
    bail!("Codex Alacritty gutter target did not materialize")
}

fn write_gutter_descriptor(
    repo: &Path,
    target: &GutterTarget,
    process: &ProcessRecord,
) -> Result<GutterState> {
    let path = repo.join(GUTTER_RELATIVE);
    ensure!(
        !path.exists(),
        "stale gutter descriptor is present: {}",
        path.display()
    );
    let descriptor = json!({
        "schema_version": 1,
        "socket": target.socket_path,
        "window_id": target.window_id,
        "process": {
            "pid": process.pid,
            "start_ticks": process.start_ticks,
            "argv_sha256": process.argv_sha256,
        }
    });
    write_json_atomic(&path, &descriptor)?;
    let digest = sha256_file(&path)?;
    Ok(GutterState {
        descriptor_path: path,
        descriptor_sha256: digest,
        socket_path: target.socket_path.clone(),
        window_id_path: target.window_id_path.clone(),
        window_id: target.window_id.clone(),
    })
}

fn emit_fixture_gutter_event(repo: &Path, name: &str) -> Result<()> {
    let state = load_state(repo)?;
    ensure!(
        state.fixture.is_some() && state.launch_authority.is_none(),
        "fixture gutter events require a rehearsal fixture with null launch authority"
    );
    let gutter = state
        .gutter
        .as_ref()
        .context("fixture gutter target is absent")?;
    ensure!(
        gutter.socket_path.is_absolute()
            && fs::symlink_metadata(&gutter.socket_path)
                .is_ok_and(|metadata| metadata.file_type().is_socket()),
        "fixture gutter socket is absent"
    );
    ensure!(
        !gutter.window_id.is_empty() && gutter.window_id.bytes().all(|byte| byte.is_ascii_digit()),
        "fixture gutter window ID is invalid"
    );
    checked_status(
        "alacritty",
        [
            "msg",
            "--socket",
            gutter
                .socket_path
                .to_str()
                .context("gutter socket is not UTF-8")?,
            "gutter-event",
            name,
            "--window-id",
            gutter.window_id.as_str(),
        ],
        Some(repo),
    )?;
    append_event(
        repo,
        EventKind::FixtureGutterEvent {
            name: name.to_owned(),
        },
    )?;
    Ok(())
}

fn emit_fixture_gutter_for_scene(repo: &Path, scene: Scene) {
    let names: &[&str] = match scene {
        Scene::FrozenContract => &["campaign-launch", "candidate-start"],
        Scene::PopulationWakes => &["candidate-pass"],
        Scene::H1ColdQualification => &["qualification-start", "qualified"],
        Scene::H2ResidualComputation => &["verify"],
        Scene::DeterministicWitness => &["qualified"],
        Scene::H5CompositionWrench => &[
            "composition-start",
            "composition-pass",
            "wrench-start",
            "wrench-reject",
        ],
        Scene::ReturnToPopulation => &["complete"],
        _ => &[],
    };
    for name in names {
        if let Err(error) = emit_fixture_gutter_event(repo, name) {
            eprintln!("fixture-only gutter event {name} was not delivered: {error:#}");
        }
    }
}

fn sha256_file(path: &Path) -> Result<String> {
    let mut file = File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0_u8; 8192];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hash.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hash.finalize()))
}

#[allow(clippy::too_many_lines)]
fn start_run(args: SessionArgs) -> Result<()> {
    let repo = resolve_repo(args.repo.repo)?;
    let initial = require_session(&repo, &args.session)?;
    let fixture = initial.fixture.clone();
    ensure!(
        initial.windows.browser_address.is_none(),
        "start-run was already materialized"
    );
    let claim_path = initial.runtime_dir.join("start-run.claim");
    let mut claim = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&claim_path)
        .with_context(|| {
            format!(
                "claim exact start-run handoff {}; an existing claim permanently refuses a duplicate",
                claim_path.display()
            )
        })?;
    writeln!(claim, "schema_version=1\nsession={}", args.session)?;
    claim.sync_all()?;
    let spotify_identity = initial
        .processes
        .iter()
        .find(|record| record.role == ProcessRole::SpotifyTerminal)
        .cloned()
        .context("Spotify terminal identity is absent")?;
    let mut playback_guard =
        SpotifyPlaybackGuard::new(repo.clone(), spotify_identity, fixture.is_none());
    let notebook_path = if fixture.is_some() {
        "research/campaign_a_rehearsal.py"
    } else {
        "research/attune_research.py"
    };
    ensure!(
        repo.join(notebook_path).is_file(),
        "selected Marimo notebook is absent: {notebook_path}"
    );

    let marimo_program;
    let marimo_args;
    let local_marimo = repo.join(".venv/bin/marimo");
    if local_marimo.is_file() {
        marimo_program = local_marimo.display().to_string();
        marimo_args = vec![
            "run".into(),
            "--headless".into(),
            "--no-token".into(),
            "--host".into(),
            NOTEBOOK_HOST.into(),
            "--port".into(),
            NOTEBOOK_PORT.to_string(),
            notebook_path.into(),
        ];
    } else {
        ensure!(
            find_command("uv").is_some(),
            "neither .venv/bin/marimo nor uv is available"
        );
        marimo_program = "uv".into();
        marimo_args = vec![
            "run".into(),
            "marimo".into(),
            "run".into(),
            "--headless".into(),
            "--no-token".into(),
            "--host".into(),
            NOTEBOOK_HOST.into(),
            "--port".into(),
            NOTEBOOK_PORT.to_string(),
            notebook_path.into(),
        ];
    }
    ensure_loopback_port_available(NOTEBOOK_PORT, "Marimo notebook")?;
    let marimo = spawn_managed(
        &repo,
        &initial.recording_dir,
        ProcessRole::Marimo,
        &marimo_program,
        marimo_args,
    )?;
    push_process(&repo, marimo.clone())?;
    wait_for_managed_tcp(
        &marimo,
        NOTEBOOK_PORT,
        "Marimo notebook",
        Duration::from_mins(1),
    )?;
    append_event(&repo, EventKind::MarimoReady)?;

    let profile = initial.runtime_dir.join("chromium-profile");
    fs::create_dir_all(&profile)?;
    ensure_loopback_port_available(CHROMIUM_DEBUG_PORT, "Chromium DevTools")?;
    let chromium = spawn_managed(
        &repo,
        &initial.recording_dir,
        ProcessRole::Chromium,
        "chromium",
        vec![
            format!("--app={NOTEBOOK_ORIGIN}"),
            "--class=attune-demo-marimo".into(),
            "--ozone-platform=wayland".into(),
            "--enable-features=UseOzonePlatform".into(),
            "--force-device-scale-factor=0.8".into(),
            "--no-first-run".into(),
            "--no-default-browser-check".into(),
            format!("--user-data-dir={}", profile.display()),
            "--remote-debugging-address=127.0.0.1".into(),
            format!("--remote-debugging-port={CHROMIUM_DEBUG_PORT}"),
            format!("--remote-allow-origins=http://127.0.0.1:{CHROMIUM_DEBUG_PORT}"),
        ],
    )?;
    push_process(&repo, chromium.clone())?;
    wait_for_managed_tcp(
        &chromium,
        CHROMIUM_DEBUG_PORT,
        "Chromium DevTools",
        Duration::from_secs(30),
    )?;
    let browser = wait_for_client("attune-demo-marimo", Duration::from_secs(30))?;
    require_process_live(&chromium, Duration::ZERO)?;
    validate_address(&browser.address)?;
    place_window(
        &initial.workspace,
        &browser.address,
        Rect::browser_three(initial.output.x),
    )?;
    set_window(&repo, ProcessRole::Chromium, browser.address.clone())?;
    let current = require_session(&repo, &args.session)?;
    if let Some(address) = current.windows.spotify_address.as_deref() {
        place_window(&current.workspace, address, Rect::spotify(current.output.x))?;
    }
    if let Some(address) = current.windows.terminal_address.as_deref() {
        place_window(
            &current.workspace,
            address,
            Rect::codex_three(current.output.x),
        )?;
    }
    append_event(
        &repo,
        EventKind::WindowMaterialized {
            role: ProcessRole::Chromium,
            address: browser.address,
        },
    )?;
    append_event(&repo, EventKind::ThreeWindowComposition)?;

    let current = require_session(&repo, &args.session)?;
    let spotify_started = current
        .spotify_started_unix_ms
        .context("Spotify playback start was not recorded")?;
    let close_at = spotify_started.saturating_add(current.spotify_seconds.saturating_mul(1000));
    let now = now_ms()?;
    if close_at > now {
        thread::sleep(Duration::from_millis(close_at - now));
    }
    if fixture.is_none() {
        checked_status("spotify_player", ["playback", "pause"], Some(&repo))?;
    }
    let spotify = current
        .processes
        .iter()
        .find(|record| record.role == ProcessRole::SpotifyTerminal)
        .context("Spotify terminal identity is absent")?;
    stop_exact_process(spotify, libc::SIGTERM)?;
    wait_for_process_exit(spotify, Duration::from_secs(3));
    ensure!(
        !process_identity_matches(spotify),
        "Spotify terminal did not close after exact targeted teardown"
    );
    playback_guard.disarm();
    append_event(&repo, EventKind::SpotifyStopped)?;

    let current = require_session(&repo, &args.session)?;
    let terminal = current
        .windows
        .terminal_address
        .as_deref()
        .context("Codex window is absent")?;
    let browser = current
        .windows
        .browser_address
        .as_deref()
        .context("Marimo window is absent")?;
    place_window(
        &current.workspace,
        terminal,
        Rect::codex_two(current.output.x),
    )?;
    place_window(
        &current.workspace,
        browser,
        Rect::browser_two(current.output.x),
    )?;
    append_event(&repo, EventKind::TwoUpRestored)?;

    // Keep the frozen-identity verification, rendered preflight request, and
    // optional single-use launch adjacent. No entertainment choreography or
    // stale notebook state is allowed between these boundaries.
    let current = require_session(&repo, &args.session)?;
    verify_recorded_checkout(&current)?;
    run_adapter_plan(&repo)?;
    if let Some(fixture) = fixture {
        ensure!(
            current.launch_authority.is_none(),
            "fixture rehearsal must never hold Campaign A launch authority"
        );
        append_event(
            &repo,
            EventKind::FixtureTimelineStarted {
                profile: fixture.profile,
            },
        )?;
        println!(
            "rehearsal fixture: fixed presentation clock {} with session-owned analytical evidence; Campaign A was not launched",
            fixture.fake_epoch_unix_ms
        );
    } else {
        run_adapter(&repo, &["act", "--name", "run_preflight"])?;
        append_event(&repo, EventKind::PreflightRequested)?;
    }

    let current = require_session(&repo, &args.session)?;
    if let Some(authority) = &current.launch_authority {
        verify_recorded_checkout(&current)?;
        ensure!(
            authority.schema_version == 1,
            "invalid launch authority schema"
        );
        ensure!(
            authority.scope == "campaign-a-paid-run",
            "invalid launch authority scope"
        );
        ensure!(
            authority.confirmation_sha256 == LAUNCH_CONFIRMATION_SHA256,
            "invalid launch authority digest"
        );
        ensure!(
            authority.recording_started_unix_ms == current.recording_started_unix_ms,
            "launch authority is not bound to this recording"
        );
        ensure!(
            authority.consumed_at.is_none(),
            "launch authority was already consumed"
        );
        append_event(&repo, EventKind::CampaignLaunchRequested)?;
        run_adapter(
            &repo,
            &[
                "act",
                "--name",
                "launch_campaign",
                "--confirm",
                LAUNCH_CONFIRMATION,
            ],
        )?;
        append_event(&repo, EventKind::CampaignLaunchDispatched)?;
    } else {
        println!("rehearsal: preflight complete; Campaign A launch was not authorized");
    }
    Ok(())
}

fn require_session(repo: &Path, session: &str) -> Result<ActiveState> {
    ensure!(
        session.len() == 12 && session.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "invalid session identifier"
    );
    let state = load_state(repo)?;
    ensure!(state.status == "recording", "director is not recording");
    ensure!(
        state.session_id == session,
        "session identifier does not match active state"
    );
    ensure!(
        state
            .processes
            .iter()
            .any(|record| record.role == ProcessRole::Recorder && process_identity_matches(record)),
        "exact recorder process is no longer live"
    );
    Ok(state)
}

fn verify_recorded_checkout(state: &ActiveState) -> Result<()> {
    if state.launch_authority.is_none() {
        return Ok(());
    }
    ensure!(
        git_status(&state.repo)?.is_empty(),
        "live checkout changed during recording"
    );
    let recorded = state
        .extra
        .get("gitHead")
        .and_then(Value::as_str)
        .context("live recording state lacks its exact gitHead")?;
    let current = checked_output(
        "git",
        [
            "-C",
            state.repo.to_str().context("repo path is not UTF-8")?,
            "rev-parse",
            "HEAD",
        ],
    )?;
    ensure!(
        current.trim() == recorded,
        "live checkout HEAD changed during recording"
    );
    Ok(())
}

fn loopback_address(port: u16) -> SocketAddr {
    SocketAddr::from(([127, 0, 0, 1], port))
}

fn ensure_loopback_port_available(port: u16, service: &str) -> Result<()> {
    let address = loopback_address(port);
    let listener = TcpListener::bind(address)
        .with_context(|| format!("{service} fixed address {address} is already occupied"))?;
    drop(listener);
    Ok(())
}

fn wait_for_managed_tcp(
    process: &ProcessRecord,
    port: u16,
    service: &str,
    timeout: Duration,
) -> Result<()> {
    let address = loopback_address(port);
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        ensure!(
            process_identity_matches(process),
            "{} exited before binding its fixed address {}",
            role_label(process.role),
            address
        );
        if TcpStream::connect_timeout(&address, Duration::from_millis(300)).is_ok() {
            ensure!(
                process_identity_matches(process),
                "{} exited while {service} became ready",
                role_label(process.role)
            );
            return Ok(());
        }
        thread::sleep(Duration::from_millis(200));
    }
    bail!("{service} did not bind fixed address {address}")
}

fn run_adapter(repo: &Path, suffix: &[&str]) -> Result<()> {
    let script = repo.join("scripts/campaign-a-demo.mjs");
    let mut args = vec![script.display().to_string()];
    args.extend(suffix.iter().map(ToString::to_string));
    checked_status("node", args, Some(repo))
}

fn run_adapter_plan(repo: &Path) -> Result<()> {
    run_adapter(repo, &["plan"])
}

fn wait_for_process_exit(record: &ProcessRecord, timeout: Duration) {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline && process_identity_matches(record) {
        thread::sleep(Duration::from_millis(50));
    }
}

fn stop_exact_process(record: &ProcessRecord, signal: i32) -> Result<bool> {
    if !process_identity_matches(record) {
        return Ok(false);
    }
    // SAFETY: the negative, previously identity-checked PID targets only the
    // process group created for this director-owned child.
    let result = unsafe { libc::kill(-record.process_group, signal) };
    if result == 0 {
        Ok(true)
    } else {
        let error = std::io::Error::last_os_error();
        if error.raw_os_error() == Some(libc::ESRCH) {
            Ok(false)
        } else {
            Err(error).context("signal exact director process group")
        }
    }
}

struct SpotifyPlaybackGuard {
    repo: PathBuf,
    process: ProcessRecord,
    armed: bool,
    pause_playback: bool,
}

impl SpotifyPlaybackGuard {
    fn new(repo: PathBuf, process: ProcessRecord, pause_playback: bool) -> Self {
        Self {
            repo,
            process,
            armed: true,
            pause_playback,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for SpotifyPlaybackGuard {
    fn drop(&mut self) {
        if self.armed {
            if self.pause_playback {
                let _ = checked_status("spotify_player", ["playback", "pause"], Some(&self.repo));
            }
            let _ = stop_exact_process(&self.process, libc::SIGTERM);
        }
    }
}

fn terminal_exec(args: TerminalExecArgs) -> Result<()> {
    if args.role == TerminalRole::Spotify && args.mode == Some(SessionMode::Rehearsal) {
        let repo = resolve_repo(args.repo.clone())?;
        let session = args
            .session
            .as_deref()
            .context("fixture Spotify terminal requires --session")?;
        let state = require_session(&repo, session)?;
        let fixture = state
            .fixture
            .as_ref()
            .context("rehearsal Spotify terminal requires an explicit fixture profile")?;
        return run_fixture_spotify_terminal(fixture, state.spotify_seconds);
    }
    let (display, program, child_args) = match args.role {
        TerminalRole::Spotify => {
            ensure!(
                args.window_id_file.is_none() && args.mode == Some(SessionMode::LiveCampaignA),
                "live Spotify terminal requires only its exact typed live-session mode"
            );
            (
                format!("spotify_player  # Overcome · {SPOTIFY_TRACK_ID}"),
                "spotify_player".to_owned(),
                Vec::new(),
            )
        }
        TerminalRole::Codex => {
            let path = args
                .window_id_file
                .as_deref()
                .context("Codex terminal requires --window-id-file")?;
            let id = env::var("ALACRITTY_WINDOW_ID").context("ALACRITTY_WINDOW_ID is absent")?;
            ensure!(
                !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit()),
                "invalid Alacritty window ID"
            );
            write_jsonless_atomic(path, format!("{id}\n").as_bytes())?;
            let repo = resolve_repo(args.repo)?;
            let session = args.session.context("Codex terminal requires --session")?;
            ensure!(
                session.len() == 12 && session.bytes().all(|byte| byte.is_ascii_hexdigit()),
                "invalid session identifier"
            );
            let paid = match args.mode.context("Codex terminal requires --mode")? {
                SessionMode::Rehearsal => false,
                SessionMode::LiveCampaignA => true,
            };
            let prompt = codex_prompt(&repo, &session, paid)?;
            (
                format!("codex --cd {} 'Start the Campaign A run'", repo.display()),
                "codex".to_owned(),
                vec![
                    "--dangerously-bypass-approvals-and-sandbox".into(),
                    "--no-alt-screen".into(),
                    "--cd".into(),
                    repo.display().to_string(),
                    prompt,
                ],
            )
        }
    };
    print!("\x1b[1;36m❯\x1b[0m ");
    std::io::stdout().flush()?;
    for character in display.chars() {
        print!("{character}");
        std::io::stdout().flush()?;
        thread::sleep(Duration::from_millis(18));
    }
    println!();
    let error = ProcessCommand::new(program).args(child_args).exec();
    Err(error).context("exec terminal child")
}

fn run_fixture_spotify_terminal(fixture: &FixtureState, visible_seconds: u64) -> Result<()> {
    ensure!(
        fixture.profile == FixtureProfile::CampaignADemo,
        "unsupported rehearsal fixture profile"
    );
    let start = Instant::now();
    let duration = Duration::from_secs(visible_seconds.max(10));
    print!("\x1b[?25l");
    loop {
        let elapsed = start.elapsed();
        let fake_elapsed =
            u64::try_from(elapsed.as_millis().saturating_mul(18)).unwrap_or(u64::MAX);
        let playback = fake_elapsed % 236_000;
        let position = format_fixture_clock(playback);
        let total = "03:56";
        let filled = usize::try_from((playback.saturating_mul(28)) / 236_000).unwrap_or(28);
        let bar = format!("{}{}", "━".repeat(filled), "─".repeat(28 - filled));
        let pulse =
            ["▁▃▆█▆▃", "▂▅█▅▂▁", "▄█▄▂▁▂", "█▆▃▁▃▆"][(elapsed.as_millis() / 250 % 4) as usize];
        let transition = if elapsed >= duration {
            "two-window transition queued"
        } else {
            "closes with the two-window transition"
        };
        print!(
            "\x1b[2J\x1b[H\x1b[1;32mSPOTIFY PLAYER\x1b[0m   \x1b[2mREHEARSAL FIXTURE · FAKE TIME\x1b[0m\n\n\
             \x1b[1;37mNOW PLAYING\x1b[0m\n\
             Overcome\n\
             Tricky\n\n\
             \x1b[1;36m{pulse}\x1b[0m  {position}  \x1b[2m{bar}\x1b[0m  {total}\n\n\
             ◀◀    \x1b[1;32m▶\x1b[0m    ▶▶     ♫  fixture visual playback\n\n\
             \x1b[2mfixed clock epoch: {} · {transition}\x1b[0m\n",
            fixture.fake_epoch_unix_ms,
        );
        std::io::stdout().flush()?;
        thread::sleep(Duration::from_millis(250));
    }
}

fn format_fixture_clock(milliseconds: u64) -> String {
    format!(
        "{:02}:{:02}",
        milliseconds / 60_000,
        (milliseconds / 1_000) % 60
    )
}

fn write_jsonless_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    fs::rename(&temporary, path)?;
    Ok(())
}

fn present(args: PresentArgs) -> Result<()> {
    let repo = resolve_repo(args.session.repo.repo)?;
    let state = require_session(&repo, &args.session.session)?;
    let fixture = state.fixture.is_some();
    let browser = state
        .windows
        .browser_address
        .as_deref()
        .context("Marimo window is absent")?;
    let normal = Rect::browser_two(state.output.x);
    place_window(
        &state.workspace,
        browser,
        Rect::browser_present(state.output.x),
    )?;
    checked_status(
        "hyprctl",
        ["dispatch", "alterzorder", &format!("top,address:{browser}")],
        None,
    )?;
    append_event(&repo, EventKind::SceneStarted { scene: args.scene })?;
    let result = run_adapter(&repo, &["drive", "--scene", args.scene.as_str()]);
    let restore = place_window(&state.workspace, browser, normal);
    restore.context("restore deterministic two-up geometry")?;
    result?;
    if fixture {
        emit_fixture_gutter_for_scene(&repo, args.scene);
    }
    append_event(&repo, EventKind::SceneCompleted { scene: args.scene })?;
    Ok(())
}

fn mark_wait(args: WaitArgs) -> Result<()> {
    let repo = resolve_repo(args.session.repo.repo)?;
    require_session(&repo, &args.session.session)?;
    let kind = match args.boundary {
        WaitBoundary::Begin => EventKind::WaitStarted {
            reason: args.reason,
        },
        WaitBoundary::End => EventKind::WaitFinished {
            reason: args.reason,
        },
    };
    let event = append_event(&repo, kind)?;
    println!("{}", serde_json::to_string(&event)?);
    Ok(())
}

fn stop(args: StopArgs) -> Result<()> {
    let repo = resolve_repo(args.repo.repo)?;
    load_state(&repo)?;
    if campaign_worker_running(&repo)? {
        ensure!(
            args.emergency_confirm.as_deref() == Some(EMERGENCY_CONFIRMATION),
            "Campaign A is starting/running or its lock is held; normal stop refuses. To stop capture only while leaving the scientific worker untouched, pass exact --emergency-confirm {EMERGENCY_CONFIRMATION}"
        );
    } else {
        ensure!(
            args.emergency_confirm.is_none(),
            "emergency confirmation is only valid while Campaign A is active"
        );
    }
    teardown_stage(&repo, false)
}

fn teardown_stage(repo: &Path, startup_failure: bool) -> Result<()> {
    let state = load_state(repo)?;
    if state.status == "stopped" {
        return Ok(());
    }
    let _ = append_event(repo, EventKind::TeardownStarted);

    if state.fixture.is_none() && state.spotify_started_unix_ms.is_some() {
        let _ = checked_status("spotify_player", ["playback", "pause"], Some(repo));
    }

    // WayVNC uses Hyprland's single seat. Stop it first so no remote pointer
    // event can race the host-focus evacuation below.
    if let Some(wayvnc) = state
        .processes
        .iter()
        .find(|record| record.role == ProcessRole::Wayvnc)
    {
        let _ = stop_exact_process(wayvnc, libc::SIGTERM);
        wait_for_process_exit(wayvnc, Duration::from_secs(3));
    }

    // Close the application clients, but retain the stage wallpaper until the
    // recorder has finalized so the captured tail never reveals Hyprland's
    // built-in background.
    for record in state.processes.iter().rev().filter(|record| {
        !matches!(
            record.role,
            ProcessRole::Recorder | ProcessRole::Wallpaper | ProcessRole::Wayvnc
        )
    }) {
        let _ = stop_exact_process(record, libc::SIGTERM);
    }
    thread::sleep(Duration::from_millis(500));
    if let Some(recorder) = state
        .processes
        .iter()
        .find(|record| record.role == ProcessRole::Recorder)
    {
        let _ = stop_exact_process(recorder, libc::SIGINT);
        wait_for_process_exit(recorder, Duration::from_secs(5));
        if process_identity_matches(recorder) {
            let _ = stop_exact_process(recorder, libc::SIGTERM);
            wait_for_process_exit(recorder, Duration::from_secs(2));
        }
    }

    for record in state
        .processes
        .iter()
        .rev()
        .filter(|record| !matches!(record.role, ProcessRole::Wallpaper | ProcessRole::Wayvnc))
    {
        if process_identity_matches(record) {
            let _ = stop_exact_process(record, libc::SIGKILL);
        }
    }
    let _ = append_event(repo, EventKind::RecordingStopped);

    remove_exact_gutter(&state)?;
    for class in [
        "attune-demo-spotify",
        "attune-demo-codex",
        "attune-demo-marimo",
    ] {
        remove_stage_rule(class);
    }

    let host_focus = current_host_focus(&state)?;
    restore_host_focus(&host_focus)?;
    if hypr_workspace_exists(&state.workspace)? {
        checked_status(
            "hyprctl",
            [
                "dispatch",
                "moveworkspacetomonitor",
                &format!("{} {}", state.workspace, host_focus.monitor),
            ],
            None,
        )?;
        restore_host_focus(&host_focus)?;
    }

    if let Some(wallpaper) = state
        .processes
        .iter()
        .find(|record| record.role == ProcessRole::Wallpaper)
    {
        let _ = stop_exact_process(wallpaper, libc::SIGTERM);
        wait_for_process_exit(wallpaper, Duration::from_secs(2));
        if process_identity_matches(wallpaper) {
            let _ = stop_exact_process(wallpaper, libc::SIGKILL);
        }
    }

    if state.output.created_by_director
        && hypr_monitors()?
            .iter()
            .any(|monitor| monitor.name == state.output.physical_name)
    {
        remove_created_output_safely(&state.output.physical_name, &host_focus)?;
    } else {
        restore_host_focus(&host_focus)?;
    }
    ensure!(
        !hypr_workspace_exists(&state.workspace)?,
        "director workspace survived headless-output teardown"
    );
    let stopped = update_state(repo, |fresh| {
        fresh.status = if startup_failure { "failed" } else { "stopped" }.into();
        Ok(())
    })?;
    write_json_atomic(&stopped.recording_dir.join("session-final.json"), &stopped)?;
    Ok(())
}

fn remove_exact_gutter(state: &ActiveState) -> Result<()> {
    let Some(gutter) = &state.gutter else {
        return Ok(());
    };
    if !gutter.descriptor_path.exists() {
        return Ok(());
    }
    if sha256_file(&gutter.descriptor_path)? != gutter.descriptor_sha256 {
        eprintln!("gutter descriptor changed; leaving the replacement untouched");
        return Ok(());
    }
    fs::remove_file(&gutter.descriptor_path)?;
    Ok(())
}

fn campaign_worker_running(repo: &Path) -> Result<bool> {
    let local_python = repo.join(".venv/bin/python");
    let python = if local_python.is_file() {
        local_python
    } else {
        find_command("python3").context("Python is unavailable for Campaign A status")?
    };
    let output = ProcessCommand::new(python)
        .args(["-m", "attune.campaign_worker", "status"])
        .current_dir(repo)
        .output()
        .context("read Campaign A worker status")?;
    ensure_status(
        "attune.campaign_worker status",
        output.status,
        &output.stderr,
    )?;
    let stdout = String::from_utf8(output.stdout)?;
    let value: Value = serde_json::from_str(&stdout).context("parse Campaign A worker status")?;
    campaign_worker_status_is_unsafe(&value)
}

fn campaign_worker_status_is_unsafe(value: &Value) -> Result<bool> {
    let active = value
        .get("active")
        .and_then(Value::as_bool)
        .context("Campaign A worker status lacks boolean active")?;
    let lock_held = value
        .get("lock_held")
        .and_then(Value::as_bool)
        .context("Campaign A worker status lacks boolean lock_held")?;
    let phase = value
        .get("phase")
        .and_then(Value::as_str)
        .context("Campaign A worker status lacks string phase")?;
    Ok(active || lock_held || matches!(phase, "starting" | "running"))
}

struct EventStream {
    rust: Vec<DirectorEvent>,
    node_semantic: Vec<(f64, String)>,
}

fn read_events(path: &Path) -> Result<EventStream> {
    let file = File::open(path).with_context(|| format!("read {}", path.display()))?;
    let mut stream = EventStream {
        rust: Vec::new(),
        node_semantic: Vec::new(),
    };
    for (index, line) in BufReader::new(file).lines().enumerate() {
        let line = line?;
        let value: Value = serde_json::from_str(&line)
            .with_context(|| format!("parse director event line {}", index + 1))?;
        if value.get("schema_version").is_some() {
            stream.rust.push(
                serde_json::from_value(value)
                    .with_context(|| format!("parse Rust director event line {}", index + 1))?,
            );
        } else if value.get("schemaVersion").is_some() {
            let at = value
                .get("t")
                .and_then(Value::as_f64)
                .with_context(|| format!("Node event line {} lacks bounded time", index + 1))?;
            let event = value
                .get("event")
                .and_then(Value::as_str)
                .with_context(|| format!("Node event line {} lacks a semantic name", index + 1))?;
            ensure!(
                at.is_finite() && at >= 0.0,
                "invalid Node event time on line {}",
                index + 1
            );
            stream.node_semantic.push((at, event.to_owned()));
        } else {
            bail!("unknown director event schema on line {}", index + 1);
        }
    }
    Ok(stream)
}

struct WaitInterval {
    start: f64,
    end: f64,
    reason: String,
}

fn bounded_wait_intervals(events: &[DirectorEvent]) -> Result<Vec<WaitInterval>> {
    let mut open: BTreeMap<String, f64> = BTreeMap::new();
    let mut waits = Vec::new();
    for event in events {
        let at = Duration::from_millis(event.elapsed_ms).as_secs_f64();
        match &event.kind {
            EventKind::WaitStarted { reason } => {
                let key = format!("{reason:?}");
                ensure!(
                    open.insert(key, at).is_none(),
                    "nested wait interval for {reason:?}"
                );
            }
            EventKind::WaitFinished { reason } => {
                let key = format!("{reason:?}");
                let start = open
                    .remove(&key)
                    .with_context(|| format!("wait end without start: {reason:?}"))?;
                ensure!(at >= start, "wait interval runs backwards: {reason:?}");
                waits.push(WaitInterval {
                    start,
                    end: at,
                    reason: key,
                });
            }
            _ => {}
        }
    }
    ensure!(
        open.is_empty(),
        "director stream has an unclosed wait interval"
    );
    Ok(waits)
}

fn safe_wait_cuts(
    stream: &EventStream,
    waits: &[WaitInterval],
    handle_seconds: f64,
) -> Result<Vec<(f64, f64)>> {
    let mut cuts = Vec::new();
    for wait in waits {
        let rust_semantic = stream.rust.iter().find(|event| {
            let at = Duration::from_millis(event.elapsed_ms).as_secs_f64();
            at >= wait.start
                && at <= wait.end
                && !matches!(
                    &event.kind,
                    EventKind::WaitStarted { .. } | EventKind::WaitFinished { .. }
                )
        });
        ensure!(
            rust_semantic.is_none(),
            "wait interval {:?} contains a Rust semantic event",
            wait.reason
        );
        let node_semantic = stream
            .node_semantic
            .iter()
            .find(|(at, _)| *at >= wait.start && *at <= wait.end);
        ensure!(
            node_semantic.is_none(),
            "wait interval {:?} contains Node semantic event {}",
            wait.reason,
            node_semantic.map_or("<unknown>", |(_, event)| event.as_str())
        );
        let cut_start = wait.start + handle_seconds;
        let cut_end = wait.end - handle_seconds;
        if cut_end > cut_start {
            cuts.push((cut_start, cut_end));
        }
    }
    Ok(cuts)
}

fn derive_cut_plan(recording_dir: &Path, handle_seconds: f64) -> Result<CutPlan> {
    ensure!(
        handle_seconds.is_finite() && (0.0..=5.0).contains(&handle_seconds),
        "handle seconds must be from 0 to 5"
    );
    let recording_dir = recording_dir
        .canonicalize()
        .context("resolve recording directory")?;
    let master = recording_dir.join("campaign-a-master.mkv");
    let stream = read_events(&recording_dir.join("director.jsonl"))?;
    let events = &stream.rust;
    ensure!(
        master.is_file(),
        "untouched master is absent: {}",
        master.display()
    );
    ensure!(!events.is_empty(), "director event stream is empty");
    let duration = events
        .iter()
        .rev()
        .find(|event| matches!(event.kind, EventKind::RecordingStopped))
        .map(|event| Duration::from_millis(event.elapsed_ms).as_secs_f64())
        .context("recording has no bounded recording_stopped event")?;
    let waits = bounded_wait_intervals(events)?;
    let mut cuts = safe_wait_cuts(&stream, &waits, handle_seconds)?;
    cuts.sort_by(|left, right| left.0.total_cmp(&right.0));
    let mut cursor = 0.0;
    let mut segments = Vec::new();
    for (cut_start, cut_end) in cuts {
        ensure!(
            cut_start >= cursor && cut_end <= duration,
            "wait intervals overlap or exceed master duration"
        );
        if cut_start > cursor {
            segments.push(CutSegment {
                start_seconds: cursor,
                end_seconds: cut_start,
            });
        }
        cursor = cut_end;
    }
    if cursor < duration {
        segments.push(CutSegment {
            start_seconds: cursor,
            end_seconds: duration,
        });
    }
    ensure!(
        !segments.is_empty(),
        "cut plan would remove the whole recording"
    );
    Ok(CutPlan {
        schema_version: 1,
        source_master: master,
        derived_only: true,
        segments,
    })
}

fn write_cut_plan(recording_dir: &Path, handle_seconds: f64) -> Result<()> {
    let plan = derive_cut_plan(recording_dir, handle_seconds)?;
    let path = recording_dir.canonicalize()?.join("cut-plan.json");
    write_json_atomic(&path, &plan)?;
    println!("{}", path.display());
    Ok(())
}

fn render(args: RenderArgs) -> Result<()> {
    let repo = resolve_repo(args.repo.repo)?;
    let state = load_state(&repo)?;
    ensure!(
        state.status == "stopped",
        "render requires a cleanly stopped capture"
    );
    ensure!(
        !campaign_worker_running(&repo)?,
        "render refuses while Campaign A is starting/running"
    );
    let directory = args.recording_dir.canonicalize()?;
    ensure!(
        directory == state.recording_dir,
        "render directory is not the exact active-session recording"
    );
    let plan = derive_cut_plan(&directory, args.handle_seconds)?;
    let plan_path = directory.join("cut-plan.json");
    write_json_atomic(&plan_path, &plan)?;
    let concat_path = directory.join("cut-plan.ffconcat");
    ensure!(
        !concat_path.exists(),
        "derived concat plan already exists: {}",
        concat_path.display()
    );
    let master = plan.source_master.to_string_lossy();
    ensure!(
        !master.contains('\''),
        "master path contains unsupported quote character"
    );
    let mut concat = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(&concat_path)?;
    writeln!(concat, "ffconcat version 1.0")?;
    for segment in &plan.segments {
        writeln!(concat, "file '{master}'")?;
        writeln!(concat, "inpoint {:.3}", segment.start_seconds)?;
        writeln!(concat, "outpoint {:.3}", segment.end_seconds)?;
    }
    let derived = directory.join("campaign-a-wait-skipped.mkv");
    ensure!(
        !derived.exists(),
        "derived render already exists: {}",
        derived.display()
    );
    checked_status(
        "ffmpeg",
        [
            "-hide_banner",
            "-loglevel",
            "warning",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            concat_path.to_str().context("concat path is not UTF-8")?,
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            derived.to_str().context("derived path is not UTF-8")?,
        ],
        Some(&directory),
    )?;
    ensure!(
        plan.source_master.is_file(),
        "master disappeared during derived render"
    );
    println!("master:  {} (untouched)", plan.source_master.display());
    println!("derived: {}", derived.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::ValueEnum;
    use tempfile::TempDir;

    fn fixture_state(repo: &Path, recording_dir: &Path) -> ActiveState {
        ActiveState {
            schema_version: 1,
            status: "recording".into(),
            repo: repo.to_path_buf(),
            session_id: "0123456789ab".into(),
            recording_started_unix_ms: 1_000,
            recording_dir: recording_dir.to_path_buf(),
            director_path: recording_dir.join("director.jsonl"),
            video_path: recording_dir.join("campaign-a-master.mkv"),
            runtime_dir: recording_dir.join("runtime"),
            workspace: "name:attune-demo-test".into(),
            output: OutputState {
                physical_name: "HEADLESS-99".into(),
                created_by_director: true,
                width: WIDTH,
                height: HEIGHT,
                fps: FPS,
                x: 3000,
                y: 0,
            },
            prior_focus: Some(HostFocusState {
                monitor: "eDP-1".into(),
                workspace: "2".into(),
                cursor: CursorPosition { x: 800, y: 500 },
                output_names: vec!["eDP-1".into()],
            }),
            fixture: None,
            processes: vec![ProcessRecord {
                role: ProcessRole::Recorder,
                pid: 123,
                process_group: 123,
                start_ticks: "456".into(),
                argv_sha256: "0".repeat(64),
            }],
            windows: WindowState::default(),
            gutter: None,
            spotify_started_unix_ms: None,
            spotify_seconds: 30,
            launch_authority: Some(LaunchAuthority {
                schema_version: 1,
                scope: "campaign-a-paid-run".into(),
                confirmation_sha256: LAUNCH_CONFIRMATION_SHA256.into(),
                recording_started_unix_ms: 1_000,
                consumed_at: Some(Value::String("node-owned-stamp".into())),
            }),
            extra: BTreeMap::from([
                ("gitHead".into(), Value::String("deadbeef".into())),
                ("nodeOwnedFutureField".into(), json!({"kept": true})),
            ]),
        }
    }

    #[test]
    fn confirmation_phrases_are_distinct_and_digest_is_exact() {
        assert_ne!(STAGE_CONFIRMATION, LAUNCH_CONFIRMATION);
        assert_eq!(
            format!("{:x}", Sha256::digest(LAUNCH_CONFIRMATION.as_bytes())),
            LAUNCH_CONFIRMATION_SHA256
        );
    }

    #[test]
    fn default_cli_and_plan_are_inert() {
        let parsed = Cli::try_parse_from(["attune-demo-director"]).unwrap();
        assert!(parsed.command.is_none());
        let parsed =
            Cli::try_parse_from(["attune-demo-director", "plan", "--repo", "/tmp"]).unwrap();
        assert!(matches!(parsed.command, Some(CliCommand::Plan(_))));
    }

    #[test]
    fn host_cursor_bounds_use_logical_monitor_geometry() {
        let monitor = HyprMonitor {
            name: "eDP-1".into(),
            width: 2560,
            height: 1600,
            x: 0,
            y: 0,
            scale: 1.6,
            focused: true,
            active_workspace: HyprWorkspaceRef {
                id: 2,
                name: "2".into(),
            },
        };
        assert!(monitor_contains_cursor(
            &monitor,
            CursorPosition { x: 800, y: 500 }
        ));
        assert!(!monitor_contains_cursor(
            &monitor,
            CursorPosition { x: 2816, y: 500 }
        ));
        assert_eq!(monitor_center(&monitor), CursorPosition { x: 800, y: 500 });
        assert_eq!(workspace_selector(2, "2"), "2");
        assert_eq!(workspace_selector(-3, "attune-demo"), "name:attune-demo");
    }

    #[test]
    fn host_restore_does_not_toggle_an_already_active_workspace() {
        let target = HostFocusState {
            monitor: "eDP-1".into(),
            workspace: "3".into(),
            cursor: CursorPosition { x: 800, y: 500 },
            output_names: vec!["eDP-1".into()],
        };
        let stale_global_active = HyprActiveWorkspace {
            id: -2,
            name: "attune-demo-session".into(),
            monitor: "HEADLESS-2".into(),
        };
        let mut monitors = vec![
            HyprMonitor {
                name: "eDP-1".into(),
                width: 2560,
                height: 1600,
                x: 0,
                y: 0,
                scale: 1.6,
                focused: false,
                active_workspace: HyprWorkspaceRef {
                    id: 3,
                    name: "3".into(),
                },
            },
            HyprMonitor {
                name: "HEADLESS-2".into(),
                width: 1920,
                height: 1080,
                x: 1856,
                y: 0,
                scale: 1.0,
                focused: true,
                active_workspace: HyprWorkspaceRef {
                    id: -2,
                    name: "attune-demo-session".into(),
                },
            },
        ];

        assert!(monitor_focus_restore_required(
            &stale_global_active,
            &target
        ));
        assert!(!workspace_restore_required(&monitors, &target).unwrap());

        monitors[0].active_workspace = HyprWorkspaceRef {
            id: 2,
            name: "2".into(),
        };
        assert!(workspace_restore_required(&monitors, &target).unwrap());
    }

    #[test]
    fn live_record_requires_a_separate_launch_confirmation_argument() {
        assert!(Cli::try_parse_from([
            "attune-demo-director",
            "record",
            "--confirm",
            STAGE_CONFIRMATION,
        ])
        .is_err());
        let parsed = Cli::try_parse_from([
            "attune-demo-director",
            "record",
            "--confirm",
            STAGE_CONFIRMATION,
            "--launch-confirm",
            LAUNCH_CONFIRMATION,
        ])
        .unwrap();
        assert!(matches!(parsed.command, Some(CliCommand::Record(_))));
        assert!(Cli::try_parse_from([
            "attune-demo-director",
            "record",
            "--confirm",
            STAGE_CONFIRMATION,
            "--launch-confirm",
            LAUNCH_CONFIRMATION,
            "--fixture",
            "campaign-a-demo",
            "--fake-time",
        ])
        .is_err());
    }

    #[test]
    fn fixture_clock_is_rehearsal_only_and_requires_its_explicit_flag() {
        assert!(Cli::try_parse_from([
            "attune-demo-director",
            "rehearse",
            "--confirm",
            STAGE_CONFIRMATION,
            "--fixture",
            "campaign-a-demo",
        ])
        .is_err());
        let parsed = Cli::try_parse_from([
            "attune-demo-director",
            "rehearse",
            "--confirm",
            STAGE_CONFIRMATION,
            "--fixture",
            "campaign-a-demo",
            "--fake-time",
        ])
        .unwrap();
        let Some(CliCommand::Rehearse(args)) = parsed.command else {
            panic!("fixture command did not parse as rehearsal");
        };
        assert_eq!(args.fixture, Some(FixtureProfile::CampaignADemo));
        assert!(args.fake_time);
        assert_eq!(format_fixture_clock(236_000), "03:56");
    }

    #[test]
    fn scenes_are_exact_storyboard_ids_not_dom_targets() {
        let expected = [
            "empty-machine",
            "station-materializes",
            "frozen-contract",
            "preflight-evidence",
            "launch-threshold",
            "population-wakes",
            "h1-cold-qualification",
            "h2-residual-computation",
            "h3-adaptive-search",
            "semantic-data-quality",
            "semantic-run-geometry",
            "semantic-neighborhoods",
            "trace-descent",
            "deterministic-witness",
            "capability-contraction",
            "h5-composition-wrench",
            "return-to-population",
        ];
        let actual: Vec<_> = Scene::value_variants()
            .iter()
            .map(|scene| scene.as_str())
            .collect();
        assert_eq!(actual, expected);
        assert!(!actual.contains(&"protocol"));
        assert!(!actual.contains(&"completion"));
    }

    #[test]
    fn fresh_state_update_preserves_node_consumption_and_unknown_fields() {
        let temporary = TempDir::new().unwrap();
        let repo = temporary.path().canonicalize().unwrap();
        let recording = repo.join("recording");
        fs::create_dir_all(&recording).unwrap();
        let state = fixture_state(&repo, &recording);
        let encoded = serde_json::to_value(&state).unwrap();
        assert_eq!(encoded["schemaVersion"], 1);
        assert!(encoded.get("launch_authority").is_some());
        assert!(encoded.get("launchAuthority").is_none());
        assert_eq!(encoded["processes"][0]["role"], "recorder");
        assert_eq!(encoded["processes"][0]["pid"], 123);
        assert_eq!(encoded["processes"][0]["startTicks"], "456");
        assert_eq!(encoded["priorFocus"]["monitor"], "eDP-1");
        assert_eq!(encoded["priorFocus"]["cursor"]["x"], 800);
        assert_eq!(encoded["gitHead"], "deadbeef");
        assert!(!serde_json::to_string(&encoded)
            .unwrap()
            .contains(LAUNCH_CONFIRMATION));
        write_json_atomic(&active_state_path(&repo), &state).unwrap();

        update_state(&repo, |fresh| {
            fresh.windows.browser_address = Some("0xabc".into());
            Ok(())
        })
        .unwrap();
        let updated = load_state(&repo).unwrap();
        assert_eq!(
            updated.launch_authority.unwrap().consumed_at,
            Some(Value::String("node-owned-stamp".into()))
        );
        assert_eq!(updated.extra["nodeOwnedFutureField"], json!({"kept": true}));
    }

    #[test]
    fn exact_process_identity_includes_linux_start_ticks() {
        let pid = i32::try_from(std::process::id()).unwrap();
        let ticks = process_start_ticks(pid).unwrap();
        let record = ProcessRecord {
            role: ProcessRole::Recorder,
            pid,
            process_group: pid,
            start_ticks: ticks,
            argv_sha256: "0".repeat(64),
        };
        assert!(process_identity_matches(&record));
        let mut recycled = record;
        recycled.start_ticks.push('1');
        assert!(!process_identity_matches(&recycled));
    }

    #[test]
    fn fixed_port_checks_reject_occupancy_and_wrong_process_identity() {
        let listener = TcpListener::bind(loopback_address(0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let error = ensure_loopback_port_available(port, "test service").unwrap_err();
        assert!(error.to_string().contains("already occupied"));

        let wrong_identity = ProcessRecord {
            role: ProcessRole::Marimo,
            pid: i32::try_from(std::process::id()).unwrap(),
            process_group: i32::try_from(std::process::id()).unwrap(),
            start_ticks: "not-the-current-start-time".into(),
            argv_sha256: "0".repeat(64),
        };
        let error = wait_for_managed_tcp(
            &wrong_identity,
            port,
            "test service",
            Duration::from_millis(10),
        )
        .unwrap_err();
        assert!(error.to_string().contains("exited before binding"));
        drop(listener);
        ensure_loopback_port_available(port, "test service").unwrap();
    }

    #[test]
    fn worker_status_treats_held_lock_and_malformed_status_as_unsafe() {
        assert!(campaign_worker_status_is_unsafe(
            &json!({"phase": "idle", "active": false, "lock_held": true})
        )
        .unwrap());
        assert!(!campaign_worker_status_is_unsafe(
            &json!({"phase": "idle", "active": false, "lock_held": false})
        )
        .unwrap());
        assert!(campaign_worker_status_is_unsafe(
            &json!({"phase": "running", "active": false, "lock_held": false})
        )
        .unwrap());
        assert!(
            campaign_worker_status_is_unsafe(&json!({"phase": "idle", "active": false})).is_err()
        );
    }

    #[test]
    fn cut_plan_preserves_semantic_events_and_uses_only_bounded_waits() {
        let temporary = TempDir::new().unwrap();
        let directory = temporary.path();
        File::create(directory.join("campaign-a-master.mkv")).unwrap();
        let mut events = File::create(directory.join("director.jsonl")).unwrap();
        let rust_event = |sequence, elapsed_ms, kind| DirectorEvent {
            schema_version: 1,
            sequence,
            unix_ms: 1_000 + elapsed_ms,
            elapsed_ms,
            kind,
        };
        for event in [
            rust_event(0, 0, EventKind::RecordingStarted),
            rust_event(
                1,
                10_000,
                EventKind::WaitStarted {
                    reason: WaitReason::CampaignProgress,
                },
            ),
        ] {
            writeln!(events, "{}", serde_json::to_string(&event).unwrap()).unwrap();
        }
        writeln!(
            events,
            "{}",
            json!({"schemaVersion": 1, "t": 5.0, "event": "chapter", "scene": "frozen-contract"})
        )
        .unwrap();
        for event in [
            rust_event(
                3,
                30_000,
                EventKind::WaitFinished {
                    reason: WaitReason::CampaignProgress,
                },
            ),
            rust_event(4, 40_000, EventKind::RecordingStopped),
        ] {
            writeln!(events, "{}", serde_json::to_string(&event).unwrap()).unwrap();
        }
        drop(events);

        let plan = derive_cut_plan(directory, 2.0).unwrap();
        assert_eq!(
            plan.segments,
            vec![
                CutSegment {
                    start_seconds: 0.0,
                    end_seconds: 12.0,
                },
                CutSegment {
                    start_seconds: 28.0,
                    end_seconds: 40.0,
                },
            ]
        );
        assert!(plan.derived_only);
        assert!(plan.source_master.is_file());

        let mut events = OpenOptions::new()
            .append(true)
            .open(directory.join("director.jsonl"))
            .unwrap();
        writeln!(
            events,
            "{}",
            json!({"schemaVersion": 1, "t": 10.0, "event": "campaign_launch"})
        )
        .unwrap();
        drop(events);
        let error = derive_cut_plan(directory, 2.0).unwrap_err();
        assert!(error.to_string().contains("contains Node semantic event"));
    }

    #[test]
    fn cut_plan_rejects_rust_semantic_event_at_wait_boundary() {
        let temporary = TempDir::new().unwrap();
        let directory = temporary.path();
        File::create(directory.join("campaign-a-master.mkv")).unwrap();
        let mut events = File::create(directory.join("director.jsonl")).unwrap();
        let rust_event = |sequence, elapsed_ms, kind| DirectorEvent {
            schema_version: 1,
            sequence,
            unix_ms: 1_000 + elapsed_ms,
            elapsed_ms,
            kind,
        };
        for event in [
            rust_event(0, 0, EventKind::RecordingStarted),
            rust_event(
                1,
                10_000,
                EventKind::WaitStarted {
                    reason: WaitReason::CampaignProgress,
                },
            ),
            rust_event(
                2,
                10_000,
                EventKind::SceneStarted {
                    scene: Scene::FrozenContract,
                },
            ),
            rust_event(
                3,
                30_000,
                EventKind::WaitFinished {
                    reason: WaitReason::CampaignProgress,
                },
            ),
            rust_event(4, 40_000, EventKind::RecordingStopped),
        ] {
            writeln!(events, "{}", serde_json::to_string(&event).unwrap()).unwrap();
        }
        drop(events);

        let error = derive_cut_plan(directory, 2.0).unwrap_err();
        assert!(error.to_string().contains("contains a Rust semantic event"));
    }

    #[test]
    fn browser_and_capture_contracts_remain_fixed_in_source() {
        let source = include_str!("lib.rs");
        assert!(source.contains("--force-device-scale-factor=0.8"));
        assert!(source.contains("--audio-backend=pipewire"));
        assert!(source.contains("--no-damage"));
        assert!(!source.contains(&["default:true", "persistent:true"].join(",")));
        assert!(source.contains("--disable-input"));
        assert!(source.contains("restore_host_focus(&prior_focus)"));
        assert!(source.contains("remove_created_output_safely"));
        assert!(source.contains("no_initial_focus"));
        assert!(source.contains("alterzorder"));
        assert!(source.contains(SPOTIFY_TRACK_ID));
        assert!(!source.contains(&["Page", ".navigate"].concat()));
        assert!(!source.contains(&["Input", ".dispatchMouseEvent"].concat()));
    }

    #[test]
    fn codex_prompt_appends_exact_mode_session_and_storyboard_commands() {
        let temporary = TempDir::new().unwrap();
        let repo = temporary.path();
        fs::create_dir_all(repo.join("docs")).unwrap();
        fs::write(
            repo.join("docs/campaign-a-demo-agent-prompt.md"),
            "## Session mode and launch authority\nNever click the Campaign A control by any other route.\nNever invoke attune.campaign_worker launch.\n",
        )
        .unwrap();
        let executable = Path::new("/nix/store/demo path/bin/attune-demo-director's");
        let prompt = codex_prompt_for_executable(repo, "0123456789ab", true, executable).unwrap();
        assert!(prompt.contains("SESSION_MODE=LIVE_CAMPAIGN_A"));
        assert!(prompt.contains("start-run --repo"));
        assert!(prompt.contains("--session 0123456789ab"));
        assert!(prompt.contains("--scene frozen-contract"));
        assert!(!prompt.contains("--scene protocol"));
        let exact_invocation = format!("{} start-run", shell_quote(executable.to_str().unwrap()));
        assert!(prompt.contains(&exact_invocation));
        assert!(!prompt.contains("\nattune-demo-director start-run"));
    }
}
