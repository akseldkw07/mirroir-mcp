// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Registers the read_scrolling_list MCP tool: every screen of a list as overlapping images.
// ABOUTME: The work is in ReadScrollingList; this file only parses arguments and builds the result.

import Foundation
import HelperLib

extension MirroirMCP {
    static func registerReadScrollingListTool(server: MCPServer, registry: TargetRegistry) {
        server.registerTool(MCPToolDefinition(
            name: "read_scrolling_list",
            description: """
                Capture every screen of the current list on the mirrored iPhone, scrolling \
                down page by page. Starts from the top (scroll_to_top) unless from_top is \
                false, and stops at the end of the list or after max_pages. Consecutive \
                pages overlap so no row is lost between them; pages that don't overlap are \
                named in the summary. Returns a one-line summary, then one image per page, \
                top to bottom.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "max_pages": .object([
                        "type": .string("integer"),
                        "description": .string("Most pages to capture (default: 10)"),
                    ]),
                    "from_top": .object([
                        "type": .string("boolean"),
                        "description": .string("Scroll to the top first (default: true)"),
                    ]),
                ]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                // Opens iPhone Mirroring if it isn't running (the window lookup below needs it).
                if let error = ctx.input.prepareTarget(tag: "read_scrolling_list") { return .error(error) }
                guard let window = ctx.bridge.getWindowInfo() else {
                    return .error("Target '\(ctx.name)' window not found")
                }
                let maxPages = max(1, args["max_pages"]?.asInt() ?? 10)
                let fromTop = args["from_top"]?.asBool() ?? true
                switch ReadScrollingList.run(input: ctx.input, capture: ctx.capture,
                                             windowSize: window.size, maxPages: maxPages,
                                             fromTop: fromTop) {
                case .failed(let error):
                    return .error(error)
                case .unverified:
                    return .error("The screen could not be captured; nothing was read.")
                case .read(let result):
                    let summary = ReadScrollingList.summary(
                        pages: result.pages.count, reachedEnd: result.reachedEnd,
                        maxPages: maxPages, gaps: result.gaps)
                    let images = result.pages.map {
                        MCPContent.image($0.base64EncodedString(), mimeType: "image/png")
                    }
                    return MCPToolResult(content: [.text(summary)] + images, isError: false)
                }
            }
        ))
    }
}
