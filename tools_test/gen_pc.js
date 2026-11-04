// gen_pc.js —— 在 tools_test 里合成 package_config.json（离线环境用）
//
// 注意：pub 缓存里同一个包往往有多个版本（升级过），若全部塞进
// package_config，dart 会报 "Duplicate package name"。这里按包名去重，
// 只保留版本号最高的那个。
const fs = require('fs');
const CACHE = process.env.LOCALAPPDATA + '/Pub/Cache/hosted/pub.dev';
const SEP = String.fromCharCode(92); // 反斜杠

// 版本比较：按数值段逐段比，数字段优先于预发布标记。
function verCmp(a, b) {
  const pa = a.split(/[.\-+]/);
  const pb = b.split(/[.\-+]/);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] ?? '0';
    const y = pb[i] ?? '0';
    const nx = /^\d+$/.test(x);
    const ny = /^\d+$/.test(y);
    if (nx && ny) {
      const d = parseInt(x, 10) - parseInt(y, 10);
      if (d !== 0) return d;
    } else if (nx !== ny) {
      return nx ? 1 : -1;
    } else if (x !== y) {
      return x < y ? -1 : 1;
    }
  }
  return 0;
}

const best = new Map();
for (const d of fs.readdirSync(CACHE)) {
  const m = d.match(/^(.*)-(\d+\.\d+\.\d+.*)$/);
  if (!m) continue;
  const cur = best.get(m[1]);
  if (!cur || verCmp(m[2], cur.version) > 0) {
    best.set(m[1], { version: m[2], dir: d });
  }
}

const pkgs = [];
for (const [name, v] of best) {
  pkgs.push({
    name,
    rootUri: 'file:///' + CACHE.split(SEP).join('/') + '/' + v.dir,
    packageUri: 'lib/',
    languageVersion: '3.4',
  });
}

const seen = new Map();
for (const d of fs.readdirSync(CACHE)) {
  const m = d.match(/^(.*)-(\d+\.\d+\.\d+.*)$/);
  if (!m) continue;
  seen.set(m[1], (seen.get(m[1]) || 0) + 1);
}
const dups = [...seen].filter(([, n]) => n > 1).map(([k, n]) => `${k}(${n})`);

fs.mkdirSync('.dart_tool', { recursive: true });
fs.writeFileSync(
  '.dart_tool/package_config.json',
  JSON.stringify({ configVersion: 2, packages: pkgs }, null, 1),
);
console.log(
  'pkgs',
  pkgs.length,
  pkgs.some((p) => p.name === 'crypto') ? 'crypto OK' : 'crypto MISSING',
);
if (dups.length) {
  console.log('去重了', dups.length, '个多版本包:', dups.slice(0, 8).join(' '));
}
