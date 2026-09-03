/// The two scripts the EPUB reader runs through the navigator's `evaluateJavaScript`.
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

    /// Scrolls the block matching `selector` so it sits in the middle third of the viewport when it
    /// is not already there (spec §2.4.5 auto-scroll). Returns true when it scrolled.
    static func scrollIntoMiddle(selector: String) -> String {
        let escaped = selector
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        (function () {
          var el = document.querySelector('\(escaped)');
          if (!el) { return false; }
          var r = el.getBoundingClientRect();
          var h = window.innerHeight;
          var mid = (r.top + r.bottom) / 2;
          if (mid >= h / 3 && mid <= 2 * h / 3 && r.top >= 0 && r.bottom <= h) { return false; }
          el.scrollIntoView({ block: 'center', behavior: 'smooth' });
          return true;
        })();
        """
    }
}
