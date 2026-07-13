#!/usr/bin/env node
// Quiet Pointer app icon generator.
// Emits app-icon-1024.svg: n=5 superellipse body (Quiet Apps spec: 1024 canvas,
// 9% safe-area ring), sanctioned blue gradient, and the actual glove artwork
// path data lifted from HandCursorRenderer.swift (public-domain BenBois glove).

const fs = require('fs');

// ── Glove path data (verbatim from HandArt in HandCursorRenderer.swift) ──
const STROKE_W = 4.0614;
const CUFF = 'm89.471 1065.9c3.7268 6.1263-0.48379 10.049-6.16 12.947-8.0302 4.0988-27.898 2.1019-34.7-2.0136-6.2427-3.777-9.0128-9.3495-6.0403-14.184';
const HAND = 'm21.354 1021c-0.85728 15.682 13.892 40.298 31.364 46.018 9.0217 2.9538 29.326 3.8464 36.494-1.431 12.273-9.0365 18.48-20.686 21.285-35.088 0.99446-5.1051 1.707-10.986 0.95737-15.702-3.1898-20.064-14.951-20.048-19.514-20.76-2.7272-8.7246-12.699-15.044-26.068-12.391-0.1029-10.746 0.22553-17.365 1.1122-27.536 1.4832-17.013-27.986-20.845-26.491-0.0121 1.0183 14.187 0.02688 25.675-2.4993 39-3.4496 1.0381-15.746 11.529-16.641 27.901z';
const WEDGES = [
  'm63.838 981.04c0.0308 10.253 1.2148 18.225 7.2258 26.105-2.5091-6.5752-3.3692-19.666-3.1766-27.939z',
  'm93.471 992.23-3.8091 1.4862c1.929 5.5768 4.0509 11.842 7.1137 15.183-1.0804-2.6051-2.0771-11.978-3.3046-16.669z',
  'm36.249 991.71c-1.7026 12.092-6.1967 31.682-4.8107 38.213 1.185-3.9899 8.356-33.636 9.1333-39.703z',
];
const CREASES = [
  'm79.642 1058.3c4.0369-9.6783 3.976-12.465 5.1951-17.405',
  'm70.26 1059c1.6922-11.475 1.4242-17.152 1.8555-24.898',
  'm59.041 1059.5c0.0971-7.9806-0.59887-11.754-1.049-16.831',
];

// ── Minimal SVG path sampler for bbox (M/m L/l H/h V/v C/c S/s Z/z) ──
function samplePath(d) {
  const tok = d.match(/[MmLlHhVvCcSsZz]|-?\d*\.?\d+(?:e-?\d+)?/g);
  const pts = [];
  let i = 0, cmd = '', cur = [0, 0], start = [0, 0], lastCtrl = null;
  const num = () => parseFloat(tok[i++]);
  const cubic = (p0, c1, c2, p1) => {
    for (let t = 0; t <= 1; t += 0.05) {
      const u = 1 - t;
      pts.push([
        u*u*u*p0[0] + 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t*t*t*p1[0],
        u*u*u*p0[1] + 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t*t*t*p1[1],
      ]);
    }
  };
  while (i < tok.length) {
    if (/[A-Za-z]/.test(tok[i])) cmd = tok[i++];
    const rel = cmd === cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M': cur = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        start = [...cur]; pts.push([...cur]); cmd = rel ? 'l' : 'L'; lastCtrl = null; break;
      case 'L': cur = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        pts.push([...cur]); lastCtrl = null; break;
      case 'H': cur = [rel ? cur[0]+num() : num(), cur[1]]; pts.push([...cur]); lastCtrl = null; break;
      case 'V': cur = [cur[0], rel ? cur[1]+num() : num()]; pts.push([...cur]); lastCtrl = null; break;
      case 'C': {
        const c1 = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        const c2 = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        const p1 = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        cubic(cur, c1, c2, p1); cur = p1; lastCtrl = c2; break;
      }
      case 'S': {
        const c1 = lastCtrl ? [2*cur[0]-lastCtrl[0], 2*cur[1]-lastCtrl[1]] : [...cur];
        const c2 = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        const p1 = rel ? [cur[0]+num(), cur[1]+num()] : [num(), num()];
        cubic(cur, c1, c2, p1); cur = p1; lastCtrl = c2; break;
      }
      case 'Z': cur = [...start]; pts.push([...cur]); lastCtrl = null; break;
    }
  }
  return pts;
}

// ── Glove bbox + fingertip (min y = top of index finger in SVG coords) ──
const all = [CUFF, HAND, ...WEDGES, ...CREASES].flatMap(samplePath);
const xs = all.map(p => p[0]), ys = all.map(p => p[1]);
const bb = { x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) };
const handPts = samplePath(HAND);
const tip = handPts.reduce((a, p) => (p[1] < a[1] ? p : a)); // topmost point = fingertip
const cuffPts = samplePath(CUFF);
const cuffXs = cuffPts.map(p => p[0]);
const cuffBB = { x: Math.min(...cuffXs), w: Math.max(...cuffXs) - Math.min(...cuffXs) };
console.error('bbox', bb, 'tip', tip);

// ── Layout: fit glove into icon body, leave headroom for the sparkle ──
const SCALE = 480 / bb.h;                 // glove ≈ 480px tall on 1024 canvas
const gw = bb.w * SCALE, gh = bb.h * SCALE;
const gx = (1024 - gw) / 2 - (tip[0] - bb.x - bb.w / 2) * SCALE * 0.4; // nudge so tip reads centered
const gy = (1024 - gh) / 2 + 40;          // sit slightly low; sparkle above
const T = `translate(${gx.toFixed(1)} ${gy.toFixed(1)}) scale(${SCALE.toFixed(4)}) translate(${(-bb.x).toFixed(3)} ${(-bb.y).toFixed(3)})`;
const tipX = gx + (tip[0] - bb.x) * SCALE;
const tipY = gy + (tip[1] - bb.y) * SCALE;
console.error('tip on canvas', tipX.toFixed(1), tipY.toFixed(1));

// ── n=5 superellipse, half-axes 420 (82% body → 9% safe-area ring) ──
function squircle(cx, cy, r, n, samples) {
  const p = [];
  for (let i = 0; i <= samples; i++) {
    const t = (i / samples) * Math.PI * 2, ct = Math.cos(t), st = Math.sin(t);
    p.push([
      cx + Math.sign(ct) * Math.pow(Math.abs(ct), 2 / n) * r,
      cy + Math.sign(st) * Math.pow(Math.abs(st), 2 / n) * r,
    ]);
  }
  return 'M ' + p.map(q => q[0].toFixed(2) + ' ' + q[1].toFixed(2)).join(' L ') + ' Z';
}
const SQ = squircle(512, 512, 420, 5, 240);

// ── Poke burst: app's .sparkle style, verbatim from HandCursorView.burstPath.
// 12 thin rays, alternating outer / 0.62·outer, starting at inner = 0.34·outer,
// centered on the fingertip. Grey core + light halo, exactly like the app.
function sparkleBurst(cx, cy, outer, base) {
  const inner = outer * 0.34, n = 12, segs = [];
  for (let i = 0; i < n; i++) {
    const a = base + (i / n) * Math.PI * 2;
    const r = i % 2 === 0 ? outer : outer * 0.62;
    segs.push(`M ${(cx + Math.cos(a) * inner).toFixed(1)} ${(cy + Math.sin(a) * inner).toFixed(1)} L ${(cx + Math.cos(a) * r).toFixed(1)} ${(cy + Math.sin(a) * r).toFixed(1)}`);
  }
  return segs.join(' ');
}
// SVG y-down: finger points up → base angle -90°, matching fingerAngle in-app.
const burst = sparkleBurst(tipX, tipY, 150, -Math.PI / 2);
const BURST_LW = 15;              // core line width
const BURST_HALO_LW = BURST_LW + 8;

// ── Shadow rod: app's drawRod — cuff-width tapered rod with round cap,
// grey gradient (white .60 α.85 → .45 α.5 → .35 α0), fading straight down
// from the cuff (tilt comes from the group rotation, like leanRadians in-app).
const cuffW = cuffBB.w * SCALE;
const rodCX = gx + (cuffBB.x - bb.x + cuffBB.w / 2) * SCALE;
const rodTop = gy + gh - 22;      // overlap: start inside the cuff so it reads attached
const rodLen = 330;
const rodEnd = rodTop + rodLen;
const wTop = cuffW / 2, wEnd = cuffW * 0.55 / 2;
const rodPath = `M ${(rodCX - wTop).toFixed(1)} ${rodTop.toFixed(1)} L ${(rodCX - wEnd).toFixed(1)} ${rodEnd.toFixed(1)} A ${wEnd.toFixed(1)} ${wEnd.toFixed(1)} 0 0 0 ${(rodCX + wEnd).toFixed(1)} ${rodEnd.toFixed(1)} L ${(rodCX + wTop).toFixed(1)} ${rodTop.toFixed(1)} Z`;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0" stop-color="#E0731F"/>
      <stop offset="0.55" stop-color="#C75B12"/>
      <stop offset="1" stop-color="#7A3009"/>
    </linearGradient>
    <linearGradient id="rod" x1="0" y1="${rodTop.toFixed(1)}" x2="0" y2="${rodEnd.toFixed(1)}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#999999" stop-opacity="0.85"/>
      <stop offset="0.5" stop-color="#737373" stop-opacity="0.5"/>
      <stop offset="1" stop-color="#595959" stop-opacity="0"/>
    </linearGradient>
    <filter id="drop" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="14" stdDeviation="22" flood-color="#0E1116" flood-opacity="0.35"/>
    </filter>
    <clipPath id="clip"><path d="${SQ}"/></clipPath>
  </defs>

  <path d="${SQ}" fill="url(#body)"/>

  <g clip-path="url(#clip)">
    <g transform="rotate(-20 512 512)">
    <!-- shadow rod, same as in-app drawRod: cuff-width taper + round cap, fading grey -->
    <path d="${rodPath}" fill="url(#rod)"/>

    <!-- glove, actual app artwork -->
    <g filter="url(#drop)">
      <g transform="${T}" fill="none" stroke="none">
        <path d="${CUFF}" fill="#FFFFFF" stroke="#0E1116" stroke-width="${STROKE_W}" stroke-linecap="round" stroke-linejoin="round"/>
        <path d="${HAND}" fill="#FFFFFF" stroke="#0E1116" stroke-width="${STROKE_W}" stroke-linecap="round" stroke-linejoin="round"/>
        ${WEDGES.map(d => `<path d="${d}" fill="#0E1116"/>`).join('\n        ')}
        ${CREASES.map(d => `<path d="${d}" fill="none" stroke="#0E1116" stroke-width="${STROKE_W}" stroke-linecap="round"/>`).join('\n        ')}
      </g>
    </g>

    <!-- poke burst at the fingertip: app's .sparkle style, halo behind grey core -->
    <g fill="none" stroke-linecap="round">
      <path d="${burst}" stroke="rgba(242,242,242,0.9)" stroke-width="${BURST_HALO_LW}"/>
      <path d="${burst}" stroke="#6B6B6B" stroke-width="${BURST_LW}"/>
    </g>
    </g>
  </g>
</svg>
`;
fs.writeFileSync(__dirname + '/app-icon-1024.svg', svg);
console.error('wrote app-icon-1024.svg');
