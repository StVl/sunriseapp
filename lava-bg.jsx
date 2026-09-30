const LAVA_PALETTES = {
  Ember: { top: '#6a2204', mid: '#c24a0c', bot: '#ff7a1a', wax: ['#fff3a0', '#ffc44d'], glow: 'rgba(255,150,60,0.6)', glow2: 'rgba(230,110,30,0.4)' },
  Aurora: { top: '#0d1f7a', mid: '#1553c4', bot: '#1d8bff', wax: ['#7dffcf', '#2bd98f'], glow: 'rgba(80,200,255,0.5)', glow2: 'rgba(60,120,255,0.35)' },
  Glacier: { top: '#4a0a3f', mid: '#a3206f', bot: '#ff3fa4', wax: ['#ffffff', '#ffc2e6'], glow: 'rgba(255,120,200,0.5)', glow2: 'rgba(200,60,160,0.35)' },
};
const LTAU = Math.PI * 2;
const LAVA_BLOBS = [
  { x: 0.18, r: 110, f: 1, ph: 0.0, dx: 0.05 }, { x: 0.34, r: 80, f: 2, ph: 2.1, dx: 0.04 },
  { x: 0.50, r: 140, f: 1, ph: 3.6, dx: 0.06 }, { x: 0.64, r: 70, f: 2, ph: 5.2, dx: 0.05 },
  { x: 0.78, r: 120, f: 1, ph: 1.4, dx: 0.04 }, { x: 0.90, r: 60, f: 3, ph: 4.4, dx: 0.03 },
  { x: 0.42, r: 55, f: 3, ph: 0.9, dx: 0.07 }, { x: 0.08, r: 65, f: 2, ph: 3.0, dx: 0.03 },
];

function LavaBG({ palette = 'Ember', intensity = 1.1, period = 48, previewStart = 0, previewDur = 8, previewFrom = 0, dim = 0 }) {
  const ref = React.useRef(null);
  const [size, setSize] = React.useState({ w: 1100, h: 700 });
  const [T, setT] = React.useState(0);
  React.useEffect(() => {
    const ro = new ResizeObserver(([e]) => setSize({ w: e.contentRect.width || 1, h: e.contentRect.height || 1 }));
    ro.observe(ref.current);
    let raf, t0 = performance.now();
    const tick = (now) => { setT((now - t0) / 1000); raf = requestAnimationFrame(tick); };
    raf = requestAnimationFrame(tick);
    return () => { cancelAnimationFrame(raf); ro.disconnect(); };
  }, []);
  const pal = LAVA_PALETTES[palette] || LAVA_PALETTES.Ember;
  const { w: W, h: H } = size;
  const sc = H / 700, k = intensity;
  const p = ((T % period) / period) * LTAU;
  let bright = 1;
  if (previewStart) {
    const e = (Date.now() - previewStart) / 1000 / previewDur;
    if (e < 1) bright = previewFrom + (1 - previewFrom) * (e < 0 ? 0 : Math.pow(e, 1.8));
  }
  const circles = LAVA_BLOBS.map((b, i) => {
    const r = b.r * sc;
    const s = Math.sin(p * b.f + b.ph);
    const cy = H / 2 - s * (H / 2 + r * 0.2);
    const cx = W * (b.x + b.dx * Math.sin(p * (b.f + 1) + b.ph * 1.3));
    const v = Math.abs(Math.cos(p * b.f + b.ph));
    return <ellipse key={i} cx={cx} cy={cy} rx={r * (1 - 0.12 * v)} ry={r * (1 + 0.22 * v)} />;
  });
  const pool = (y, ph) => Array.from({ length: 5 }, (_, i) => (
    <ellipse key={'p' + y + i} cx={W * (i + 0.5) / 5 + 30 * sc * Math.sin(p + i + ph)} cy={y} rx={200 * sc * (W / H) / 1.77} ry={(70 + 25 * Math.sin(p * 2 + i * 1.7 + ph)) * sc} />
  ));
  const lava = <g>{pool(H + 30 * sc, 0)}{pool(-40 * sc, 2)}{circles}</g>;
  const bg = [
    `radial-gradient(60% 70% at ${50 + 18 * Math.sin(p)}% ${75 + 8 * Math.cos(p)}%, ${pal.glow}, transparent 70%)`,
    `radial-gradient(45% 55% at ${20 + 10 * Math.cos(p)}% 20%, ${pal.glow2}, transparent 70%)`,
    `radial-gradient(80% 90% at 100% 0%, rgba(0,0,0,0.35), transparent 60%)`,
    `linear-gradient(180deg, ${pal.top} 0%, ${pal.mid} 50%, ${pal.bot} 100%)`,
  ].join(', ');
  return (
    <div ref={ref} style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: bg }}>
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <filter id="lava-goo" x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur in="SourceGraphic" stdDeviation={28 * sc} result="b" />
            <feColorMatrix in="b" mode="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 36 -16" />
          </filter>
          <filter id="lava-glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation={60 * sc} /></filter>
          <radialGradient id="lava-wax" cx="50%" cy="100%" r="110%">
            <stop offset="0" stopColor={pal.wax[0]} /><stop offset="1" stopColor={pal.wax[1]} />
          </radialGradient>
        </defs>
        <g filter="url(#lava-glow)" fill={pal.wax[1]} opacity={0.55 * k}>{lava}</g>
        <g filter="url(#lava-goo)" fill="url(#lava-wax)" opacity={Math.min(1, 0.95 * k)}>{lava}</g>
      </svg>
      <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(90deg, rgba(0,0,0,0.3), transparent 18%, rgba(255,255,255,0.05) 30%, transparent 42%, transparent 80%, rgba(0,0,0,0.3))' }} />
      <div style={{ position: 'absolute', inset: 0, background: '#000', opacity: Math.max(1 - bright, dim), pointerEvents: 'none', transition: previewStart ? 'none' : 'opacity 1.4s cubic-bezier(0.4,0,0.2,1)' }} />
    </div>
  );
}
window.LavaBG = LavaBG;
