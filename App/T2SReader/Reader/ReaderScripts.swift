import Foundation

/// Scripts the EPUB reader runs through the navigator's `evaluateJavaScript`.
enum ReaderScripts {
    /// Reports the block under a viewport point: its text and the caret offset inside it
    /// (both UTF-16, as JavaScript counts), or null when the point is not on text.
    static func hitTest(x: Double, y: Double) -> String {
        """
        (function () {
          var range = document.caretRangeFromPoint(\(x), \(y));
          if (!range) { return null; }
          var node = range.startContainer;
          var blocks = ['P','H1','H2','H3','H4','H5','H6','LI','BLOCKQUOTE','DIV','SECTION','TD','DD','DT','PRE','FIGCAPTION','ARTICLE'];
          var block = node.nodeType === 1 ? node : node.parentElement;
          while (block && blocks.indexOf(block.tagName) < 0) { block = block.parentElement; }
          if (!block) { return null; }
          var offset = 0, found = false;
          var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, null);
          while (walker.nextNode()) {
            var text = walker.currentNode;
            if (text === node) { offset += range.startOffset; found = true; break; }
            offset += text.textContent.length;
          }
          if (!found && node.nodeType === 1) { offset = 0; }
          return { text: block.textContent, offset: offset };
        })();
        """
    }

    /// Scrolls the exact text quote from a locator into the viewport's middle third when needed
    /// (spec §2.4.5). Using the range's rect, rather than the containing block's rect, keeps long
    /// paragraphs from leaving the active word offscreen.
    static func scrollIntoMiddle(selector: String?, before: String?, highlight: String, after: String?) -> String {
        let selector = javaScriptString(selector)
        let before = javaScriptString(before)
        let highlight = javaScriptString(highlight)
        let after = javaScriptString(after)
        return """
        (function () {
          var selector = \(selector);
          var before = \(before) || '';
          var highlight = \(highlight);
          var after = \(after) || '';
          if (!highlight) { return false; }

          var root = selector ? document.querySelector(selector) : document.body;
          if (!root) { root = document.body; }
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
          var nodes = [];
          var text = '';
          while (walker.nextNode()) {
            var node = walker.currentNode;
            nodes.push(node);
            text += node.nodeValue || '';
          }

          var start = text.indexOf(highlight);
          var match = -1;
          while (start >= 0) {
            var end = start + highlight.length;
            var prefix = text.slice(Math.max(0, start - before.length), start);
            var suffix = text.slice(end, end + after.length);
            if ((!before || prefix === before) && (!after || suffix === after)) {
              match = start;
              break;
            }
            if (match < 0) { match = start; }
            start = text.indexOf(highlight, start + 1);
          }
          if (match < 0) { return false; }

          function boundary(offset) {
            var consumed = 0;
            for (var index = 0; index < nodes.length; index += 1) {
              var length = (nodes[index].nodeValue || '').length;
              if (offset <= consumed + length) {
                return { node: nodes[index], offset: offset - consumed };
              }
              consumed += length;
            }
            return null;
          }

          var rangeStart = boundary(match);
          var rangeEnd = boundary(match + highlight.length);
          if (!rangeStart || !rangeEnd) { return false; }
          var range = document.createRange();
          range.setStart(rangeStart.node, rangeStart.offset);
          range.setEnd(rangeEnd.node, rangeEnd.offset);
          var r = range.getBoundingClientRect();
          if (!r || (!r.width && !r.height)) { return false; }
          var h = window.innerHeight;
          var mid = (r.top + r.bottom) / 2;
          if (mid >= h / 3 && mid <= 2 * h / 3) { return false; }
          window.scrollBy({ top: mid - h / 2, behavior: 'smooth' });
          return true;
        })();
        """
    }

    private static func javaScriptString(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return "null" }
        return json
    }
}
