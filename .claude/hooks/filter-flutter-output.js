#!/usr/bin/env node
/**
 * PreToolUse(Bash) hook: trim the noisiest Flutter/Dart command output before it
 * reaches the model's context.
 *
 * `flutter test` prints one progress line per test ("00:03 +12: some test"),
 * which is invisible in a real terminal because each line overwrites the last,
 * but lands in context in full when the output is captured. This repo has 17
 * test files including widget-render and screenshot suites, so a green run costs
 * thousands of tokens that say nothing.
 *
 * The rewrites below drop only the zero-failure progress lines (a failing line
 * reads "00:04 +12 -1: ..." and does not match) and cap the tail, so failures,
 * stack traces and summaries survive intact.
 *
 * Bypass: put a pipe or redirect in the command yourself, or add NOFILTER.
 */

let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let cmd;
  try {
    cmd = JSON.parse(raw).tool_input.command;
  } catch {
    return passthrough();
  }
  if (typeof cmd !== 'string' || !cmd.trim()) return passthrough();

  // Respect an explicit opt-out and never touch a command that already shapes
  // its own output.
  if (/NOFILTER/.test(cmd)) return passthrough();
  if (/[|>]/.test(cmd)) return passthrough();

  const rules = [
    // Passing progress lines only; "+N -M:" failure lines are kept.
    [/\bflutter\s+test\b/, "2>&1 | grep -vE '^[0-9]{2}:[0-9]{2} [+][0-9]+:' | tail -150"],
    [/\b(flutter|dart)\s+analyze\b/, "2>&1 | grep -vE '^Analyzing|^$' | tail -120"],
    [/\bflutter\s+build\b/, '2>&1 | tail -60'],
    [/\bflutter\s+pub\s+(get|upgrade|outdated)\b/, '2>&1 | tail -40'],
    [/\bpod\s+install\b/, '2>&1 | tail -30'],
  ];

  const rule = rules.find(([re]) => re.test(cmd));
  if (!rule) return passthrough();

  const updated = `${cmd.replace(/;\s*$/, '')} ${rule[1]}`;
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'allow',
        updatedInput: { command: updated },
      },
    })
  );
});

function passthrough() {
  process.stdout.write('{}');
}
