// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Registers the scroll_to_top MCP tool: back to the top of the current list, verified.
// ABOUTME: The work is in ScrollToTop; this file only parses arguments and formats the result.

import Foundation
import HelperLib

extension MirroirMCP {
    static func registerScrollToTopTool(server: MCPServer, registry: TargetRegistry) {
        server.registerTool(MCPToolDefinition(
            name: "scroll_to_top",
            description: """
                Scroll the current list on the mirrored iPhone back to its top by tapping \
                the status-bar clock. Taps are sometimes lost, so it checks with an upward \
                swipe: if the list still follows, it taps again (up to 3 times). The result \
                says whether the top was verified and whether the screen moved.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([:]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                guard let window = ctx.bridge.getWindowInfo() else {
                    return .error("Target '\(ctx.name)' window not found")
                }
                let outcome = ScrollToTop.run(input: ctx.input, capture: ctx.capture,
                                              windowSize: window.size)
                if case .failed(let error) = outcome { return .error(error) }
                return .text(ScrollToTop.message(outcome) ?? "")
            }
        ))
    }
}
