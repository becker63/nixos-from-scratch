"""MCP Apps companion that renders validated research visualization specs."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
from typing import Any

from mcp.server.fastmcp import FastMCP

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "python"))
from visualization import validate_spec  # noqa: E402

RESOURCE_URI = "ui://attune-research-workbench/graph-v1.html"
RESOURCE_MIME = "text/html;profile=mcp-app"
MAX_SPEC_BYTES = 32_768


def create_server(widget_path: Path | None = None) -> FastMCP:
    widget_path = widget_path or HERE / "graph.html"
    html = widget_path.read_text(encoding="utf-8")
    server = FastMCP("Attune Research Graphs")

    @server.resource(RESOURCE_URI, mime_type=RESOURCE_MIME)
    def graph_widget() -> str:
        """Inline chart viewer for the current visualization result."""
        return html

    @server.tool(
        title="Show research graph",
        description=(
            "Render a grounded chart inline in the conversation from an "
            "attune.visualization.v1 specification. Supply measured values, "
            "explicit relationships, and provenance. Never invent measurements "
            "or edges. Reusing the same id replaces the prior chart."
        ),
        meta={"ui": {"resourceUri": RESOURCE_URI}},
    )
    def show_graph(spec: dict[str, Any]) -> dict[str, Any]:
        """Validate and return one bounded visualization specification."""
        if len(json.dumps(spec, ensure_ascii=False, allow_nan=False).encode("utf-8")) > MAX_SPEC_BYTES:
            raise ValueError("visualization exceeds 32768 bytes")
        return validate_spec(spec)

    return server


async def protocol_smoke(fixture: dict[str, Any]) -> None:
    """Exercise MCP initialize, discovery, resource delivery, call, and exit."""
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    params = StdioServerParameters(command=sys.executable, args=[str(Path(__file__).resolve())])
    async with stdio_client(params) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            tools = await session.list_tools()
            graph_tool = next((tool for tool in tools.tools if tool.name == "show_graph"), None)
            assert graph_tool is not None
            assert graph_tool.meta["ui"]["resourceUri"] == RESOURCE_URI
            resources = await session.read_resource(RESOURCE_URI)
            assert resources.contents and resources.contents[0].mimeType == RESOURCE_MIME
            assert "ui/notifications/tool-result" in resources.contents[0].text
            result = await session.call_tool("show_graph", {"spec": fixture})
            assert result.structuredContent == fixture
            rejected = await session.call_tool("show_graph", {"spec": {"schema": "attune.visualization.v0"}})
            assert rejected.isError


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-fixture", action="store_true")
    parser.add_argument("--widget", type=Path)
    args = parser.parse_args()
    server = create_server(args.widget)
    if args.check_fixture:
        fixture = HERE.parent / "visualizations.jsonl"
        specs = []
        for line in fixture.read_text(encoding="utf-8").splitlines():
            if line.strip():
                specs.append(validate_spec(json.loads(line)))
        asyncio.run(protocol_smoke(specs[0]))
        print("MCP initialize, tool discovery/call, widget resource, shared fixture, and child shutdown passed")
        return
    server.run(transport="stdio")


if __name__ == "__main__":
    main()
