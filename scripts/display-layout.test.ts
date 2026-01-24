import { describe, expect, test } from "bun:test";
import {
  extractDisplayplacerArgs,
  nextLayout,
  parseShellWords,
} from "./display-layout";

describe("display layout", () => {
  test("parses the command printed by displayplacer list", () => {
    const output = `Persistent screen id: ABC

Execute the command below to set your screens to the current arrangement.
displayplacer "id:ABC mode:1 origin:(0,0) degree:0" "id:DEF mode:2 origin:(0,900) degree:0"
`;

    expect(extractDisplayplacerArgs(output)).toEqual([
      "id:ABC mode:1 origin:(0,0) degree:0",
      "id:DEF mode:2 origin:(0,900) degree:0",
    ]);
  });

  test("accepts an absolute displayplacer path and escaped text", () => {
    expect(
      extractDisplayplacerArgs(
        String.raw`/opt/homebrew/bin/displayplacer "id:ABC note:\"desk\" origin:(0,0)"`,
      ),
    ).toEqual(['id:ABC note:"desk" origin:(0,0)']);
  });

  test("parses quoted and unquoted shell words", () => {
    expect(parseShellWords(`displayplacer 'one two' three\\ four`)).toEqual([
      "displayplacer",
      "one two",
      "three four",
    ]);
  });

  test("toggles between the two layouts", () => {
    expect(nextLayout()).toBe("below");
    expect(nextLayout("below")).toBe("left");
    expect(nextLayout("left")).toBe("below");
  });
});
