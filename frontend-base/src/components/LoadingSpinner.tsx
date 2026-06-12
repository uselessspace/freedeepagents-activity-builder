interface Props {
  size?: number;
  label?: string;
}

export function LoadingSpinner({ size = 24, label = 'Loading…' }: Props) {
  return (
    <div
      role="status"
      aria-label={label}
      style={{
        display: 'inline-block',
        width: size,
        height: size,
        border: '3px solid rgba(0,0,0,0.1)',
        borderTopColor: 'currentColor',
        borderRadius: '50%',
        animation: 'fda-spin 0.8s linear infinite',
      }}
    >
      <style>{`@keyframes fda-spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}
