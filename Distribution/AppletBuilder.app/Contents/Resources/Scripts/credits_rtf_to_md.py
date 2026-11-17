#!/usr/bin/env python3
"""
credits_rtf_to_md.py - writes an applet's Credits.md from its Credits.rtf (macOS only).

The Command Engine's About window shows Contents/Resources/Credits.md, as Markdown, on macOS and on
Linux. Applets made before 6.0 have Credits.rtf, which macOS's standard About panel showed. AppletBuilder's
Build runs this once for such an applet, so its credits keep showing, on both platforms.

    credits_rtf_to_md.py <Credits.rtf> <Credits.md>

macOS's textutil turns the RTF into HTML; this script turns that HTML into Markdown:
- each RTF paragraph (one line) is a line; lines with no space after them in the RTF (CSS bottom
  margin 0) stay one Markdown paragraph, joined with hard line breaks; a line with space after it, or an
  empty line, ends the paragraph;
- italic and bold become *...* and **...**, links [text](url), or <url> when the text is the address;
- list items become "- " lines;
- alignment, fonts, sizes and colors are dropped: the About window draws the credits in its own style.

It never overwrites an existing Credits.md. Exit status 0 when Credits.md was written, 1 otherwise
(the reason on standard error).
"""

import html.parser
import os
import re
import subprocess
import sys
import tempfile

TEXTUTIL = "/usr/bin/textutil"

# Characters that would start Markdown syntax inside a line
_INLINE_SPECIALS = re.compile(r"([\\`*_\[\]<>~])")
# Syntax a line can start with: a heading, a list item, a quote, a numbered list item
_LINE_START = re.compile(r"^(\s*)([#>+\-]|\d+[.)])")


def escape_text(text):
    return _INLINE_SPECIALS.sub(r"\\\1", text)


def escape_line_start(line):
    return _LINE_START.sub(lambda m: m.group(1) + "\\" + m.group(2), line, count=1)


def paragraph_spacing(style_text):
    """{class name: True when that paragraph class has space after it} from textutil's <style>."""
    spacing = {}
    for match in re.finditer(r"p\.(\w+)\s*\{([^}]*)\}", style_text):
        name, body = match.group(1), match.group(2)
        spaced = False
        margin = re.search(r"margin:\s*([^;]+)", body)
        if margin:
            parts = margin.group(1).split()
            if len(parts) == 4:
                bottom = parts[2]
            elif len(parts) >= 1:
                bottom = parts[0] if len(parts) < 3 else parts[2]
            else:
                bottom = "0"
            number = re.match(r"([0-9.]+)", bottom)
            spaced = bool(number) and float(number.group(1)) > 0
        spacing[name] = spaced
    return spacing


class CreditsHTMLParser(html.parser.HTMLParser):
    """Collects the body's lines as (markdown, space_after, is_list_item)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_style = False
        self.style_text = ""
        self.in_body = False
        self.lines = []          # (markdown text, space after it, list item)
        self.parts = None        # the current line's pieces, None outside a line
        self.line_class = None
        self.line_is_item = False
        self.link_href = None
        self.link_parts = None
        self.emphasis = []       # the open emphasis tags' markers, innermost last

    # The current line, or the link's text inside a link
    def _sink(self):
        return self.link_parts if self.link_parts is not None else self.parts

    def _start_line(self, css_class, is_item):
        if self.parts is not None:
            self._end_line()
        self.parts = []
        self.line_class = css_class
        self.line_is_item = is_item

    def _end_line(self):
        if self.parts is None:
            return
        text = "".join(self.parts).replace("\u00a0", " ")
        text = re.sub(r"[ \t\r\n]+", " ", text).strip()
        self.lines.append((text, self.line_class, self.line_is_item))
        self.parts = None
        self.emphasis = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "style":
            self.in_style = True
        elif tag == "body":
            self.in_body = True
        elif not self.in_body:
            return
        elif tag == "p":
            self._start_line(attributes.get("class"), False)
        elif tag == "li":
            self._start_line(attributes.get("class"), True)
        elif tag == "br":
            # textutil writes an empty paragraph as <p><br></p>; inside text a <br> is a line break
            if self.parts is not None and "".join(self.parts).strip():
                self._sink().append("\u2028")
        elif tag in ("i", "em", "b", "strong"):
            marker = "**" if tag in ("b", "strong") else "*"
            self.emphasis.append(marker)
            if self.parts is None:
                self._start_line(None, False)
            self._sink().append("\u0001" + marker)
        elif tag == "a":
            if self.parts is None:
                self._start_line(None, False)
            self.link_href = attributes.get("href") or ""
            self.link_parts = []

    def handle_endtag(self, tag):
        if tag == "style":
            self.in_style = False
        elif tag == "body":
            self._end_line()
            self.in_body = False
        elif not self.in_body:
            return
        elif tag in ("p", "li"):
            self._end_line()
        elif tag in ("i", "em", "b", "strong"):
            if self.emphasis:
                marker = self.emphasis.pop()
                self._sink().append("\u0002" + marker)
        elif tag == "a" and self.link_parts is not None:
            text = "".join(self.link_parts)
            href = self.link_href or ""
            self.link_parts = None
            self.link_href = None
            plain = re.sub("[\u0001\u0002][*]+", "", text).strip()
            plain = re.sub(r"\\([\\`*_\[\]<>~])", r"\1", plain)  # as written, without the escapes
            if not href:
                self.parts.append(text)
            elif plain == href or plain == href.rstrip("/"):
                self.parts.append("<" + href.replace(">", "%3E") + ">")
            else:
                self.parts.append("[" + text + "](" + href.replace(" ", "%20").replace(")", "%29") + ")")

    def handle_data(self, data):
        if self.in_style:
            self.style_text += data
            return
        if not self.in_body:
            return
        if not data.strip() and self.parts is None:
            return  # whitespace between paragraphs
        if self.parts is None:
            self._start_line(None, False)
        self._sink().append(escape_text(data))


def place_emphasis(text):
    """Turns the open/close markers into Markdown emphasis that CommonMark reads as such: no empty pairs,
    and no space just inside a marker (the space moves outside it)."""
    # Drop empty pairs (textutil writes <i></i>)
    text = re.sub("\u0001([*]+)\\s*\u0002\\1", "", text)
    # Move spaces from inside the markers to outside them
    text = re.sub("\u0001([*]+)(\\s+)", lambda m: m.group(2) + "\u0001" + m.group(1), text)
    text = re.sub("(\\s+)\u0002([*]+)", lambda m: "\u0002" + m.group(2) + m.group(1), text)
    return text.replace("\u0001", "").replace("\u0002", "")


def html_to_markdown(html_text):
    parser = CreditsHTMLParser()
    parser.feed(html_text)
    parser.close()
    spacing = paragraph_spacing(parser.style_text)

    paragraphs = []   # each a list of lines
    current = []
    in_list = False
    for text, css_class, is_item in parser.lines:
        text = place_emphasis(text)
        if not text:
            if current:
                paragraphs.append(current)
                current = []
            in_list = False
            continue
        if is_item != in_list and current:
            paragraphs.append(current)
            current = []
        in_list = is_item
        line = "- " + text if is_item else escape_line_start(text)
        current.append(line)
        if spacing.get(css_class, False):
            paragraphs.append(current)
            current = []
            in_list = False
    if current:
        paragraphs.append(current)

    blocks = []
    for lines in paragraphs:
        if lines[0].startswith("- "):
            blocks.append("\n".join(line.replace("\u2028", " ") for line in lines))
        else:
            joined = "\\\n".join(lines)
            blocks.append(joined.replace("\u2028", "\\\n"))
    return "\n\n".join(blocks) + "\n" if blocks else ""


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: credits_rtf_to_md.py <Credits.rtf> <Credits.md>\n")
        return 1
    rtf_path, md_path = argv[1], argv[2]
    if os.path.exists(md_path):
        sys.stderr.write("%s exists; not overwritten\n" % md_path)
        return 1
    if not os.path.isfile(TEXTUTIL):
        sys.stderr.write("textutil not found (%s): Credits.rtf is converted on macOS only\n" % TEXTUTIL)
        return 1
    result = subprocess.run([TEXTUTIL, "-convert", "html", "-stdout", rtf_path],
                            stdin=subprocess.DEVNULL, capture_output=True)
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        sys.stderr.write("textutil could not read %s: %s\n" % (rtf_path, message or "status %d" % result.returncode))
        return 1
    markdown = html_to_markdown(result.stdout.decode("utf-8", "replace"))
    if not markdown.strip():
        sys.stderr.write("%s has no text\n" % rtf_path)
        return 1
    directory = os.path.dirname(os.path.abspath(md_path))
    try:
        handle, temp_path = tempfile.mkstemp(prefix=".Credits.", suffix=".md", dir=directory)
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write(markdown)
        os.chmod(temp_path, 0o644)
        if os.path.exists(md_path):  # appeared meanwhile
            os.unlink(temp_path)
            sys.stderr.write("%s exists; not overwritten\n" % md_path)
            return 1
        os.replace(temp_path, md_path)
    except OSError as error:
        sys.stderr.write("cannot write %s: %s\n" % (md_path, error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
