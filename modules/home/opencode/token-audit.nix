{ pkgs }:

let
  opencodeTokenUsageSkill = pkgs.runCommand "opencode-token-usage-skill-0.1.0" { } ''
        skill="$out/opencode-codex-token-compare"
        mkdir -p "$skill/scripts"

        cat > "$skill/SKILL.md" <<'EOF'
    ---
    name: opencode-codex-token-compare
    description: Compare local Opencode token usage against Codex token/thread history. Use when the user asks about token reduction, fresh vs raw input, subscription-window efficiency, Magic Context/AFT impact, or how much more work Opencode buys versus Codex.
    ---

    # Opencode/Codex Token Comparison

    Use this skill to compare local Codex usage state with local Opencode usage traces.

    ## Data sources

    Codex:
    - `~/.codex/state_5.sqlite`: `threads.tokens_used`, `cwd`, `title`, timestamps.
    - `~/.codex/history.jsonl`: count user prompts per `session_id`.
    - `~/.codex/logs_2.sqlite`: optional operational warnings/errors.

    Opencode:
    - `~/.local/share/opencode/opencode-stable.db`: current stable session DB.
    - `~/.local/share/opencode/opencode.db`: older/legacy DB if useful.
    - `message.data.tokens`: token accounting.
    - `part.data`: tool usage, including `ctx_reduce`, `ctx_memory`, `bash`, `apply_patch`, AFT/PTY tools.

    AFT benchmarks:
    - `~/study/aft/docs/benchmarks.md`: search-index headline benchmarks.
    - `~/study/aft/benchmarks/**/results/*.json`: retrieval/agent benchmark result artifacts.
    - `~/study/aft/benchmarks/**/*REPORT*.md` and `*RESULTS*.md`: benchmark reports.
    - `~/study/aft/benchmarks/trigram-ab-results.json`: memory/query A/B benchmark.

    ## Token definitions

    For Opencode messages:
    - `raw_input = tokens.input + tokens.cache.read + tokens.cache.write`
    - `fresh_input = tokens.input + tokens.cache.write`
    - `generated = tokens.output + tokens.reasoning`
    - `cache_ratio = tokens.cache.read / raw_input`

    Use `raw_input` for total carried context and `fresh_input` for newly processed prompt burden. For subscription-window projections, show both because providers may meter cached tokens differently.

    ## Workflow

    1. Run the bundled script:

       ```bash
       python3 <skill-dir>/scripts/compare-token-usage.py
       ```

       If the skill runner provides a base directory note, use that directory for `<skill-dir>`. Otherwise locate the installed skill at `~/.config/opencode/skills/opencode-codex-token-compare`.

       Useful flags:
    - `--no-aft-benchmarks`: skip benchmark artifact scanning.
    - `--aft-root ~/study/aft`: choose an alternate AFT checkout.

    2. Read the script output before interpreting. Prefer same-shape comparisons:
    - Current Codex session vs current Opencode sessions for setup/debug work.
    - Historical Codex Attune sessions vs long Opencode sessions for migration/spec work.
    - Avoid comparing tiny one-message Opencode sessions against multi-hour Codex runs as if they are equivalent.

    3. In the answer, include:
    - Codex tokens per user prompt: current session if available, historical median/p75/p90 when useful.
    - Opencode raw and fresh input per user prompt.
    - Apparent multiplier: Codex tokens per prompt divided by Opencode raw/fresh per prompt.
    - Evidence of reduction mechanisms: `ctx_reduce`, `ctx_memory`, AFT-compressed `bash`, cache ratio, tool-call slope.
    - AFT benchmark context when relevant: search/retrieval quality, latency, compression savings, settle-time costs, and whether the benchmark is deterministic retrieval or agent-mode.
    - Caveats about sample size and work-shape mismatch.

    ## Interpretation guardrails

    - Do not claim a precise billing multiplier unless the user provided billing rules.
    - Say "raw context" for all prompt tokens including cache reads.
    - Say "fresh input" for uncached input plus cache writes.
    - Treat zero-token Opencode sessions as UI/test noise unless the user asks about them.
    - Treat AFT benchmark worktrees separately unless the user explicitly wants benchmark comparison.
    - Benchmark artifacts describe expected mechanism performance; do not blend them into observed Opencode/Codex usage totals.
    - A good projection is a range, not a point estimate.
    EOF

        cat > "$skill/scripts/compare-token-usage.py" <<'EOF'
    #!/usr/bin/env python3
    import argparse
    import collections
    import datetime as dt
    import json
    import pathlib
    import re
    import sqlite3
    import statistics

    HOME = pathlib.Path.home()

    def open_ro(path):
        return sqlite3.connect(f"file:{path}?mode=ro", uri=True)

    def when(ms_or_s):
        if ms_or_s is None:
            return None
        value = int(ms_or_s)
        if value > 10_000_000_000:
            value = value / 1000
        return dt.datetime.fromtimestamp(value)

    def read_codex_history():
        path = HOME / ".codex/history.jsonl"
        counts = collections.Counter()
        if not path.exists():
            return counts
        for line in path.read_text(errors="replace").splitlines():
            try:
                row = json.loads(line)
            except Exception:
                continue
            sid = row.get("session_id")
            if sid:
                counts[sid] += 1
        return counts

    def codex_summary():
        db = HOME / ".codex/state_5.sqlite"
        if not db.exists():
            return {"error": f"missing {db}"}
        prompt_counts = read_codex_history()
        con = open_ro(db)
        con.row_factory = sqlite3.Row
        rows = []
        for row in con.execute("select id,title,cwd,tokens_used,created_at,updated_at from threads"):
            prompts = prompt_counts.get(row["id"], 0)
            tokens = row["tokens_used"] or 0
            if prompts:
                per_prompt = tokens / prompts
                rows.append({
                    "id": row["id"],
                    "title": row["title"],
                    "cwd": row["cwd"],
                    "tokens": tokens,
                    "prompts": prompts,
                    "tokens_per_prompt": per_prompt,
                    "created": when(row["created_at"]),
                    "updated": when(row["updated_at"]),
                })
        con.close()
        usable = [r["tokens_per_prompt"] for r in rows if r["prompts"] >= 5]
        rows.sort(key=lambda r: r["tokens"], reverse=True)
        recent = sorted(rows, key=lambda r: r["updated"] or dt.datetime.min, reverse=True)[:8]
        stats = {}
        if usable:
            ordered = sorted(usable)
            stats = {
                "sessions_with_prompt_counts": len(rows),
                "sessions_prompts_ge_5": len(usable),
                "median_tokens_per_prompt": statistics.median(usable),
                "p75_tokens_per_prompt": statistics.quantiles(usable, n=4)[2] if len(usable) >= 4 else ordered[-1],
                "p90ish_tokens_per_prompt": ordered[min(len(ordered) - 1, int(len(ordered) * 0.9))],
            }
        return {"stats": stats, "top_by_tokens": rows[:10], "recent": recent}

    def opencode_db_summary(path):
        if not path.exists():
            return {"path": str(path), "missing": True}
        con = open_ro(path)
        con.row_factory = sqlite3.Row
        sessions = {r["id"]: dict(r) for r in con.execute("select * from session")}
        msg = {sid: collections.Counter() for sid in sessions}
        parts = {sid: collections.Counter() for sid in sessions}
        for row in con.execute("select session_id,data from message"):
            sid = row["session_id"]
            try:
                data = json.loads(row["data"])
            except Exception:
                continue
            tokens = data.get("tokens") or {}
            cache = tokens.get("cache") or {}
            msg[sid]["messages"] += 1
            msg[sid][f"role_{data.get('role') or 'unknown'}"] += 1
            for key in ("input", "output", "reasoning"):
                if isinstance(tokens.get(key), (int, float)):
                    msg[sid][key] += tokens[key]
            for key in ("read", "write"):
                if isinstance(cache.get(key), (int, float)):
                    msg[sid][f"cache_{key}"] += cache[key]
        for row in con.execute("select session_id,data from part"):
            sid = row["session_id"]
            try:
                data = json.loads(row["data"])
            except Exception:
                continue
            kind = data.get("type") or "unknown"
            parts[sid][f"part_{kind}"] += 1
            if kind == "tool":
                parts[sid][f"tool_{data.get('tool') or data.get('name') or 'unknown'}"] += 1
            if kind == "text":
                parts[sid]["text_chars"] += len(data.get("text") or "")
        rows = []
        for sid, session in sessions.items():
            c = msg[sid]
            p = parts[sid]
            raw = c["input"] + c["cache_read"] + c["cache_write"]
            fresh = c["input"] + c["cache_write"]
            user = c["role_user"]
            if c["messages"] == 0:
                continue
            rows.append({
                "id": sid,
                "title": session.get("title"),
                "directory": session.get("directory"),
                "messages": c["messages"],
                "user_prompts": user,
                "assistant_messages": c["role_assistant"],
                "raw_input": raw,
                "fresh_input": fresh,
                "cache_read": c["cache_read"],
                "cache_ratio": c["cache_read"] / raw if raw else 0,
                "output": c["output"],
                "reasoning": c["reasoning"],
                "generated": c["output"] + c["reasoning"],
                "tools": sum(v for k, v in p.items() if k.startswith("tool_")),
                "ctx_reduce": p["tool_ctx_reduce"],
                "ctx_memory": p["tool_ctx_memory"],
                "bash": p["tool_bash"],
                "apply_patch": p["tool_apply_patch"],
                "text_chars": p["text_chars"],
            })
        con.close()
        useful = [r for r in rows if r["user_prompts"] > 0 and r["raw_input"] > 0]
        total = collections.Counter()
        for r in useful:
            for key in ("messages", "user_prompts", "assistant_messages", "raw_input", "fresh_input", "cache_read", "output", "reasoning", "generated", "tools", "ctx_reduce", "ctx_memory", "bash", "apply_patch", "text_chars"):
                total[key] += r[key]
        summary = {
            "path": str(path),
            "sessions": len(rows),
            "useful_sessions": len(useful),
            "totals": dict(total),
        }
        if total["user_prompts"]:
            summary["per_user_prompt"] = {
                "raw_input": total["raw_input"] / total["user_prompts"],
                "fresh_input": total["fresh_input"] / total["user_prompts"],
                "generated": total["generated"] / total["user_prompts"],
                "tools": total["tools"] / total["user_prompts"],
                "cache_ratio": total["cache_read"] / total["raw_input"] if total["raw_input"] else 0,
            }
        rows.sort(key=lambda r: r["raw_input"], reverse=True)
        summary["top_sessions"] = rows[:8]
        return summary

    def compact_session(row):
        return {
            "title": row.get("title"),
            "directory": row.get("directory"),
            "user_prompts": row.get("user_prompts"),
            "raw_input": row.get("raw_input"),
            "fresh_input": row.get("fresh_input"),
            "cache_ratio": round(row.get("cache_ratio", 0), 3),
            "tools": row.get("tools"),
            "ctx_reduce": row.get("ctx_reduce"),
            "ctx_memory": row.get("ctx_memory"),
        }

    def roundish(value):
        if isinstance(value, float):
            return round(value, 4)
        return value

    def compact_value(value, depth=0):
        if depth >= 3:
            return "..."
        if isinstance(value, dict):
            out = {}
            for key, item in value.items():
                if isinstance(item, (str, int, float, bool)) or item is None:
                    out[key] = roundish(item)
                elif isinstance(item, dict):
                    out[key] = compact_value(item, depth + 1)
            return out
        if isinstance(value, list):
            return [compact_value(item, depth + 1) for item in value[:6]]
        return roundish(value)

    def summarize_result_json(path, data):
        rel = str(path)
        item = {"path": rel}
        if isinstance(data, list):
            item["kind"] = "list"
            item["items"] = len(data)
            if data and isinstance(data[0], dict) and "before" in data[0] and "after" in data[0]:
                repos = []
                for row in data:
                    before = ((row.get("before") or {}).get("rss_mb"))
                    after = ((row.get("after") or {}).get("rss_mb"))
                    repo = {"repo": row.get("repo"), "before_rss_mb": roundish(before), "after_rss_mb": roundish(after)}
                    if before and after:
                        repo["rss_reduction_pct"] = round((before - after) * 100 / before, 1)
                    repos.append(repo)
                item["kind"] = "trigram-ab"
                item["repos"] = repos
            return item
        if not isinstance(data, dict):
            item["kind"] = type(data).__name__
            return item
        item["benchmark"] = data.get("benchmark") or data.get("tool_name") or path.parent.name
        item["driver"] = data.get("driver")
        item["corpus"] = data.get("corpus")
        item["timestamp"] = data.get("timestamp")
        if "summary" in data:
            item["summary"] = compact_value(data["summary"])
        if "aggregate" in data:
            item["aggregate"] = compact_value(data["aggregate"])
        if "aggregates" in data and isinstance(data["aggregates"], list):
            aggregates = data["aggregates"]
            item["aggregate_count"] = len(aggregates)
            by_candidate = {}
            for row in aggregates:
                if not isinstance(row, dict):
                    continue
                candidate = row.get("candidate") or row.get("arm") or row.get("driver") or "unknown"
                current = by_candidate.get(candidate)
                if current is None or (row.get("mrr") or row.get("rank1_rate") or 0) > (current.get("mrr") or current.get("rank1_rate") or 0):
                    by_candidate[candidate] = row
            item["best_rows_by_candidate"] = [compact_value(row) for _, row in sorted(by_candidate.items())[:8]]
        if "results" in data and isinstance(data["results"], list):
            results = [row for row in data["results"] if isinstance(row, dict)]
            item["result_count"] = len(results)
            pass_keys = [key for key in ("pass", "success") if any(key in row for row in results)]
            for key in pass_keys:
                values = [bool(row.get(key)) for row in results if key in row]
                if values:
                    item[f"{key}_count"] = sum(values)
                    item[f"{key}_rate"] = round(sum(values) / len(values), 4)
            for key in ("recall", "mrr", "precisionAt1", "precisionAt5", "precisionAt10", "latencyMs", "wallTimeMs", "toolCalls"):
                vals = [row.get(key) for row in results if isinstance(row.get(key), (int, float))]
                if vals:
                    item[f"{key}_mean"] = round(sum(vals) / len(vals), 4)
            token_totals = [((row.get("tokens") or {}).get("total")) for row in results if isinstance(row.get("tokens"), dict)]
            token_totals = [v for v in token_totals if isinstance(v, (int, float))]
            if token_totals:
                item["tokens_total_mean"] = round(sum(token_totals) / len(token_totals), 2)
        return {k: v for k, v in item.items() if v not in (None, {}, [])}

    def summarize_markdown(path):
        text = path.read_text(errors="replace")
        title = None
        for line in text.splitlines():
            if line.startswith("#"):
                title = line.strip("# ").strip()
                break
        speedups = [int(m.group(1)) for m in re.finditer(r"\*\*(\d+)x\*\*", text)]
        saved = [int(m.group(1).replace(",", "")) for m in re.finditer(r"\b([0-9][0-9,]+)\s+saved\b", text, re.I)]
        settle = [float(m.group(1)) for m in re.finditer(r"\b([0-9]+(?:\.[0-9]+)?)s\b", text)]
        item = {"path": str(path), "title": title}
        if speedups:
            item["speedup_min_x"] = min(speedups)
            item["speedup_max_x"] = max(speedups)
            item["speedup_median_x"] = statistics.median(speedups)
        if saved:
            item["saved_token_mentions"] = saved[:8]
        if "did not settle" in text.lower() or "timeout" in text.lower():
            item["mentions_timeout_or_unsettled"] = True
        if settle:
            item["duration_mentions_s_max"] = max(settle)
        return {k: v for k, v in item.items() if v not in (None, {}, [])}

    def aft_benchmark_summary(root):
        root = pathlib.Path(root).expanduser()
        bench = root / "benchmarks"
        if not root.exists():
            return {"root": str(root), "missing": True}
        json_paths = []
        for path in bench.rglob("*.json") if bench.exists() else []:
            rel = path.relative_to(bench)
            rel_parts = set(rel.parts)
            if "corpora" in rel_parts or "fixtures" in rel_parts:
                continue
            if path.name.startswith("swe-bench-") or path.name in {"package.json", "tsconfig.json", "external-fixtures.json", "identifier-fusion-fixtures.json", "fixtures.json"}:
                continue
            if "results" in rel_parts or path.name in {"trigram-ab-results.json", "baseline.json"}:
                json_paths.append(path)
        md_paths = []
        candidates = [
            root / "docs/benchmarks.md",
            bench / "compression-tokens/REPORT.md",
            bench / "settle-time/RESULTS.md",
            bench / "codegraph-vs-aft-agent/FINDINGS.md",
        ]
        md_paths.extend([path for path in candidates if path.exists()])
        result_summaries = []
        for path in sorted(json_paths)[:40]:
            try:
                data = json.loads(path.read_text(errors="replace"))
            except Exception as exc:
                result_summaries.append({"path": str(path), "error": str(exc)})
                continue
            result_summaries.append(summarize_result_json(path, data))
        report_summaries = []
        for path in md_paths:
            try:
                report_summaries.append(summarize_markdown(path))
            except Exception as exc:
                report_summaries.append({"path": str(path), "error": str(exc)})
        return {
            "root": str(root),
            "json_artifacts_scanned": len(result_summaries),
            "markdown_reports_scanned": len(report_summaries),
            "json_results": result_summaries,
            "markdown_reports": report_summaries,
        }

    def main():
        parser = argparse.ArgumentParser(description="Compare Codex and Opencode token usage, optionally with AFT benchmark context.")
        parser.add_argument("--aft-root", default=str(HOME / "study/aft"), help="AFT checkout containing benchmarks/ and docs/benchmarks.md")
        parser.add_argument("--no-aft-benchmarks", action="store_true", help="Skip AFT benchmark artifact summary")
        args = parser.parse_args()

        codex = codex_summary()
        opencode = [
            opencode_db_summary(HOME / ".local/share/opencode/opencode-stable.db"),
            opencode_db_summary(HOME / ".local/share/opencode/opencode.db"),
        ]
        print("## Codex")
        print(json.dumps(codex["stats"], indent=2))
        print("recent:")
        for row in codex.get("recent", [])[:5]:
            print(json.dumps({
                "title": row["title"],
                "cwd": row["cwd"],
                "tokens": row["tokens"],
                "prompts": row["prompts"],
                "tokens_per_prompt": round(row["tokens_per_prompt"]),
                "updated": row["updated"].isoformat(sep=" ", timespec="seconds") if row["updated"] else None,
            }, ensure_ascii=False))
        for item in opencode:
            print("\n## Opencode", item["path"])
            if item.get("missing"):
                print("missing")
                continue
            print(json.dumps({
                "sessions": item["sessions"],
                "useful_sessions": item["useful_sessions"],
                "per_user_prompt": item.get("per_user_prompt", {}),
                "totals": item["totals"],
            }, indent=2))
            print("top_sessions:")
            for row in item["top_sessions"][:5]:
                print(json.dumps(compact_session(row), ensure_ascii=False))
        stable = opencode[0]
        if codex.get("stats") and stable.get("per_user_prompt"):
            print("\n## Multipliers vs stable Opencode")
            raw = stable["per_user_prompt"]["raw_input"]
            fresh = stable["per_user_prompt"]["fresh_input"]
            for label, value in codex["stats"].items():
                if not label.endswith("tokens_per_prompt"):
                    continue
                print(json.dumps({
                    "codex_baseline": label,
                    "codex_tokens_per_prompt": round(value),
                    "opencode_raw_multiplier": round(value / raw, 2) if raw else None,
                    "opencode_fresh_multiplier": round(value / fresh, 2) if fresh else None,
                }))
        if not args.no_aft_benchmarks:
            print("\n## AFT benchmarks")
            print(json.dumps(aft_benchmark_summary(args.aft_root), indent=2, ensure_ascii=False))

    if __name__ == "__main__":
        main()
    EOF

        chmod +x "$skill/scripts/compare-token-usage.py"
  '';

in
{
  inherit opencodeTokenUsageSkill;

  xdgConfigFiles = {
    "opencode/skills/opencode-codex-token-compare".source =
      "${opencodeTokenUsageSkill}/opencode-codex-token-compare";
  };
}
