/**
 * The macOS open-hand pointer (the glove you get over something you can grab),
 * waving. On the page it rocks at the wrist now and then; still under reduced motion.
 */

// Finger centerlines in a 32-unit box, palm facing you: [x, top, bottom].
const FINGERS: [number, number, number][] = [
  [11.6, 7.2, 17],
  [15.2, 5, 17],
  [18.8, 5.8, 17],
  [22.2, 8.6, 18],
];

export function Hand({ wave = false }: { wave?: boolean }) {
  return (
    <g className={wave ? "hand-wave" : undefined} style={{ transformOrigin: "17px 28px" }}>
      <g transform="rotate(-14 17 28)">
        {/* palm outline */}
        <rect x="8.6" y="13.4" width="16.4" height="15" rx="6" fill="#1f1f1d" />
        {/* fingers: outline then glove, one at a time so the gaps show */}
        {FINGERS.map(([x, top, bottom]) => (
          <g key={x}>
            <path d={`M${x} ${bottom}V${top}`} stroke="#1f1f1d" strokeWidth="4.4" strokeLinecap="round" />
            <path d={`M${x} ${bottom}V${top}`} stroke="#ffffff" strokeWidth="2.2" strokeLinecap="round" />
          </g>
        ))}
        {/* thumb */}
        <path d="M10.6 21.2L6.4 15.6" stroke="#1f1f1d" strokeWidth="4.4" strokeLinecap="round" />
        <path d="M10.6 21.2L6.4 15.6" stroke="#ffffff" strokeWidth="2.2" strokeLinecap="round" />
        {/* palm */}
        <rect x="9.7" y="15.6" width="14.2" height="11.7" rx="5" fill="#ffffff" />
        <path d="M13.2 20.6c1.4 1.2 3 1.6 4.6 1.2" stroke="#1f1f1d" strokeWidth="0.9" strokeLinecap="round" fill="none" />
      </g>
      {/* motion lines */}
      <path d="M25.8 4.4a5 5 0 0 1 3.4 4.2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
      <path d="M24.6 7.2a2.6 2.6 0 0 1 1.8 2.2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
    </g>
  );
}

export function Mark({ className = "", wave = false }: { className?: string; wave?: boolean }) {
  return (
    <svg viewBox="0 0 32 32" className={className} aria-hidden xmlns="http://www.w3.org/2000/svg">
      <Hand wave={wave} />
    </svg>
  );
}
