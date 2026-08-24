import { describe, expect, test } from "bun:test";
import { unwrap } from "./unwrap";

describe("unwrap", () => {
  test("joins prose lines and preserves paragraph breaks", () => {
    expect(
      unwrap(
        "Agents often hard wrap\nperfectly good prose.\n\nThis should be one line.\n",
      ),
    ).toBe(
      "Agents often hard wrap perfectly good prose.\n\nThis should be one line.\n",
    );
  });

  test("keeps Markdown structure while joining list continuations", () => {
    const input = `# Notes

- The first item has a
  wrapped continuation.
- The second item stays
on one logical line.

1. Ordered items work
   the same way.
2. Next item
`;

    expect(unwrap(input)).toBe(`# Notes

- The first item has a wrapped continuation.
- The second item stays on one logical line.

1. Ordered items work the same way.
2. Next item
`);
  });

  test("does not absorb structural Markdown into a list item", () => {
    const input = `- Item
# Heading

- Item
---

- Item
| A | B |

- Item
<div>
`;

    expect(unwrap(input)).toBe(input);
  });

  test("unwraps block quotes without merging quote levels", () => {
    const input = `> This quote is
> wrapped too.
>
> > Nested text is
> > kept separate.
`;

    expect(unwrap(input)).toBe(`> This quote is wrapped too.
>
> > Nested text is kept separate.
`);
  });

  test("preserves fenced code inside block quotes", () => {
    const input = `> Before
>
> \`\`\`ts
> const value =
>   doThing();
> \`\`\`
>
> After this is
> unwrapped.
`;

    expect(unwrap(input)).toBe(`> Before
>
> \`\`\`ts
> const value =
>   doThing();
> \`\`\`
>
> After this is unwrapped.
`);
  });

  test("preserves indentation for a later list paragraph", () => {
    const input = `- First paragraph.

  Second paragraph is
  wrapped.
`;

    expect(unwrap(input)).toBe(`- First paragraph.

  Second paragraph is wrapped.
`);
  });

  test("leaves fences, frontmatter, tables, and indented code alone", () => {
    const input = `---
title: A title
summary: still metadata
---

| Name | Value |
| --- | --- |
| one | two |

\`\`\`ts
const value =
  doThing();
\`\`\`

    indented
    code
`;

    expect(unwrap(input)).toBe(input);
  });

  test("preserves GFM tables without outer pipes", () => {
    const input = `Name | Value
--- | ---
one | two
three | four
`;

    expect(unwrap(input)).toBe(input);
  });

  test("does not mistake an opening thematic break for frontmatter", () => {
    const input = `---
This prose is
wrapped.
---
`;

    expect(unwrap(input)).toBe(`---
This prose is wrapped.
---
`);
  });

  test("honors explicit Markdown hard breaks", () => {
    expect(unwrap("keep this break  \nthen join\nthe rest\n")).toBe(
      "keep this break  \nthen join the rest\n",
    );
  });

  test("normalizes CRLF", () => {
    expect(unwrap("one\r\ntwo\r\n")).toBe("one two\n");
  });
});
