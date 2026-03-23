#!/usr/bin/env python3
# md2html.py - Convert markdown files to styled HTML using mistune
# Usage: md2html.py <input.md> <output.html>
#        md2html.py --dir <input_dir> <output_dir>

import sys
import os
import re

# Add Contents/Library to path for mistune
app_bundle = os.environ.get("OMC_APP_BUNDLE_PATH", "")
if app_bundle:
    sys.path.insert(0, os.path.join(app_bundle, "Contents", "Library"))
else:
    # Fallback: assume script is in Contents/Resources/Scripts
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(script_dir, "..", "..", "Library"))

import mistune

HTML_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; line-height: 1.6; color: #333; background: #fff; }}
  h1 {{ border-bottom: 1px solid #eee; padding-bottom: 8px; }}
  h2 {{ border-bottom: 1px solid #f0f0f0; padding-bottom: 6px; margin-top: 24px; }}
  code {{ background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }}
  pre {{ background: #f4f4f4; padding: 16px; border-radius: 6px; overflow-x: auto; }}
  pre code {{ background: none; padding: 0; }}
  table {{ border-collapse: collapse; width: 100%; margin: 12px 0; }}
  th, td {{ border: 1px solid #ddd; padding: 8px 12px; text-align: left; }}
  th {{ background: #f8f8f8; }}
  blockquote {{ border-left: 4px solid #ddd; margin: 0; padding: 0 16px; color: #666; }}
  a {{ color: #0366d6; }}
</style>
</head>
<body>
{content}
</body>
</html>"""


def convert_file(input_path, output_path):
    with open(input_path, "r", encoding="utf-8") as f:
        md_text = f.read()

    html_body = mistune.html(md_text)

    # Rewrite .md links to .html
    html_body = re.sub(r'href="([^"]*?)\.md"', r'href="\1.html"', html_body)
    html_body = re.sub(r'href="([^"]*?)\.md#', r'href="\1.html#', html_body)

    title = os.path.basename(input_path).replace(".md", "")
    html = HTML_TEMPLATE.format(title=title, content=html_body)

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)


def convert_dir(input_dir, output_dir):
    import shutil
    for root, dirs, files in os.walk(input_dir):
        for name in files:
            input_path = os.path.join(root, name)
            rel_path = os.path.relpath(input_path, input_dir)
            if name.endswith(".md"):
                output_path = os.path.join(output_dir, rel_path.replace(".md", ".html"))
                convert_file(input_path, output_path)
            else:
                # Copy non-markdown files (e.g. .json templates) as-is
                output_path = os.path.join(output_dir, rel_path)
                os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
                shutil.copy2(input_path, output_path)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--dir":
        convert_dir(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3:
        convert_file(sys.argv[1], sys.argv[2])
    else:
        print("Usage: md2html.py <input.md> <output.html>", file=sys.stderr)
        print("       md2html.py --dir <input_dir> <output_dir>", file=sys.stderr)
        sys.exit(1)
