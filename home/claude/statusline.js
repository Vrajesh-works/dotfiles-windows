// Claude Code status line: "<model> | ctx: N% used". Reads the session JSON on stdin.
let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { raw += chunk; });
process.stdin.on('end', () => {
  let data = {};
  try { data = JSON.parse(raw); } catch { /* print what we can */ }
  const model = (data.model && data.model.display_name) || 'Claude';
  const used = data.context_window && data.context_window.used_percentage;
  process.stdout.write(typeof used === 'number' ? `${model} | ctx: ${Math.round(used)}% used` : model);
});
