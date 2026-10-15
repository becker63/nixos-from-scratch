use std::{
    collections::HashMap,
    io::{self, BufRead, BufReader, Write},
    process::{Child, ChildStdin, Command, Stdio},
    sync::mpsc::{self, Receiver},
    thread,
    time::Duration,
};

use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    symbols,
    text::{Line, Span},
    widgets::{Axis, Block, Borders, Chart, Dataset, Paragraph, Sparkline},
    Terminal,
};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Debug, Deserialize)]
struct ResearchEvent {
    schema: String,
    experiment: String,
    candidate: String,
    treatment: String,
    iteration: u64,
    best_objective: f64,
    recall_at_10: f64,
    harm: f64,
    cost_usd: f64,
    latency_ms: u64,
    state: String,
}

#[derive(Debug, Clone, Deserialize)]
struct VisualizationSpec {
    schema: String,
    id: String,
    #[serde(rename = "type")]
    kind: String,
    title: String,
    #[serde(default, rename = "xAxis")]
    x_axis: AxisSpec,
    #[serde(default, rename = "yAxis")]
    y_axis: AxisSpec,
    data: VisualizationData,
    provenance: serde_json::Value,
    epistemic: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct AxisSpec {
    #[serde(default)]
    label: String,
    #[serde(default)]
    unit: String,
}

#[derive(Debug, Clone, Deserialize)]
struct VisualizationData {
    #[serde(default)]
    series: Vec<VisualizationSeries>,
    #[serde(default)]
    nodes: Vec<serde_json::Value>,
    #[serde(default)]
    edges: Vec<serde_json::Value>,
    #[serde(default)]
    rows: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Deserialize)]
struct VisualizationSeries {
    label: String,
    x: Vec<f64>,
    y: Vec<f64>,
}

fn load_fixture() -> Result<Vec<ResearchEvent>, Box<dyn std::error::Error>> {
    const FIXTURE: &str = include_str!("../../events.jsonl");
    FIXTURE
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            let event: ResearchEvent = serde_json::from_str(line)?;
            if event.schema != "attune.research-event.v1" {
                return Err("unsupported event schema".into());
            }
            Ok(event)
        })
        .collect()
}

fn load_visualization() -> Result<VisualizationSpec, Box<dyn std::error::Error>> {
    const FIXTURE: &str = include_str!("../../visualizations.jsonl");
    let spec: VisualizationSpec = serde_json::from_str(
        FIXTURE
            .lines()
            .next()
            .ok_or("missing visualization fixture")?,
    )?;
    if spec.schema != "attune.visualization.v1" || spec.epistemic != "observed" {
        return Err("unsupported or ungrounded visualization fixture".into());
    }
    if spec
        .data
        .series
        .iter()
        .any(|series| series.x.len() != series.y.len())
    {
        return Err("invalid visualization series lengths".into());
    }
    Ok(spec)
}

enum ServerMessage {
    Message(Value),
    Closed,
}

struct AppServer {
    child: Child,
    input: Option<ChildStdin>,
    messages: Receiver<ServerMessage>,
    next_id: u64,
    log: Vec<String>,
    thread_id: Option<String>,
    thread_ready: bool,
    active_turn_id: Option<String>,
    visualization: VisualizationSpec,
    pending_approvals: HashMap<String, Value>,
}

impl AppServer {
    fn start() -> Result<Self, Box<dyn std::error::Error>> {
        let mut child = Command::new("codex")
            .args(["app-server", "--stdio"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?;
        let input = child.stdin.take().ok_or("missing App Server stdin")?;
        let output = child.stdout.take().ok_or("missing App Server stdout")?;
        let (sender, messages) = mpsc::channel();
        thread::spawn(move || {
            for line in BufReader::new(output).lines() {
                match line {
                    Ok(line) => match serde_json::from_str::<Value>(&line) {
                        Ok(message) => {
                            if sender.send(ServerMessage::Message(message)).is_err() {
                                return;
                            }
                        }
                        Err(error) => {
                            let _ = sender.send(ServerMessage::Message(json!({"method":"client/error","params":{"message":error.to_string()}})));
                        }
                    },
                    Err(_) => break,
                }
            }
            let _ = sender.send(ServerMessage::Closed);
        });
        let mut server = Self {
            child,
            input: Some(input),
            messages,
            next_id: 1,
            log: Vec::new(),
            thread_id: None,
            thread_ready: false,
            active_turn_id: None,
            visualization: load_visualization()?,
            pending_approvals: HashMap::new(),
        };
        server.request("initialize", json!({"clientInfo":{"name":"attune-ratatui-workbench","title":"Attune Research Workbench","version":"0.1.0"},"capabilities":{"experimentalApi":true}}))?;
        server.notify("initialized", json!({}))?;
        let models = server.request("model/list", json!({"limit":100}))?;
        let names: Vec<String> = models["data"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|model| model["displayName"].as_str().map(str::to_owned))
            .collect();
        server
            .log
            .push(format!("Codex models: {}", names.join(", ")));
        let args: Vec<String> = std::env::args().collect();
        if let Some(index) = args.iter().position(|arg| arg == "--resume") {
            server.thread_id = args.get(index + 1).cloned();
        }
        Ok(server)
    }

    fn send(&mut self, value: Value) -> Result<(), Box<dyn std::error::Error>> {
        let input = self
            .input
            .as_mut()
            .ok_or("Codex App Server input is closed")?;
        writeln!(input, "{value}")?;
        input.flush()?;
        Ok(())
    }

    fn notify(&mut self, method: &str, params: Value) -> Result<(), Box<dyn std::error::Error>> {
        self.send(json!({"jsonrpc":"2.0","method":method,"params":params}))
    }

    fn request(
        &mut self,
        method: &str,
        params: Value,
    ) -> Result<Value, Box<dyn std::error::Error>> {
        let id = self.next_id;
        self.next_id += 1;
        self.send(json!({"jsonrpc":"2.0","id":id,"method":method,"params":params}))?;
        loop {
            match self.messages.recv_timeout(Duration::from_secs(120))? {
                ServerMessage::Closed => {
                    return Err("Codex App Server closed its stdio stream".into())
                }
                ServerMessage::Message(message) if message["id"] == id => {
                    if let Some(error) = message.get("error") {
                        return Err(format!("{method}: {error}").into());
                    }
                    return Ok(message.get("result").cloned().unwrap_or(Value::Null));
                }
                ServerMessage::Message(message) => self.handle_message(message)?,
            }
        }
    }

    fn handle_message(&mut self, message: Value) -> Result<(), Box<dyn std::error::Error>> {
        let method = message["method"].as_str().unwrap_or("");
        if method.is_empty() {
            return Ok(());
        }
        let params = &message["params"];
        if message.get("id").is_some() && method == "item/tool/call" {
            let valid_tool = params["tool"] == "visualize";
            let candidate = params["arguments"].clone();
            let parsed = serde_json::from_value::<VisualizationSpec>(candidate.clone());
            let valid_spec = parsed.ok().filter(|spec| {
                spec.schema == "attune.visualization.v1"
                    && matches!(spec.epistemic.as_str(), "observed" | "inferred")
                    && spec
                        .data
                        .series
                        .iter()
                        .all(|series| series.x.len() == series.y.len())
                    && matches!(
                        spec.kind.as_str(),
                        "line"
                            | "bar"
                            | "histogram"
                            | "scatter"
                            | "heatmap"
                            | "tree"
                            | "timeline"
                            | "sparkline"
                            | "table"
                    )
                    && serde_json::to_vec(&candidate)
                        .map(|bytes| bytes.len() <= 32_768)
                        .unwrap_or(false)
            });
            if valid_tool {
                if let Some(spec) = valid_spec {
                    self.visualization = spec;
                    self.log
                        .push(format!("Codex visualization: {}", self.visualization.title));
                    self.send(json!({"jsonrpc":"2.0","id":message["id"],"result":{"success":true,"contentItems":[{"type":"inputText","text":"Visualization displayed with observed values and provenance."}]}}))?;
                } else {
                    self.send(json!({"jsonrpc":"2.0","id":message["id"],"result":{"success":false,"contentItems":[{"type":"inputText","text":"Invalid bounded visualization specification."}]}}))?;
                }
            } else {
                self.send(json!({"jsonrpc":"2.0","id":message["id"],"result":{"success":false,"contentItems":[{"type":"inputText","text":"Unsupported visualization tool."}]}}))?;
            }
            return Ok(());
        }
        match method {
            "item/agentMessage/delta" => {
                if let Some(delta) = params["delta"].as_str() {
                    self.log.push(delta.to_owned());
                }
            }
            "turn/completed" => {
                self.active_turn_id = None;
                self.log.push("Turn completed".into());
            }
            "turn/started" => self.log.push("Turn started".into()),
            _ if message.get("id").is_some()
                && (method.contains("Approval") || method.ends_with("/requestApproval")) =>
            {
                let id = message["id"].to_string();
                self.pending_approvals.insert(id.clone(), message.clone());
                let detail = serde_json::to_string(&message["params"]).unwrap_or_default();
                self.log.push(format!(
                    "Approval pending id={id}: {} · type :approve {id} or :deny {id}",
                    detail.chars().take(700).collect::<String>()
                ));
            }
            _ if message.get("id").is_some() && method == "item/tool/requestUserInput" => {
                self.log
                    .push("Codex requested user input; returned no answers".into());
                self.send(json!({"jsonrpc":"2.0","id":message["id"],"result":{"answers":{}}}))?;
            }
            _ if message.get("id").is_some() => {
                self.log
                    .push(format!("Unsupported App Server request: {method}"));
                self.send(json!({"jsonrpc":"2.0","id":message["id"],"error":{"code":-32601,"message":"unsupported server request"}}))?;
            }
            _ if method == "client/error" => self.log.push(
                params["message"]
                    .as_str()
                    .unwrap_or("protocol error")
                    .into(),
            ),
            _ => {}
        }
        Ok(())
    }

    fn prompt(&mut self, prompt: &str) -> Result<(), Box<dyn std::error::Error>> {
        let models = self.request("model/list", json!({"limit":100}))?;
        let model = models["data"]
            .as_array()
            .and_then(|data| {
                data.iter()
                    .find(|m| m["isDefault"] == true)
                    .or(data.first())
            })
            .and_then(|m| m["id"].as_str())
            .ok_or("no models available for this account")?
            .to_owned();
        let cwd = std::env::current_dir()?.to_string_lossy().to_string();
        let thread_id = if let Some(thread_id) = self.thread_id.clone() {
            if !self.thread_ready {
                self.request("thread/resume", json!({"threadId":thread_id,"cwd":cwd}))?;
                self.thread_ready = true;
            }
            thread_id
        } else {
            let thread = self.request("thread/start", json!({
                "cwd":cwd,"model":model,
                "dynamicTools":[{"type":"function","name":"visualize","description":"Show a grounded chart or relationship graph with provenance; updates replace a matching chart id.","inputSchema":{"type":"object","required":["schema","id","type","title","data","provenance","epistemic"],"properties":{"schema":{"const":"attune.visualization.v1"},"id":{"type":"string"},"type":{"enum":["line","bar","histogram","scatter","heatmap","tree","timeline","sparkline","table"]},"title":{"type":"string"},"xAxis":{"type":"object"},"yAxis":{"type":"object"},"data":{"type":"object"},"identifiers":{"type":"object"},"provenance":{"type":"object"},"epistemic":{"enum":["observed","inferred"]},"uncertainty":{"type":"object"},"update":{"type":"object"}},"additionalProperties":false}}],
                "developerInstructions":"Favor grounded visual explanations for meaningful structure, trends, comparisons, dependencies, or distributions. Use visualize proactively; avoid duplicating automatic charts. Never fabricate data or relationships."
            }))?;
            let thread_id = thread["thread"]["id"]
                .as_str()
                .ok_or("thread/start did not return a thread id")?
                .to_owned();
            self.thread_id = Some(thread_id.clone());
            self.thread_ready = true;
            thread_id
        };
        self.log.push(format!("Thread {thread_id}"));
        let turn = self.request(
            "turn/start",
            json!({"threadId":thread_id,"input":[{"type":"text","text":prompt}]}),
        )?;
        self.active_turn_id = turn["turn"]["id"].as_str().map(str::to_owned);
        Ok(())
    }

    fn interrupt(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if let (Some(thread_id), Some(turn_id)) = (&self.thread_id, &self.active_turn_id) {
            self.request(
                "turn/interrupt",
                json!({"threadId":thread_id,"turnId":turn_id}),
            )?;
            self.log.push("Interrupt requested".into());
        }
        Ok(())
    }

    fn resolve_approval(
        &mut self,
        id: &str,
        allow: bool,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let normalized = id
            .parse::<u64>()
            .map(|n| n.to_string())
            .unwrap_or_else(|_| format!("\"{id}\""));
        let Some(request) = self
            .pending_approvals
            .get(id)
            .cloned()
            .or_else(|| self.pending_approvals.get(&normalized).cloned())
        else {
            self.log.push(format!("No pending approval id={id}"));
            return Ok(());
        };
        let method = request["method"].as_str().unwrap_or("");
        if allow
            && !matches!(
                method,
                "item/commandExecution/requestApproval"
                    | "item/fileChange/requestApproval"
                    | "execCommandApproval"
                    | "applyPatchApproval"
            )
        {
            self.log.push(format!(
                "Approval type {method} cannot be accepted by this frontend"
            ));
            return Ok(());
        }
        self.send(json!({"jsonrpc":"2.0","id":request["id"],"result":{"decision":if allow {"accept"} else {"decline"}}}))?;
        self.pending_approvals.remove(id);
        self.log.push(format!(
            "Approval {}: {id}",
            if allow { "accepted" } else { "declined" }
        ));
        Ok(())
    }

    fn poll(&mut self) {
        while let Ok(message) = self.messages.try_recv() {
            match message {
                ServerMessage::Message(value) => {
                    let _ = self.handle_message(value);
                }
                ServerMessage::Closed => self.log.push("Codex server closed".into()),
            }
        }
    }
}

impl Drop for AppServer {
    fn drop(&mut self) {
        self.input.take();
        let deadline = std::time::Instant::now() + Duration::from_secs(3);
        loop {
            match self.child.try_wait() {
                Ok(Some(_)) => return,
                Ok(None) if std::time::Instant::now() < deadline => {
                    thread::sleep(Duration::from_millis(50))
                }
                _ => {
                    let _ = self.child.kill();
                    let _ = self.child.wait();
                    return;
                }
            }
        }
    }
}

fn fixture_summary(events: &[ResearchEvent]) -> String {
    let best = events
        .iter()
        .map(|event| event.best_objective)
        .fold(f64::NEG_INFINITY, f64::max);
    format!(
        "events={} experiment={} best={best:.2} treatments={}",
        events.len(),
        events[0].experiment,
        ["J0", "J32", "J100", "uniform"]
            .iter()
            .filter(|treatment| events.iter().any(|event| &event.treatment == **treatment))
            .copied()
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn draw(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    events: &[ResearchEvent],
    spec: &VisualizationSpec,
    prompt: &str,
    log: &[String],
) -> io::Result<()> {
    terminal.draw(|frame| {
        let outer = Layout::default().direction(Direction::Vertical).constraints([Constraint::Length(3), Constraint::Min(8), Constraint::Length(3), Constraint::Length(3), Constraint::Length(8)]).split(frame.area());
        frame.render_widget(Paragraph::new("Attune workbench · fixture observations · App Server on first prompt; Ctrl+C interrupts").block(Block::default().borders(Borders::ALL).title("Ratatui")), outer[0]);
        let body = Layout::default().direction(Direction::Horizontal).constraints([Constraint::Percentage(70), Constraint::Percentage(30)]).split(outer[1]);
        let points: Vec<Vec<(f64, f64)>> = spec.data.series.iter().map(|series| series.x.iter().copied().zip(series.y.iter().copied()).collect()).collect();
        let data: Vec<u64> = events.iter().filter(|e| e.treatment == "J0").map(|e| e.latency_ms).collect();
        let palette = [Color::Cyan, Color::Yellow, Color::Magenta, Color::Green];
        let datasets: Vec<Dataset> = spec.data.series.iter().zip(points.iter()).enumerate().map(|(i, (series, values))|
            Dataset::default().name(series.label.as_str()).marker(symbols::Marker::Braille).style(Style::default().fg(palette[i % palette.len()])).data(values)
        ).collect();
        let x_max = points.iter().flatten().map(|point| point.0).fold(1.0_f64, f64::max);
        if datasets.is_empty() {
            let description = serde_json::to_string(&spec.data.nodes.iter().chain(spec.data.edges.iter()).chain(spec.data.rows.iter()).collect::<Vec<_>>()).unwrap_or_default();
            frame.render_widget(Paragraph::new(description).block(Block::default().title(format!("{} · {} · {}", spec.title, spec.kind, spec.id)).borders(Borders::ALL)), body[0]);
        } else {
            frame.render_widget(Chart::new(datasets).block(Block::default().title(format!("{} · {} · {}", spec.title, spec.kind, spec.id)).borders(Borders::ALL))
            .x_axis(Axis::default().title(format!("{} ({})", spec.x_axis.label, spec.x_axis.unit)).bounds([0.0, x_max + 1.0]).labels(vec![Line::from("0"), Line::from(format!("{x_max:.0}"))]))
            .y_axis(Axis::default().title(format!("{} ({})", spec.y_axis.label, spec.y_axis.unit)).bounds([0.0, 1.0]).labels(vec![Line::from("0"), Line::from("0.5"), Line::from("1")])), body[0]);
        }
        frame.render_widget(Sparkline::default().block(Block::default().title("Evaluation latency ms").borders(Borders::ALL)).data(&data).style(Style::default().fg(Color::Yellow)), body[1]);
        let metrics = events.last().map(|event| format!("last: {} · recall@10 {:.2} · harm {:.2} · ${:.4} · {}ms · {}", event.candidate, event.recall_at_10, event.harm, event.cost_usd, event.latency_ms, event.state)).unwrap_or_default();
        frame.render_widget(Paragraph::new(metrics).block(Block::default().borders(Borders::ALL).title("Fixture metrics")), outer[2]);
        frame.render_widget(Paragraph::new(prompt).block(Block::default().borders(Borders::ALL).title("Prompt")), outer[3]);
        let lines: Vec<Line> = log.iter().rev().take(7).rev().map(|entry| Line::from(Span::styled(entry.as_str(), Style::default().add_modifier(Modifier::DIM)))).collect();
        frame.render_widget(Paragraph::new(lines).block(Block::default().borders(Borders::ALL).title("Codex stream · Enter sends; Esc quits")), outer[4]);
    })?;
    Ok(())
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let events = load_fixture()?;
    let default_visualization = load_visualization()?;
    if std::env::args().any(|arg| arg == "--check-fixture") {
        println!("{}", fixture_summary(&events));
        return Ok(());
    }
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;
    let mut prompt = String::new();
    let mut server: Option<AppServer> = None;
    let mut log = vec![fixture_summary(&events)];
    loop {
        if let Some(server) = server.as_mut() {
            server.poll();
            log = server.log.clone();
        }
        let spec = server
            .as_ref()
            .map(|active| &active.visualization)
            .unwrap_or(&default_visualization);
        draw(&mut terminal, &events, spec, &prompt, &log)?;
        if event::poll(Duration::from_millis(120))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
                    if let Some(server) = server.as_mut() {
                        if let Err(error) = server.interrupt() {
                            log.push(format!("Interrupt failed: {error}"));
                        }
                    }
                    continue;
                }
                match key.code {
                    KeyCode::Esc => break,
                    KeyCode::Backspace => {
                        prompt.pop();
                    }
                    KeyCode::Enter if !prompt.trim().is_empty() => {
                        let value = std::mem::take(&mut prompt);
                        if let Some((command, request_id)) = value.trim().split_once(' ') {
                            if matches!(command, ":approve" | ":deny") {
                                if let Some(server) = server.as_mut() {
                                    if let Err(error) =
                                        server.resolve_approval(request_id, command == ":approve")
                                    {
                                        log.push(format!("Approval response failed: {error}"));
                                    }
                                } else {
                                    log.push("No active Codex session".into());
                                }
                                continue;
                            }
                        }
                        if server.is_none() {
                            match AppServer::start() {
                                Ok(value) => server = Some(value),
                                Err(error) => log.push(format!("Codex startup failed: {error}")),
                            }
                        }
                        if let Some(server) = server.as_mut() {
                            if let Err(error) = server.prompt(&value) {
                                log.push(format!("Codex error: {error}"));
                            }
                        }
                    }
                    KeyCode::Char(ch) => prompt.push(ch),
                    _ => {}
                }
            }
        }
    }
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("research workbench: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixture_has_shared_events_and_metrics() {
        let events = load_fixture().unwrap();
        assert_eq!(events.len(), 8);
        assert_eq!(
            events
                .iter()
                .map(|e| e.treatment.as_str())
                .collect::<Vec<_>>(),
            ["J0", "J0", "J0", "J32", "J32", "J100", "J100", "uniform"]
        );
        assert!(events.iter().any(|e| e.state == "failed"));
        assert!(events.iter().any(|e| e.recall_at_10 > 0.7 && e.harm < 0.05));
    }

    #[test]
    fn both_frontends_read_the_same_visualization_contract() {
        let spec = load_visualization().unwrap();
        assert_eq!(spec.schema, "attune.visualization.v1");
        assert_eq!(spec.id, "fixture:treatment-objective");
        assert_eq!(
            spec.data
                .series
                .iter()
                .map(|series| series.label.as_str())
                .collect::<Vec<_>>(),
            ["J0", "J32", "J100", "uniform"]
        );
        assert_eq!(spec.provenance["eventCount"], 8);
    }
}
