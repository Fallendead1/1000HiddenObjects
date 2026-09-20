// Exact, unique-match text edits (used by one-off edit scripts).
const fs = require('fs');
exports.edit = (f, pairs) => {
  let s = fs.readFileSync(f, 'utf8');
  for (const [a, b] of pairs) {
    const n = s.split(a).length - 1;
    if (n !== 1) throw new Error(f + ': ' + (n ? 'not unique' : 'missing') + ': ' + a.slice(0, 80));
    s = s.split(a).join(b);
  }
  fs.writeFileSync(f, s);
};
